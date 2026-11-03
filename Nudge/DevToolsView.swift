import SwiftUI
import UserNotifications
import WidgetKit

/// Settings › Developer tools: quick ways to try every part of the app without waiting.
struct DevToolsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.buddyName, store: SharedStore.defaults) private var buddyName = ""
    @State private var pending = 0
    @State private var permission = "Checking…"
    @State private var confirmClear = false
    @State private var note = ""

    private let groupOK = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup) != nil

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Notifications", value: permission)
                LabeledContent("Scheduled nudges", value: "\(pending) of 64")
                LabeledContent("Widget data sharing", value: groupOK ? "Working" : "Missing app group")
                LabeledContent("Tasks", value: "\(store.tasks.count) total, \(store.openTasks.count) open")
                Button("Refresh") { Task { await refresh() } }
            }

            Section {
                Button("Single nudge in 5 sec") { testNudge(count: 1) }
                Button("3 nudges, 10 sec apart") { testNudge(count: 3) }
            } header: { Text("Notifications") } footer: {
                Text("Lock your phone to see them as real notifications. Each test adds a \"Test nudge\" task you can mark Done.")
            }

            Section {
                Button("Show full-screen nudge") { showNudge(last: false) }
                Button("Show last nudge") { showNudge(last: true) }
                Button("Play success haptic") { haptic() }
            } header: { Text("Screens") } footer: {
                Text("The last nudge shows a text-your-buddy button when a buddy phone number is set.")
            }

            Section("Data") {
                Button("Add a sample day") { addSampleDay() }
                Button("Reload widget") { WidgetCenter.shared.reloadAllTimelines(); note = "Widget reloaded." }
                Button("Delete all tasks", role: .destructive) { confirmClear = true }
            }

            if !note.isEmpty {
                Section { Text(note).foregroundStyle(Theme.grey) }
            }
        }
        .navigationTitle("Developer tools")
        .task { await refresh() }
        .confirmationDialog("Delete every task?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all tasks", role: .destructive) { store.deleteAll(); note = "All tasks deleted." }
        } message: {
            Text("This also cancels every scheduled nudge. It can't be undone.")
        }
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        pending = await center.pendingNotificationRequests().count
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = "Allowed"
        case .denied: permission = "Blocked in iOS Settings"
        case .notDetermined: permission = "Not asked yet"
        @unknown default: permission = "Unknown"
        }
    }

    private func testNudge(count: Int) {
        let t = NudgeTask(title: "Test nudge", steps: ["This is only a test"], due: .now.addingTimeInterval(5), nag: count > 1)
        store.add(t)
        // Override the normal spacing so the whole series arrives within half a minute.
        Nudger.schedule(t, count: count, gapSeconds: 10, buddyName: buddyName, quiet: false)
        note = count == 1 ? "Nudge coming in 5 sec." : "Nudges coming 5, 15 and 25 sec from now."
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    private func showNudge(last: Bool) {
        let id: UUID
        if let current = store.current {
            id = current.id
        } else {
            let t = NudgeTask(title: "Test nudge", steps: ["This is only a test"], due: .now, nag: false)
            store.add(t)
            id = t.id
        }
        store.nudge = NudgeRef(id: id, last: last)
    }

    private func addSampleDay() {
        let samples: [(String, String, Double)] = [
            ("Take your meds", "Grab the pill bottle on the counter", 0),
            ("Shower", "Hang your towel on the door", 30),
            ("Reply to landlord", "Just open the email", 90),
            ("Pay electric bill", "Open the utility app", 450),
        ]
        for (title, step, minutes) in samples {
            store.add(NudgeTask(title: title, steps: [step], due: .now.addingTimeInterval(minutes * 60), nag: false))
        }
        note = "Added 4 sample tasks (quiet, one nudge each)."
    }
}
