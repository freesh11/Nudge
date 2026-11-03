import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

/// One-shot "where am I" to save Home. Only needs While Using permission.
@MainActor
final class HomeLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status = ""
    private let manager = CLLocationManager()
    private var waiting = false

    func saveCurrentAsHome() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        waiting = true
        status = "Finding you…"
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()   // continues in the callback
        case .denied, .restricted: waiting = false; status = "Location is off for Nudge in iOS Settings."
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        Task { @MainActor in
            guard self.waiting else { return }
            if s == .authorizedWhenInUse || s == .authorizedAlways { self.manager.requestLocation() }
            else if s == .denied || s == .restricted { self.waiting = false; self.status = "Location is off for Nudge in iOS Settings." }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard self.waiting else { return }
            self.waiting = false
            SharedStore.defaults.set(c.latitude, forKey: Keys.homeLat)
            SharedStore.defaults.set(c.longitude, forKey: Keys.homeLon)
            self.status = "Home saved."
            Store.shared.rescheduleAll()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.waiting = false
            self.status = "Couldn't find your location. Try again outside or near a window."
        }
    }
}

/// The tasks file, for saving to Files and restoring later.
struct BackupDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.appearance, store: SharedStore.defaults) private var appearance = "system"
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @AppStorage(Keys.matchIcon, store: SharedStore.defaults) private var matchIcon = false
    @AppStorage(Keys.background, store: SharedStore.defaults) private var background = LiveBackground.constellations.rawValue
    @AppStorage(Keys.name, store: SharedStore.defaults) private var name = ""
    @AppStorage(Keys.showWins, store: SharedStore.defaults) private var showWins = true
    @AppStorage(Keys.haptics, store: SharedStore.defaults) private var haptics = true
    @AppStorage(Keys.nudgeCount, store: SharedStore.defaults) private var nudgeCount = 3
    @AppStorage(Keys.nudgeGap, store: SharedStore.defaults) private var nudgeGap = 5
    @AppStorage(Keys.sound, store: SharedStore.defaults) private var sound = true
    @AppStorage(Keys.liveActivity, store: SharedStore.defaults) private var liveActivity = true
    @AppStorage(Keys.quietOn, store: SharedStore.defaults) private var quietOn = true
    @AppStorage(Keys.bedtime, store: SharedStore.defaults) private var bedtime = 23
    @AppStorage(Keys.wakeHour, store: SharedStore.defaults) private var wakeHour = 7
    @AppStorage(Keys.notYetMins, store: SharedStore.defaults) private var notYetMins = 10
    @AppStorage(Keys.onItMins, store: SharedStore.defaults) private var onItMins = 15
    @AppStorage(Keys.defaultWhen, store: SharedStore.defaults) private var defaultWhen = When.later.rawValue
    @AppStorage(Keys.defaultNag, store: SharedStore.defaults) private var defaultNag = true
    @AppStorage(Keys.buddyName, store: SharedStore.defaults) private var buddyName = ""
    @AppStorage(Keys.buddyPhone, store: SharedStore.defaults) private var buddyPhone = ""
    @AppStorage(Keys.onboarded, store: SharedStore.defaults) private var onboarded = true
    @AppStorage(Keys.showCalendar, store: SharedStore.defaults) private var showCalendar = false
    @AppStorage(Keys.weeklyRecap, store: SharedStore.defaults) private var weeklyRecap = true
    @AppStorage(Keys.doneSound, store: SharedStore.defaults) private var doneSound = true
    @AppStorage(Keys.focusMins, store: SharedStore.defaults) private var focusMins = 5
    @AppStorage(Keys.homeLat, store: SharedStore.defaults) private var homeLat: Double?
    @StateObject private var locator = HomeLocator()
    @State private var calendarNote = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var restoreCandidate: [NudgeTask]?
    @State private var backupNote = ""

    /// Anything that changes what gets scheduled; one key keeps it to a single onChange.
    private var nudgeConfig: String { "\(nudgeCount)-\(nudgeGap)-\(sound)-\(quietOn)-\(bedtime)-\(wakeHour)-\(buddyName)-\(weeklyRecap)" }

    var body: some View {
        NavigationStack {
            Form {
                look
                nudges
                night
                buttons
                brainDump
                places
                today
                buddy
                backup
                Section {
                    NavigationLink("Developer tools") { DevToolsView() }
                    Button("Run setup again") { onboarded = false }
                } footer: {
                    Text("Nudge \(Self.appVersion)")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: nudgeConfig) { store.rescheduleAll() }
            .onChange(of: liveActivity) { store.syncActivity() }
            .onChange(of: "\(accentName)-\(matchIcon)") { applyIcon() }
        }
    }

    private var look: some View {
        Section("Look") {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(Theme.accents) { a in
                    Button { accentName = a.id } label: {
                        Circle().fill(a.color).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: accentName == a.id ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.id.capitalized)
                    .accessibilityAddTraits(accentName == a.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            Toggle("App icon matches color", isOn: $matchIcon)
            Picker("Live background", selection: $background) {
                ForEach(LiveBackground.allCases) { Text($0.label).tag($0.rawValue) }
            }
            TextField("Your name, for the greeting", text: $name)
            Toggle("Show wins counter", isOn: $showWins)
            Toggle("Haptics", isOn: $haptics)
            Toggle("Sound when you finish", isOn: $doneSound)
        }
    }

    private var nudges: some View {
        Section {
            Stepper("Nudges per task: \(nudgeCount)", value: $nudgeCount, in: 1...5)
            Picker("Time between nudges", selection: $nudgeGap) {
                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
            }
            Toggle("Sound", isOn: $sound)
            Toggle("Dynamic Island timer", isOn: $liveActivity)
            Picker("\u{201C}Start with me\u{201D} timer", selection: $focusMins) {
                ForEach([2, 5, 10, 15, 25], id: \.self) { Text("\($0) min").tag($0) }
            }
            Toggle("Sunday wins recap", isOn: $weeklyRecap)
            Button("Phone notification settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
        } header: { Text("Nudges") } footer: {
            Text("Add Nudge to the allowed apps in your Focus modes so nudges get through.")
        }
    }

    private var night: some View {
        Section {
            Picker("Bedtime", selection: $bedtime) { hourOptions }
            Toggle("Quiet hours", isOn: $quietOn)
            if quietOn {
                Picker("Quiet until", selection: $wakeHour) { hourOptions }
            }
        } header: { Text("Night") } footer: {
            Text(quietOn
                 ? "From bedtime until \(Self.hourLabel(wakeHour)), repeat nudges wait and the first one moves to the morning."
                 : "Nudges can arrive at any hour.")
        }
    }

    private var buttons: some View {
        Section("Buttons") {
            Picker("\u{201C}Not yet\u{201D} waits", selection: $notYetMins) {
                ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("\u{201C}I\u{2019}m on it\u{201D} checks back after", selection: $onItMins) {
                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
            }
        }
    }

    private var brainDump: some View {
        Section("Brain dump") {
            Picker("Default reminder", selection: $defaultWhen) {
                ForEach(When.defaults, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("Nag by default", isOn: $defaultNag)
        }
    }

    private var places: some View {
        Section {
            LabeledContent("Home", value: homeLat == nil ? "Not set" : "Set")
            Button(homeLat == nil ? "Set Home to where I am now" : "Update Home to where I am now") { locator.saveCurrentAsHome() }
        } header: { Text("Places") } footer: {
            Text(locator.status.isEmpty
                 ? "Used for \u{201C}When I leave home\u{201D} and \u{201C}When I get home\u{201D} reminders. Your location stays on your phone."
                 : locator.status)
        }
    }

    private var today: some View {
        Section {
            Toggle("Show my calendar", isOn: $showCalendar)
        } header: { Text("Today screen") } footer: {
            Text(calendarNote.isEmpty ? "Puts today's calendar events in your timeline. Read-only." : calendarNote)
        }
        .onChange(of: showCalendar) { _, on in
            guard on else { calendarNote = ""; return }
            Task {
                if await CalendarFeed.requestAccess() {
                    calendarNote = ""
                } else {
                    showCalendar = false
                    calendarNote = "Calendar access is off. Turn it on for Nudge in iOS Settings › Privacy › Calendars."
                }
            }
        }
    }

    private var backup: some View {
        Section {
            Button("Save a backup to Files") { exporting = true }
            Button("Restore from a backup") { importing = true }
        } header: { Text("Backup") } footer: {
            Text(backupNote.isEmpty ? "Do this before reinstalling, in case the new install starts empty." : backupNote)
        }
        .fileExporter(isPresented: $exporting,
                      document: BackupDoc(data: (try? JSONEncoder().encode(store.tasks)) ?? Data()),
                      contentType: .json,
                      defaultFilename: "Nudge backup \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { backupNote = "Backup saved." }
            if case .failure = result { backupNote = "Couldn't save the backup." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // A bad file must never replace your list, so decode fully before asking.
            guard let data = try? Data(contentsOf: url),
                  let tasks = try? JSONDecoder().decode([NudgeTask].self, from: data) else {
                backupNote = "That file isn't a Nudge backup."
                return
            }
            restoreCandidate = tasks
        }
        .confirmationDialog("Replace your list with this backup?", isPresented: .init(
            get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } }), titleVisibility: .visible) {
            Button("Replace \(store.tasks.count) tasks with \(restoreCandidate?.count ?? 0)", role: .destructive) {
                if let r = restoreCandidate { store.replaceAll(r); backupNote = "Restored \(r.count) tasks." }
                restoreCandidate = nil
            }
        } message: {
            Text("Your current tasks will be replaced. Save a backup first if you want to keep them.")
        }
    }

    private var buddy: some View {
        Section {
            TextField("Name", text: $buddyName)
            TextField("Phone number", text: $buddyPhone).keyboardType(.phonePad)
            Button("Send a test text") {
                Buddy.text(phone: buddyPhone, body: "Hey! I set you as my accountability buddy in Nudge. If I text you, just check I did the thing.")
            }
            .disabled(buddyPhone.isEmpty)
        } header: { Text("Accountability buddy") } footer: {
            Text("After your last nudge, Nudge offers a one-tap text to your buddy. iOS doesn't let apps send texts for you, so you still hit send.")
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { h in Text(Self.hourLabel(h)).tag(h) }
    }

    /// Orange is the main icon; the others are alternate icon sets named AppIcon-<color>.
    private func applyIcon() {
        let icon: String? = matchIcon && accentName != "orange" ? "AppIcon-\(accentName)" : nil
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != icon else { return }
        UIApplication.shared.setAlternateIconName(icon, completionHandler: nil)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let stage = info["NudgeStage"] as? String ?? ""
        return "\(version) \(stage)".trimmingCharacters(in: .whitespaces)
    }

    static func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.onboarded, store: SharedStore.defaults) private var onboarded = false
    @AppStorage(Keys.bedtime, store: SharedStore.defaults) private var bedtime = 23
    @AppStorage(Keys.buddyName, store: SharedStore.defaults) private var buddyName = ""
    @AppStorage(Keys.buddyPhone, store: SharedStore.defaults) private var buddyPhone = ""
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                intro(icon: "scope", title: "One thing at a time",
                      text: "Nudge only shows you the next thing. The rest of your list waits quietly where you can't see it.")
                    .tag(0)
                VStack(spacing: 24) {
                    intro(icon: "bell.badge", title: "Nudges that don't give up",
                          text: "Reminders repeat until you tap Done or push them back. You choose how pushy in Settings.")
                    OutlineButton(title: "Allow notifications") {
                        Task {
                            _ = await Nudger.requestPermission()
                            withAnimation { page = 2 }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .tag(1)
                setup.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            BigButton(title: page < 2 ? "Next" : "Get started", color: Theme.accent(accentName)) {
                if page < 2 { withAnimation { page += 1 } } else { finish() }
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.bg)
    }

    private func intro(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.system(size: 44, weight: .bold))
            Text(title).font(.system(size: 36, weight: .heavy))
            Text(text).font(.title3).foregroundStyle(Theme.grey)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two quick things").font(.system(size: 32, weight: .heavy))
            Text("Both optional. You can change them later.").foregroundStyle(Theme.grey)
            HStack {
                Text("Bedtime").font(.body.weight(.bold))
                Spacer()
                Picker("Bedtime", selection: $bedtime) {
                    ForEach(0..<24, id: \.self) { h in Text(SettingsView.hourLabel(h)).tag(h) }
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                Text("Accountability buddy").font(.body.weight(.bold))
                TextField("Their name", text: $buddyName)
                Divider()
                TextField("Their phone number", text: $buddyPhone).keyboardType(.phonePad)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
        .padding(24)
    }

    private func finish() {
        store.add(NudgeTask(title: "Try it out", steps: ["Tap the big Done button"], due: .now, nag: false))
        onboarded = true
    }
}
