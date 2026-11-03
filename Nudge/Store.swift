import SwiftUI
import UIKit
import WidgetKit
import UserNotifications

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

    func reload() { tasks = SharedStore.load() }

    func add(_ t: NudgeTask) {
        tasks.append(t)
        schedule(t)
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

    func rescheduleAll() { tasks.forEach { schedule($0) } }

    private func update(_ id: UUID, _ change: (inout NudgeTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[i])
        schedule(tasks[i])
        commit()
    }

    private func schedule(_ t: NudgeTask) {
        Nudger.schedule(t, count: d.integer(forKey: Keys.nudgeCount), gapSeconds: d.integer(forKey: Keys.nudgeGap) * 60,
                        buddyName: d.string(forKey: Keys.buddyName) ?? "")
    }

    private func commit() {
        SharedStore.save(tasks)
        WidgetCenter.shared.reloadAllTimelines()
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
