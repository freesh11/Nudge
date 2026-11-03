import AppIntents

/// "Hey Siri, brain dump in Nudge", or the Action Button: add a thought without opening the app.
struct BrainDumpIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to brain dump"
    static var description = IntentDescription("Get a thought out of your head without opening Nudge.")

    @Parameter(title: "Thought", requestValueDialog: "What's on your mind?")
    var thought: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .result(dialog: "Nothing to add.") }
        let store = Store.shared
        store.reload()
        let when = When(rawValue: SharedStore.defaults.string(forKey: Keys.defaultWhen) ?? "")
            .flatMap { When.defaults.contains($0) ? $0 : nil } ?? .later
        store.add(NudgeTask(title: title, due: when.date(from: .now, picked: .now),
                            nag: SharedStore.defaults.bool(forKey: Keys.defaultNag)))
        return .result(dialog: "Got it. It's in your brain dump.")
    }
}

struct NudgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BrainDumpIntent(),
                    phrases: ["Brain dump in \(.applicationName)",
                              "Add to \(.applicationName)",
                              "Remind me with \(.applicationName)"],
                    shortTitle: "Brain dump",
                    systemImageName: "plus.bubble")
    }
}
