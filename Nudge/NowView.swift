import SwiftUI

struct NowView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @AppStorage(Keys.name, store: SharedStore.defaults) private var name = ""
    @AppStorage(Keys.showWins, store: SharedStore.defaults) private var showWins = true
    @AppStorage(Keys.notYetMins, store: SharedStore.defaults) private var notYetMins = 10
    @AppStorage(Keys.focusMins, store: SharedStore.defaults) private var focusMins = 5
    @State private var breaking: NudgeTask?

    var body: some View {
        let accent = Theme.accent(accentName)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                energyRow(accent)
                if let t = store.current {
                    card(t, accent)
                    BigButton(title: t.stepsDone + 1 < t.steps.count ? "Step done" : "Done",
                              systemImage: "checkmark", color: accent) {
                        Celebrate.done()
                        store.done(t.id)
                    }
                    if t.isFocusing {
                        OutlineButton(title: "Stop timer") { store.stopFocus(t.id) }
                    } else {
                        OutlineButton(title: "Start \(focusMins) min with me") { haptic(); store.startFocus(t.id) }
                    }
                    HStack(spacing: 12) {
                        OutlineButton(title: "Not yet · \(notYetMins) min") { store.snooze(t.id, minutes: notYetMins) }
                        OutlineButton(title: "Break it down") { breaking = t }
                    }
                    if let next = store.upNext { upNext(next) }
                } else {
                    allClear(accent)
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppBackground())
        .sheet(item: $breaking) { BreakDownView(task: $0) }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let hello = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? hello : "\(hello), \(trimmed)"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.grey)
                Text(greeting).font(.system(size: 26, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            if showWins {
                Button { store.showWins = true } label: {
                    Label("\(store.winsToday) wins today", systemImage: "star")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line))
                }
                .accessibilityHint("Shows what you finished this week")
            }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Low / Medium / High: hides harder tasks on low days. Resets each morning.
    private func energyRow(_ accent: Color) -> some View {
        let levels = [(1, "Low"), (2, "Medium"), (3, "High")]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Energy").font(.subheadline.weight(.bold)).foregroundStyle(Theme.grey)
                ForEach(levels, id: \.0) { item in
                    let (level, label) = item
                    let on = store.energy == level
                    Button { store.setEnergy(on ? nil : level) } label: {
                        Text(label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(on ? accent : Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(on ? accent : Theme.line))
                    }
                    .frame(minHeight: 44)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if store.hiddenByEnergy > 0 {
                Text("Hiding \(store.hiddenByEnergy) harder \(store.hiddenByEnergy == 1 ? "task" : "tasks") for now")
                    .font(.footnote).foregroundStyle(Theme.grey)
            }
        }
    }

    private func card(_ t: NudgeTask, _ accent: Color) -> some View {
        let isDue = (t.due ?? .now) <= .now
        let inPrep = !isDue && (t.nudgeStart ?? .distantFuture) <= .now
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t.isFocusing ? "FOCUS" : isDue ? "RIGHT NOW" : inPrep ? "GET READY" : "NEXT UP")
                    .font(.caption.weight(.heavy)).kerning(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
                Spacer()
                if let due = t.due {
                    Text(due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.grey)
                }
            }
            Text(t.title)
                .font(.system(size: 36, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            if inPrep, let due = t.due {
                Text("Start getting ready. It's at \(due.formatted(date: .omitted, time: .shortened)).")
                    .font(.body.weight(.semibold)).foregroundStyle(Theme.grey)
            }
            if t.steps.count > 1 {
                Text("Step \(t.stepsDone + 1) of \(t.steps.count)")
                    .font(.body.weight(.medium)).foregroundStyle(Theme.grey)
            }
            if let step = t.currentStep {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(t.stepsDone == 0 ? "TINY FIRST STEP" : "NEXT TINY STEP")
                    Text(step).font(.body.weight(.bold))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16))
            }
            if let end = t.focusUntil, t.isFocusing {
                TimeDisk(end: end, span: Double(focusMins * 60), color: accent, label: "left · you've got this")
            } else if let due = t.due, due > .now, due.timeIntervalSinceNow < 3600 {
                TimeDisk(end: due, span: 3600, color: accent, label: "until it starts")
            }
            if let estimate = t.estimateMinutes {
                Text("You guessed \(estimate) min" + (store.lastDuration(for: t.title).map { ". Last time took \(formatMinutes($0))." } ?? "."))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.grey)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    private func upNext(_ t: NudgeTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("UP NEXT")
            HStack(spacing: 14) {
                Text(t.due?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.grey)
                    .frame(minWidth: 64, alignment: .leading)
                Text(t.title).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
        }
    }

    private func allClear(_ accent: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .heavy))
                .frame(width: 72, height: 72)
                .background(accent, in: Circle())
                .foregroundStyle(Theme.onAccent)
            Text("All clear.").font(.system(size: 32, weight: .heavy))
            Text(store.inbox.isEmpty
                 ? "Nothing needs you right now. Tap + whenever something pops into your head."
                 : "Nothing scheduled. You have \(store.inbox.count) things in your brain dump.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.grey)
            if !store.inbox.isEmpty {
                BigButton(title: "Pick one for me", systemImage: "dice", color: accent) {
                    haptic()
                    store.pickOne()
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 32).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28))
    }
}

/// A shrinking pie that shows time left at a glance (a "time timer").
struct TimeDisk: View {
    let end: Date
    let span: TimeInterval
    let color: Color
    let label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.line.opacity(0.6))
                    PieSlice(fraction: min(1, left / span)).fill(color)
                }
                .frame(width: 44, height: 44)
                Text("\(Self.clock(left)) \(label)").font(.body.weight(.bold)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(formatMinutes(left)) \(label)")
        }
    }

    static func clock(_ s: TimeInterval) -> String {
        let total = Int(s.rounded(.up))
        return total >= 3600 ? "\(total / 3600):\(String(format: "%02d", total % 3600 / 60)):\(String(format: "%02d", total % 60))"
                             : "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

struct PieSlice: Shape {
    var fraction: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard fraction > 0 else { return p }
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(r.width, r.height) / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct BreakDownView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let task: NudgeTask
    @State private var steps: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(steps.indices, id: \.self) { i in
                        TextField("Step \(i + 1)", text: $steps[i])
                    }
                    Button("Add a step") { steps.append("") }
                } header: {
                    Text("Make each step tiny. Like, embarrassingly tiny.")
                }
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.setSteps(task.id, steps); dismiss() }
                }
            }
            .onAppear { steps = task.steps.isEmpty ? ["", "", ""] : task.steps }
        }
    }
}
