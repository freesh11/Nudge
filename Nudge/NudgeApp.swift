import SwiftUI
import UserNotifications

@main
struct NudgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared

    init() {
        SharedStore.defaults.register(defaults: [Keys.nudgeCount: 3, Keys.nudgeGap: 5, Keys.bedtime: 23, Keys.accent: "orange"])
        #if DEBUG
        When.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Nudger.setup()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["task"] as? String, let id = UUID(uuidString: raw) else { return }
        let last = info["last"] as? Bool ?? false
        let action = response.actionIdentifier
        await MainActor.run {
            let store = Store.shared
            store.reload()
            switch action {
            case "DONE": store.complete(id)
            case "LATER5": store.snooze(id, minutes: 5)
            default: store.nudge = NudgeRef(id: id, last: last)   // tapped it, or "I'm on it"
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var phase
    @AppStorage(Keys.onboarded, store: SharedStore.defaults) private var onboarded = false
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @State private var capturing = false

    var body: some View {
        Group {
            if !onboarded {
                OnboardingView()
            } else {
                TabView {
                    NowView().tabItem { Label("Now", systemImage: "scope") }
                    TodayView().tabItem { Label("Today", systemImage: "calendar") }
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .tint(Theme.ink)
                .overlay(alignment: .bottomTrailing) {
                    Button { capturing = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 64, height: 64)
                            .background(Theme.accent(accentName), in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    }
                    .accessibilityLabel("Brain dump")
                    .padding(.trailing, 20)
                    .padding(.bottom, 70)
                }
                .sheet(isPresented: $capturing) { CaptureView() }
            }
        }
        .fullScreenCover(item: $store.nudge) { NudgeView(ref: $0) }
        .onChange(of: phase) { _, p in if p == .active { store.reload() } }
        .preferredColorScheme(.light)
    }
}

/// Small shared bits of UI.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.heavy)).kerning(1).foregroundStyle(Theme.grey)
    }
}

struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.title3.weight(.heavy))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(color, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct OutlineButton: View {
    let title: String
    var dark = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(dark ? .white : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(dark ? Color.clear : Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(dark ? Color(hex: 0x3A3E48) : Theme.line, lineWidth: 1.5))
        }
    }
}
