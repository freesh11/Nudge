// Compiled into both the app and the widget.
import Foundation
import SwiftUI
import UserNotifications
import AppIntents
import UIKit

struct NudgeTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var steps: [String] = []
    var stepsDone = 0
    var due: Date?          // nil = sitting in the brain dump, unscheduled
    var nag = true
    var doneAt: Date?

    var currentStep: String? { stepsDone < steps.count ? steps[stepsDone] : nil }
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
}

enum Nudger {
    static let category = "NUDGE"

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

    /// Escalating nudges: one at the due time, then repeats every `gapSeconds` up to `count`.
    static func schedule(_ t: NudgeTask, count: Int, gapSeconds: Int, buddyName: String, quiet: Bool = true) {
        cancel(t.id)
        guard let due = t.due, t.doneAt == nil else { return }
        let total = t.nag ? min(max(1, count), 5) : 1
        for n in 0..<total {
            var fire = due.addingTimeInterval(Double(n * gapSeconds))
            if quiet, let wake = quietEnd(for: fire) {
                if n > 0 { continue }   // repeats wait; the first nudge moves to wake-up time
                fire = wake
            }
            let wait = fire.timeIntervalSinceNow
            guard wait > 1 else { continue }
            let last = total > 1 && n == total - 1
            let c = UNMutableNotificationContent()
            c.title = t.title
            if total > 1 { c.subtitle = "Nudge \(n + 1) of \(total)" }
            if last && !buddyName.isEmpty {
                c.body = "Last nudge. Want to text \(buddyName) for backup?"
            } else if let step = t.currentStep {
                c.body = "Just do this part: \(step)"
            } else {
                c.body = "Just start. Two minutes counts."
            }
            c.sound = SharedStore.defaults.bool(forKey: Keys.sound) ? .default : nil
            c.categoryIdentifier = category
            c.userInfo = ["task": t.id.uuidString, "last": last]
            let req = UNNotificationRequest(identifier: "\(t.id.uuidString)-\(n)", content: c,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
            UNUserNotificationCenter.current().add(req)
        }
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

    static func cancel(_ id: UUID) {
        let ids = (0..<5).map { "\(id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Lets the widget's Done button finish a task without opening the app.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark done"
    @Parameter(title: "Task ID") var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        var tasks = SharedStore.load()
        if let i = tasks.firstIndex(where: { $0.id.uuidString == taskID }) {
            tasks[i].doneAt = .now
            SharedStore.save(tasks)
            Nudger.cancel(tasks[i].id)
        }
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
