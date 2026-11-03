import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.nudgeCount, store: SharedStore.defaults) private var nudgeCount = 3
    @AppStorage(Keys.nudgeGap, store: SharedStore.defaults) private var nudgeGap = 5
    @AppStorage(Keys.bedtime, store: SharedStore.defaults) private var bedtime = 23
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @AppStorage(Keys.buddyName, store: SharedStore.defaults) private var buddyName = ""
    @AppStorage(Keys.buddyPhone, store: SharedStore.defaults) private var buddyPhone = ""
    @AppStorage(Keys.onboarded, store: SharedStore.defaults) private var onboarded = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Nudges per task: \(nudgeCount)", value: $nudgeCount, in: 1...5)
                    Picker("Time between nudges", selection: $nudgeGap) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Button("Phone notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Text("Nudges") } footer: {
                    Text("Keep sounds on, and add Nudge to the allowed apps in your Focus modes so nudges get through.")
                }

                Section("Your day") {
                    Picker("Bedtime", selection: $bedtime) {
                        ForEach(0..<24, id: \.self) { h in Text(Self.hourLabel(h)).tag(h) }
                    }
                }

                Section("Color") {
                    HStack(spacing: 16) {
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
                }

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

                Section {
                    NavigationLink("Developer tools") { DevToolsView() }
                    Button("Run setup again") { onboarded = false }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: nudgeCount) { store.rescheduleAll() }
            .onChange(of: nudgeGap) { store.rescheduleAll() }
            .onChange(of: buddyName) { store.rescheduleAll() }
        }
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
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) {
                Text("Accountability buddy").font(.body.weight(.bold))
                TextField("Their name", text: $buddyName)
                Divider()
                TextField("Their phone number", text: $buddyPhone).keyboardType(.phonePad)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
        .padding(24)
    }

    private func finish() {
        store.add(NudgeTask(title: "Try it out", steps: ["Tap the big Done button"], due: .now, nag: false))
        onboarded = true
    }
}
