import SwiftUI
import UIKit
import WidgetKit
import UserNotifications
import ActivityKit

struct NudgeRef: Identifiable {
    let id: UUID
    let last: Bool
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var tasks: [NudgeTask] = SharedStore.load()
    @Published var nudge: NudgeRef?          // drives the full-screen nudge

    private var d: UserDefaults { SharedStore.defaults }

    var openTasks: [NudgeTask] { SharedStore.openTasks(in: tasks) }
    var current: NudgeTask? { openTasks.first }
    var upNext: NudgeTask? { openTasks.dropFirst().first }
    var inbox: [NudgeTask] { tasks.filter { $0.doneAt == nil && $0.due == nil } }
    var winsToday: Int { tasks.filter { $0.doneAt.map(Calendar.current.isDateInToday) ?? false }.count }

    /// Today's tasks (done ones included), plus anything overdue from earlier days.
    var today: [NudgeTask] {
        let start = Calendar.current.startOfDay(for: .now)
        return tasks.filter { t in
            guard let due = t.due else { return false }
            return Calendar.current.isDateInToday(due) || (t.doneAt == nil && due < start)
        }.sorted { $0.due! < $1.due! }
    }

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
        update(id) { t in
            if t.stepsDone + 1 < t.steps.count { t.stepsDone += 1 } else { t.doneAt = .now }
        }
    }

    func complete(_ id: UUID) { update(id) { $0.doneAt = .now } }
    func snooze(_ id: UUID, minutes: Int) { update(id) { $0.due = .now.addingTimeInterval(Double(minutes * 60)) } }
    func doNow(_ id: UUID) { update(id) { $0.due = .now } }

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

    /// Re-plans every nudge, soonest tasks first, within iOS's notification limit.
    func rescheduleAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let count = d.integer(forKey: Keys.nudgeCount), gap = d.integer(forKey: Keys.nudgeGap) * 60
        let buddy = d.string(forKey: Keys.buddyName) ?? ""
        for t in Nudger.withinBudget(openTasks, count: count, gapSeconds: gap) {
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

    /// Shows the current task in the Dynamic Island once it's due within 15 minutes.
    // shortcut: iOS only lets an app start a Live Activity while it's open, so a task that
    // comes due with the app closed appears once you open the app or tap its nudge.
    func syncActivity() {
        let running = Activity<NudgeActivity>.activities
        var keep: String?
        if d.bool(forKey: Keys.liveActivity), ActivityAuthorizationInfo().areActivitiesEnabled,
           let t = current, let due = t.due, due <= .now.addingTimeInterval(15 * 60) {
            keep = t.id.uuidString
            let content = ActivityContent(state: NudgeActivity.ContentState(title: t.title, step: t.currentStep, due: due), staleDate: nil)
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
    case now, later, tomorrow, weekend, pick, someday

    var label: String {
        switch self {
        case .now: return "Right now"
        case .later: return "Later today"
        case .tomorrow: return "Tomorrow AM"
        case .weekend: return "This weekend"
        case .pick: return "Pick a time"
        case .someday: return "No rush"
        }
    }

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
        case .someday: return nil
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
