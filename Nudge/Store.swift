import SwiftUI
import UIKit
import WidgetKit
import UserNotifications
import ActivityKit
import AVFoundation

struct NudgeRef: Identifiable {
    let id: UUID
    let last: Bool
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var tasks: [NudgeTask] = SharedStore.load()
    @Published var nudge: NudgeRef?          // drives the full-screen nudge
    @Published var showWins = false          // opened by the Sunday recap or the wins pill
    @Published private(set) var energyTick = 0

    private var d: UserDefaults { SharedStore.defaults }

    var openTasks: [NudgeTask] { SharedStore.openTasks(in: tasks) }
    /// What "Right now" draws from: open tasks that fit today's energy.
    var nowQueue: [NudgeTask] {
        guard let e = energy else { return openTasks }
        return openTasks.filter { ($0.effort ?? 1) <= e }
    }
    var current: NudgeTask? { nowQueue.first }
    var upNext: NudgeTask? { nowQueue.dropFirst().first }
    var hiddenByEnergy: Int { openTasks.count - nowQueue.count }
    var inbox: [NudgeTask] { tasks.filter { $0.doneAt == nil && $0.due == nil && $0.place == nil } }
    var placeTasks: [NudgeTask] { tasks.filter { $0.doneAt == nil && $0.place != nil } }
    var winsToday: Int { tasks.filter { $0.doneAt.map(Calendar.current.isDateInToday) ?? false }.count }
    var winsThisWeek: [NudgeTask] {
        let since = Date.now.addingTimeInterval(-7 * 86400)
        return tasks.filter { ($0.doneAt ?? .distantPast) > since }.sorted { $0.doneAt! > $1.doneAt! }
    }

    /// Today's tasks (done ones included), plus anything overdue from earlier days.
    var today: [NudgeTask] {
        let start = Calendar.current.startOfDay(for: .now)
        return tasks.filter { t in
            guard let due = t.due else { return false }
            return Calendar.current.isDateInToday(due) || (t.doneAt == nil && due < start)
        }.sorted { $0.due! < $1.due! }
    }

    // MARK: Energy (resets each day)

    var energy: Int? {
        _ = energyTick
        guard let day = d.object(forKey: Keys.energyDay) as? Date, Calendar.current.isDateInToday(day) else { return nil }
        let e = d.integer(forKey: Keys.energy)
        return (1...3).contains(e) ? e : nil
    }

    func setEnergy(_ e: Int?) {
        d.set(e ?? 0, forKey: Keys.energy)
        d.set(Date.now, forKey: Keys.energyDay)
        energyTick += 1
        syncActivity()
    }

    // MARK: Changes

    /// Runs when the app opens: drops old finished tasks and tops up nudges for later tasks.
    func reload() {
        tasks = SharedStore.load()
        let cutoff = Date.now.addingTimeInterval(-30 * 86400)
        if tasks.contains(where: { ($0.doneAt ?? .distantFuture) < cutoff }) {
            tasks.removeAll { ($0.doneAt ?? .distantFuture) < cutoff }   // nothing shows tasks finished 30+ days ago
            SharedStore.save(tasks)
        }
        rescheduleAll()
        syncActivity()
    }

    func add(_ t: NudgeTask) {
        tasks.append(t)
        commit()
    }

    /// Finishes the current step, or the whole task when it was the last step.
    func done(_ id: UUID) {
        guard let t = tasks.first(where: { $0.id == id }) else { return }
        if t.stepsDone + 1 < t.steps.count {
            update(id) { $0.stepsDone += 1 }
        } else {
            complete(id)
        }
    }

    func complete(_ id: UUID) {
        NudgeTask.complete(id, in: &tasks)
        Nudger.cancel(id)
        commit()
    }

    func snooze(_ id: UUID, minutes: Int) { update(id) { $0.due = .now.addingTimeInterval(Double(minutes * 60)) } }

    /// "I'm on it": you started, so the clock for "how long it really took" starts now.
    func onIt(_ id: UUID, minutes: Int) {
        update(id) { t in
            t.startedAt = t.startedAt ?? .now
            t.due = .now.addingTimeInterval(Double(minutes * 60))
        }
    }

    func doNow(_ id: UUID) { update(id) { $0.due = .now } }

    /// Picks a random brain-dump item that fits today's energy and makes it Right now.
    @discardableResult func pickOne() -> Bool {
        let pool = inbox.filter { energy == nil || ($0.effort ?? 1) <= energy! }
        guard let t = pool.randomElement() else { return false }
        doNow(t.id)
        return true
    }

    func startFocus(_ id: UUID) {
        let mins = max(1, d.integer(forKey: Keys.focusMins))
        update(id) { t in
            t.startedAt = t.startedAt ?? .now
            t.focusUntil = .now.addingTimeInterval(Double(mins * 60))
        }
    }

