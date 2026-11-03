import SwiftUI

struct NowView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @State private var breaking: NudgeTask?

    var body: some View {
        let accent = Theme.accent(accentName)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let t = store.current {
                    card(t, accent)
                    BigButton(title: t.stepsDone + 1 < t.steps.count ? "Step done" : "Done",
                              systemImage: "checkmark", color: accent) {
                        haptic()
                        store.done(t.id)
                    }
                    HStack(spacing: 12) {
                        OutlineButton(title: "Not yet · 10 min") { store.snooze(t.id, minutes: 10) }
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
        .background(Theme.bg)
        .sheet(item: $breaking) { BreakDownView(task: $0) }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.grey)
                Text(greeting).font(.system(size: 26, weight: .heavy))
            }
            Spacer()
            Label("\(store.winsToday) wins today", systemImage: "star")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
        }
        .foregroundStyle(Theme.ink)
    }

    private func card(_ t: NudgeTask, _ accent: Color) -> some View {
        let isDue = (t.due ?? .now) <= .now
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isDue ? "RIGHT NOW" : "NEXT UP")
                    .font(.caption.weight(.heavy)).kerning(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(accent, in: Capsule())
                Spacer()
                if let due = t.due {
                    Text(due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.grey)
                }
            }
            Text(t.title)
                .font(.system(size: 36, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
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
        }
        .foregroundStyle(Theme.ink)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
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
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
        }
    }

    private func allClear(_ accent: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .heavy))
                .frame(width: 72, height: 72)
                .background(accent, in: Circle())
            Text("All clear.").font(.system(size: 32, weight: .heavy))
            Text(store.inbox.isEmpty
                 ? "Nothing needs you right now. Tap + whenever something pops into your head."
                 : "Nothing scheduled. You have \(store.inbox.count) things in your brain dump. Pick one in Today.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.grey)
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 32).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
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
