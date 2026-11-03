import SwiftUI

/// Full-screen nudge, shown when you tap a reminder.
struct NudgeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.buddyName, store: SharedStore.defaults) private var buddyName = ""
    @AppStorage(Keys.buddyPhone, store: SharedStore.defaults) private var buddyPhone = ""
    @AppStorage(Keys.onItMins, store: SharedStore.defaults) private var onItMins = 15
    let ref: NudgeRef

    private let orange = Theme.accent("orange")
    private let muted = Color(hex: 0xA3A9B6)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let t = store.tasks.first(where: { $0.id == ref.id }), t.doneAt == nil {
                HStack(spacing: 10) {
                    Text(ref.last ? "LAST NUDGE" : "NUDGE")
                        .font(.caption.weight(.heavy)).kerning(1)
                        .foregroundStyle(Color(hex: 0xFF8A57))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(orange, lineWidth: 1.5))
                    if let due = t.due {
                        Text("You planned this for \(due.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(muted)
                    }
                }
                Text(t.title).font(.system(size: 48, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("JUST DO THIS PART").font(.caption.weight(.heavy)).kerning(1).foregroundStyle(muted)
                    Text(t.currentStep ?? "Start for two minutes. That's it.").font(.title2.weight(.bold))
                    Text("The rest usually follows.").font(.subheadline).foregroundStyle(muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x23262E), in: RoundedRectangle(cornerRadius: 22))

                Spacer()

                BigButton(title: "I'm on it", color: orange) { store.snooze(t.id, minutes: onItMins); dismiss() }
                HStack(spacing: 12) {
                    OutlineButton(title: "5 more min", dark: true) { store.snooze(t.id, minutes: 5); dismiss() }
                    OutlineButton(title: "Move to later", dark: true) { store.snooze(t.id, minutes: 180); dismiss() }
                }
                OutlineButton(title: "Already done", dark: true) { haptic(); store.complete(t.id); dismiss() }
                if ref.last && !buddyPhone.isEmpty {
                    OutlineButton(title: "Text \(buddyName.isEmpty ? "your buddy" : buddyName) for backup", dark: true) {
                        Buddy.text(phone: buddyPhone,
                                   body: "Hey, can you check that I did \"\(t.title)\"? My reminders aren't cutting it today.")
                    }
                }
                Text("\"I'm on it\" means I'll check back in \(onItMins) min.")
                    .font(.footnote).foregroundStyle(muted)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
                Text("Already handled. Nice.").font(.largeTitle.weight(.heavy))
                Spacer()
                BigButton(title: "Close", color: orange) { dismiss() }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppBackground(base: Theme.night, ink: .white))
    }
}