    func stopFocus(_ id: UUID) { update(id) { $0.focusUntil = nil } }

    func setSteps(_ id: UUID, _ steps: [String]) {
        update(id) { t in
            t.steps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            t.stepsDone = 0
        }
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        Nudger.cancel(id)
        commit()
    }

    func deleteAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        tasks = []
        commit()
    }

    /// Restore from a backup file: replaces the whole list.
    func replaceAll(_ restored: [NudgeTask]) {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        tasks = restored
        commit()
    }

    /// How long this kind of task really took last time (same title).
    func lastDuration(for title: String) -> TimeInterval? {
        tasks.filter { $0.title.caseInsensitiveCompare(title) == .orderedSame && $0.actualSeconds != nil }
            .max { $0.doneAt! < $1.doneAt! }?.actualSeconds
    }

    /// Re-plans every notification within iOS's limit of 64: place reminders, the weekly recap,
    /// focus timers, then nudges for the soonest tasks.
    func rescheduleAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let count = d.integer(forKey: Keys.nudgeCount), gap = d.integer(forKey: Keys.nudgeGap) * 60
        let buddy = d.string(forKey: Keys.buddyName) ?? ""
        var budget = 60

        if let home = SharedStore.home {
            for t in placeTasks.prefix(15) {
                Nudger.scheduleLocation(t, home: home)
                budget -= 1
            }
        }
        if d.bool(forKey: Keys.weeklyRecap) {
            Nudger.scheduleRecap(wins: winsThisWeek.count)
            budget -= 1
        }
        let focusing = openTasks.filter(\.isFocusing)
        for t in focusing {
            Nudger.scheduleFocusEnd(t)   // its regular nudges pause while the timer runs
            budget -= 1
        }
        let rest = openTasks.filter { !$0.isFocusing }
        for t in Nudger.withinBudget(rest, count: count, gapSeconds: gap, budget: max(0, budget)) {
            Nudger.schedule(t, count: count, gapSeconds: gap, buddyName: buddy)
        }
    }

    private func update(_ id: UUID, _ change: (inout NudgeTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[i])
        Nudger.cancel(id)   // also clears this task's old banners
        commit()
    }

    private func commit() {
        SharedStore.save(tasks)
        rescheduleAll()
        WidgetCenter.shared.reloadAllTimelines()
        syncActivity()
    }

    /// Shows the current task in the Dynamic Island once it's due within 15 minutes or a focus timer runs.
    // shortcut: iOS only lets an app start a Live Activity while it's open, so a task that
    // comes due with the app closed appears once you open the app or tap its nudge.
    func syncActivity() {
        let running = Activity<NudgeActivity>.activities
        var keep: String?
        if d.bool(forKey: Keys.liveActivity), ActivityAuthorizationInfo().areActivitiesEnabled,
           let t = current, let due = t.due, t.isFocusing || due <= .now.addingTimeInterval(15 * 60) {
            keep = t.id.uuidString
            let state = NudgeActivity.ContentState(title: t.title, step: t.currentStep, due: due,
                                                   focusUntil: t.isFocusing ? t.focusUntil : nil)
            let content = ActivityContent(state: state, staleDate: nil)
            if let mine = running.first(where: { $0.attributes.taskID == keep }) {
                Task { await mine.update(content) }
            } else {
                _ = try? Activity.request(attributes: NudgeActivity(taskID: t.id.uuidString), content: content)
            }
        }
        for a in running where a.attributes.taskID != keep {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

enum When: String, CaseIterable {
    case now, later, tomorrow, weekend, pick, leaveHome, arriveHome, someday

    var label: String {
        switch self {
        case .now: return "Right now"
        case .later: return "Later today"
        case .tomorrow: return "Tomorrow AM"
        case .weekend: return "This weekend"
        case .pick: return "Pick a time"
        case .leaveHome: return "When I leave home"
        case .arriveHome: return "When I get home"
        case .someday: return "No rush"
        }
    }

    var place: Place? {
        switch self {
        case .leaveHome: return .leaveHome
        case .arriveHome: return .arriveHome
        default: return nil
        }
    }

    /// Choices that make sense as a default for new brain dumps (and Siri).
    static var defaults: [When] { allCases.filter { $0 != .pick && $0.place == nil } }

    func date(from now: Date, picked: Date, cal: Calendar = .current) -> Date? {
        switch self {
        case .now: return now
        case .later: return now.addingTimeInterval(3 * 3600)
        case .tomorrow:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .weekend:
            return cal.nextDate(after: now, matching: DateComponents(hour: 10, minute: 0, weekday: 7), matchingPolicy: .nextTime)
        case .pick: return picked
        case .someday, .leaveHome, .arriveHome: return nil
        }
    }

    static func selfCheck() {
        let cal = Calendar.current, now = Date.now
        let tm = When.tomorrow.date(from: now, picked: now)!
        assert(tm > now && cal.component(.hour, from: tm) == 9, "Tomorrow AM should be 9:00 tomorrow")
        let we = When.weekend.date(from: now, picked: now)!
        assert(we > now && cal.component(.weekday, from: we) == 7, "This weekend should be a Saturday")
        assert(When.someday.date(from: now, picked: now) == nil, "No rush should stay unscheduled")
        var t = NudgeTask(title: "x", steps: ["a", "b"])
        assert(t.currentStep == "a")
        t.stepsDone = 2
        assert(t.currentStep == nil)
        assert(Nudger.isQuiet(hour: 23, bed: 23, wake: 7) && Nudger.isQuiet(hour: 3, bed: 23, wake: 7))
        assert(!Nudger.isQuiet(hour: 12, bed: 23, wake: 7) && !Nudger.isQuiet(hour: 7, bed: 23, wake: 7))
        assert(Nudger.isQuiet(hour: 2, bed: 1, wake: 9) && !Nudger.isQuiet(hour: 10, bed: 1, wake: 9))
        assert(!Nudger.isQuiet(hour: 5, bed: 6, wake: 6), "same start and end means no quiet hours")
        let soon = (1...4).map { NudgeTask(title: "t\($0)", due: now.addingTimeInterval(Double($0) * 3600)) }
        assert(Nudger.withinBudget(soon, count: 3, gapSeconds: 300, budget: 7).count == 2, "3 nudges each: only 2 tasks fit in 7")
        let overdue = NudgeTask(title: "late", due: now.addingTimeInterval(-3600))
        assert(Nudger.withinBudget([overdue] + soon, count: 3, gapSeconds: 300, budget: 6).count == 3, "fired nudges cost nothing")
        assert(LiveBackground.wrap(-5, 100) == 95 && LiveBackground.wrap(250, 100) == 50)
        assert((0..<500).allSatisfy { i in (0..<10).allSatisfy { (0..<1).contains(LiveBackground.rnd(i, $0)) } })

        // Repeats: a Friday 9 AM weekday task comes back Monday 9 AM; an old daily one lands after now.
        let friday = cal.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 6), matchingPolicy: .nextTime)!
        let monday = Repeat.weekdays.next(after: friday, now: friday)
        assert(cal.component(.weekday, from: monday) == 2 && cal.component(.hour, from: monday) == 9)
        let old = now.addingTimeInterval(-10 * 86400)
        let nextDaily = Repeat.daily.next(after: old, now: now)
        assert(nextDaily > now && nextDaily < now.addingTimeInterval(86400 + 60))

        // Completing a repeating task logs a win and moves it forward instead of finishing it.
        var list = [NudgeTask(title: "meds", due: now.addingTimeInterval(-60), repeatRule: .daily)]
        NudgeTask.complete(list[0].id, in: &list, now: now)
        assert(list.count == 2 && list[0].doneAt == nil && list[0].due! > now && list[1].doneAt == now)

        // Tasks saved by older versions (no new fields) still load.
        let legacy = #"[{"id":"\#(UUID().uuidString)","title":"old","steps":[],"stepsDone":0,"nag":true}]"#
        assert((try? JSONDecoder().decode([NudgeTask].self, from: Data(legacy.utf8)))?.first?.title == "old")

        // Get-ready time moves the first nudge earlier.
        let prep = NudgeTask(title: "dentist", due: now.addingTimeInterval(3600), prepMinutes: 45)
        assert(abs(prep.nudgeStart!.timeIntervalSince(now) - 900) < 1)
    }
}

enum Buddy {
    /// iOS never lets an app send a text silently, so this opens Messages ready to send.
    static func text(phone: String, body: String) {
        let number = phone.filter { $0.isNumber || $0 == "+" }
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if let url = URL(string: "sms:\(number)&body=\(encoded)") { UIApplication.shared.open(url) }
    }
}

func haptic() {
    guard SharedStore.defaults.bool(forKey: Keys.haptics) else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

/// Finishing something: a heavier thump plus a short chime.
@MainActor
enum Celebrate {
    private static var player: AVAudioPlayer?

    static func done() {
        if SharedStore.defaults.bool(forKey: Keys.haptics) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        guard SharedStore.defaults.bool(forKey: Keys.doneSound),
              let url = Bundle.main.url(forResource: "chime", withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)   // respects the silent switch, doesn't stop music
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

func formatMinutes(_ seconds: TimeInterval) -> String {
    let m = max(1, Int((seconds / 60).rounded()))
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
