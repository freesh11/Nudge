// Compiled into both the app and the widget.
import Foundation
import SwiftUI
import UserNotifications
import AppIntents
import UIKit
import ActivityKit
import WidgetKit
import CoreLocation

enum Repeat: String, Codable, CaseIterable {
    case daily, weekdays, weekly, monthly

    var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    /// The first occurrence after `now`, stepping from the old due date so the time of day stays put.
    // shortcut: monthly from the 31st drifts to the 28th after February; fine for reminders.
    func next(after due: Date, now: Date = .now, cal: Calendar = .current) -> Date {
        var d = due
        for _ in 0..<5000 {
            d = step(d, cal)
            if d > now { return d }
        }
        return d
    }

    private func step(_ d: Date, _ cal: Calendar) -> Date {
        switch self {
        case .daily: return cal.date(byAdding: .day, value: 1, to: d) ?? d
        case .weekly: return cal.date(byAdding: .day, value: 7, to: d) ?? d
        case .monthly: return cal.date(byAdding: .month, value: 1, to: d) ?? d
        case .weekdays:
            var n = cal.date(byAdding: .day, value: 1, to: d) ?? d
            while cal.isDateInWeekend(n) { n = cal.date(byAdding: .day, value: 1, to: n) ?? n }
            return n
        }
    }
}

/// Remind on leaving or reaching Home instead of at a time.
enum Place: String, Codable {
    case leaveHome, arriveHome
}

struct NudgeTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var steps: [String] = []
    var stepsDone = 0
    var due: Date?              // nil = brain dump (or a place reminder)
    var nag = true
    var doneAt: Date?
    var repeatRule: Repeat?
    var prepMinutes = 0         // get-ready time: nudges start this long before `due`
    var estimateMinutes: Int?   // your guess
    var effort: Int?            // 1 easy, 2 medium, 3 hard
    var place: Place?
    var startedAt: Date?        // set by "I'm on it" or the focus timer
    var focusUntil: Date?

    var currentStep: String? { stepsDone < steps.count ? steps[stepsDone] : nil }

    /// When nudging starts: the due time minus get-ready time.
    var nudgeStart: Date? { due?.addingTimeInterval(Double(-prepMinutes * 60)) }

    /// How long it really took, when we know when you started.
    var actualSeconds: TimeInterval? {
        guard let start = startedAt, let end = doneAt else { return nil }
        let s = end.timeIntervalSince(start)
        return s > 30 && s < 12 * 3600 ? s : nil
    }

    var isFocusing: Bool { (focusUntil ?? .distantPast) > .now }

    /// Marks a task done. A repeating one logs a finished copy (for wins) and moves to its next time.
    static func complete(_ id: UUID, in tasks: inout [NudgeTask], now: Date = .now) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].doneAt == nil else { return }
        guard let rule = tasks[i].repeatRule else {
            tasks[i].doneAt = now
            tasks[i].focusUntil = nil
            return
        }
        var log = tasks[i]
        log.id = UUID()
        log.doneAt = now
        log.repeatRule = nil
        log.focusUntil = nil
        tasks.append(log)
        if let due = tasks[i].due { tasks[i].due = rule.next(after: due, now: now) }
        tasks[i].stepsDone = 0
        tasks[i].startedAt = nil
        tasks[i].focusUntil = nil
    }
}

/// Reads tasks saved by older versions, which don't have the newer fields yet.
extension NudgeTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
        stepsDone = try c.decodeIfPresent(Int.self, forKey: .stepsDone) ?? 0
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        nag = try c.decodeIfPresent(Bool.self, forKey: .nag) ?? true
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        repeatRule = try c.decodeIfPresent(Repeat.self, forKey: .repeatRule)
        prepMinutes = try c.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
        estimateMinutes = try c.decodeIfPresent(Int.self, forKey: .estimateMinutes)
        effort = try c.decodeIfPresent(Int.self, forKey: .effort)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        focusUntil = try c.decodeIfPresent(Date.self, forKey: .focusUntil)
    }
}

enum Keys {
    static let onboarded = "onboarded"
    static let bedtime = "bedtimeHour"
    static let nudgeCount = "nudgeCount"
    static let nudgeGap = "nudgeGap"
    static let accent = "accent"
    static let buddyName = "buddyName"
    static let buddyPhone = "buddyPhone"
    static let appearance = "appearance"
    static let matchIcon = "matchIcon"
    static let name = "name"
    static let showWins = "showWins"
    static let haptics = "haptics"
    static let sound = "sound"
    static let quietOn = "quietOn"
    static let wakeHour = "wakeHour"
    static let notYetMins = "notYetMins"
    static let onItMins = "onItMins"
    static let defaultWhen = "defaultWhen"
    static let defaultNag = "defaultNag"
    static let background = "background"
    static let liveActivity = "liveActivity"
    static let homeLat = "homeLat"
    static let homeLon = "homeLon"
    static let showCalendar = "showCalendar"
    static let weeklyRecap = "weeklyRecap"
    static let doneSound = "doneSound"
    static let focusMins = "focusMins"
    static let energy = "energy"
    static let energyDay = "energyDay"
}

enum SharedStore {
    // shortcut: if the signing profile lacks this app group, app and widget each fall back to
    // their own folder and the widget shows "All clear". Fix by signing with a profile that has it.
    static let appGroup = "group.com.nudge.adhd"
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var fileURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tasks.json")
    }

    static func load() -> [NudgeTask] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let tasks = try? JSONDecoder().decode([NudgeTask].self, from: data) { return tasks }
        // Unreadable file: keep a copy so the next save can't silently wipe your list.
        try? data.write(to: fileURL.appendingPathExtension("bak"))
        return []
    }

    static func save(_ tasks: [NudgeTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Open, scheduled tasks, earliest first. The first one is "right now".
    static func openTasks(in tasks: [NudgeTask]) -> [NudgeTask] {
        tasks.filter { $0.doneAt == nil && $0.due != nil }.sorted { $0.due! < $1.due! }
    }

    static var home: CLLocationCoordinate2D? {
        guard defaults.object(forKey: Keys.homeLat) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: Keys.homeLat), longitude: defaults.double(forKey: Keys.homeLon))
    }
}

enum Nudger {
    static let category = "NUDGE"
    static let recapID = "weekly-recap"

    static func setup() {
        let done = UNNotificationAction(identifier: "DONE", title: "Done", options: [])
        let onIt = UNNotificationAction(identifier: "ONIT", title: "I'm on it", options: [.foreground])
        let later = UNNotificationAction(identifier: "LATER5", title: "5 more min", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [done, onIt, later], intentIdentifiers: [], options: [])
        ])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func content(_ t: NudgeTask, body: String, last: Bool = false) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = t.title
        c.body = body
        c.sound = SharedStore.defaults.bool(forKey: Keys.sound) ? .default : nil
        c.categoryIdentifier = category
        c.userInfo = ["task": t.id.uuidString, "last": last]
        return c
    }

    /// Escalating nudges: one when nudging starts, then repeats every `gapSeconds` up to `count`.
    static func schedule(_ t: NudgeTask, count: Int, gapSeconds: Int, buddyName: String, quiet: Bool = true) {
        // Only pending ones: a nudge already sitting in Notification Center stays visible.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids(t.id))
        guard let start = t.nudgeStart, let due = t.due, t.doneAt == nil else { return }
        let total = t.nag ? min(max(1, count), 5) : 1
        for n in 0..<total {
            var fire = start.addingTimeInterval(Double(n * gapSeconds))
            if quiet, let wake = quietEnd(for: fire) {
                if n > 0 { continue }   // repeats wait; the first nudge moves to wake-up time
                fire = wake
            }
            let wait = fire.timeIntervalSinceNow
            guard wait > 1 else { continue }
            let last = total > 1 && n == total - 1
            let body: String
            if n == 0 && t.prepMinutes > 0 {
                body = "Start getting ready. It's at \(due.formatted(date: .omitted, time: .shortened))."
            } else if last && !buddyName.isEmpty {
                body = "Last nudge. Want to text \(buddyName) for backup?"
            } else if let step = t.currentStep {
                body = "Just do this part: \(step)"
            } else {
                body = "Just start. Two minutes counts."
            }
            let c = content(t, body: body, last: last)
            if total > 1 { c.subtitle = "Nudge \(n + 1) of \(total)" }
            add("\(t.id.uuidString)-\(n)", c, UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
        }
    }

    /// Fires when you leave or reach Home. Needs location permission; iOS watches the area, not the app.
    static func scheduleLocation(_ t: NudgeTask, home: CLLocationCoordinate2D) {
        guard let place = t.place, t.doneAt == nil else { return }
        let region = CLCircularRegion(center: home, radius: 150, identifier: t.id.uuidString)
        region.notifyOnExit = place == .leaveHome
        region.notifyOnEntry = place == .arriveHome
        let lead = place == .leaveHome ? "Before you go" : "You're home"
        let c = content(t, body: "\(lead): \(t.currentStep ?? t.title)")
        add("\(t.id.uuidString)-0", c, UNLocationNotificationTrigger(region: region, repeats: t.repeatRule != nil))
    }

    static func scheduleFocusEnd(_ t: NudgeTask) {
        guard let end = t.focusUntil, end.timeIntervalSinceNow > 1 else { return }
        let c = content(t, body: "Time's up. Keep going, or call it a win?")
        c.categoryIdentifier = ""
        add("\(t.id.uuidString)-focus", c, UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false))
    }

    /// Sunday 6 PM. Re-planned on every change, so the count stays current.
    static func scheduleRecap(wins: Int, at date: Date? = nil) {
        let c = UNMutableNotificationContent()
        c.title = "Your week"
        c.body = wins > 0 ? "You finished \(wins) things this week. Tap to see them." : "New week, fresh start. You've got this."
        c.sound = SharedStore.defaults.bool(forKey: Keys.sound) ? .default : nil
        c.userInfo = ["recap": true]
        let trigger: UNNotificationTrigger = date.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false) }
            ?? UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18, minute: 0, weekday: 1), repeats: false)
        add(recapID, c, trigger)
    }

    private static func add(_ id: String, _ c: UNNotificationContent, _ trigger: UNNotificationTrigger) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    /// If `date` falls in quiet hours, when they end; otherwise nil.
    static func quietEnd(for date: Date, cal: Calendar = .current) -> Date? {
        let d = SharedStore.defaults
        guard d.bool(forKey: Keys.quietOn) else { return nil }
        let wake = d.integer(forKey: Keys.wakeHour)
        guard isQuiet(hour: cal.component(.hour, from: date), bed: d.integer(forKey: Keys.bedtime), wake: wake) else { return nil }
        return cal.nextDate(after: date, matching: DateComponents(hour: wake, minute: 0), matchingPolicy: .nextTime)
    }

    /// Handles windows that cross midnight (23→7) and ones that don't (1→9).
    static func isQuiet(hour h: Int, bed: Int, wake: Int) -> Bool {
        bed > wake ? (h >= bed || h < wake) : (h >= bed && h < wake)
    }

    static func ids(_ id: UUID) -> [String] { (0..<5).map { "\(id.uuidString)-\($0)" } + ["\(id.uuidString)-focus"] }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids(id))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids(id))
    }

    /// iOS keeps only 64 pending notifications per app and silently drops the rest.
    /// Takes tasks soonest-first and keeps those whose future nudges fit in `budget`.
    static func withinBudget(_ soonestFirst: [NudgeTask], count: Int, gapSeconds: Int, budget: Int = 60, now: Date = .now) -> [NudgeTask] {
        var used = 0, picked: [NudgeTask] = []
        for t in soonestFirst {
            guard let start = t.nudgeStart else { continue }
            let total = t.nag ? min(max(1, count), 5) : 1
            let need = (0..<total).filter { start.addingTimeInterval(Double($0 * gapSeconds)) > now }.count
            if used + need > budget { break }
            used += need
            picked.append(t)
        }
        return picked
    }
}

/// The current task, shown in the Dynamic Island and on the Lock Screen.
struct NudgeActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var step: String?
        var due: Date
        var focusUntil: Date?
    }
    var taskID: String
}

/// Done from the widget, Lock Screen or Dynamic Island.
/// LiveActivityIntent runs it in the app's process, so it can also close the Live Activity.
// shortcut: a repeating task's next nudges get planned the next time the app opens.
struct CompleteTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark done"
    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        var tasks = SharedStore.load()
        if let id = UUID(uuidString: taskID) {
            NudgeTask.complete(id, in: &tasks)
            SharedStore.save(tasks)
            Nudger.cancel(id)
        }
        for activity in Activity<NudgeActivity>.activities where activity.attributes.taskID == taskID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A color that switches with light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Accent: Identifiable {
    let id: String
    let color: Color
}

enum Theme {
    static let ink = Color(light: 0x15171C, dark: 0xF1F2F4)      // main text
    static let bg = Color(light: 0xF4F5F7, dark: 0x0E0F12)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1E24)
    static let grey = Color(light: 0x5B6170, dark: 0xA3A9B6)
    static let line = Color(light: 0xD5D8DF, dark: 0x33363F)
    static let link = Color(light: 0x3B4CCA, dark: 0x9AABFF)
    static let indigo = Color(hex: 0x3B4CCA)                      // selected chips, always with white text
    static let night = Color(hex: 0x15171C)                       // the always-dark nudge and time cards
    static let onAccent = Color(hex: 0x15171C)                    // text on any accent color
    static let green = Color(hex: 0x1F7A55)
    static let accents = [
        Accent(id: "orange", color: Color(hex: 0xFF6B2C)),
        Accent(id: "mint", color: Color(hex: 0x4FD1A5)),
        Accent(id: "yellow", color: Color(hex: 0xFFC233)),
        Accent(id: "periwinkle", color: Color(hex: 0x8FA2FF)),
        Accent(id: "pink", color: Color(hex: 0xFF8AC2)),
        Accent(id: "sky", color: Color(hex: 0x5CC8FF)),
    ]
    static func accent(_ name: String) -> Color { accents.first { $0.id == name }?.color ?? accents[0].color }
    static func scheme(_ appearance: String) -> ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
}
