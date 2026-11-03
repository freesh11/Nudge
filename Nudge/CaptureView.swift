import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @State private var title = ""
    @State private var step = ""
    @State private var when: When = .later
    @State private var picked = Date.now.addingTimeInterval(3600)
    @State private var nag = true
    @FocusState private var focused: Bool

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Get it out of your head. Sorting is optional.").foregroundStyle(Theme.grey)

                    TextField("What's on your mind?", text: $title, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.title3.weight(.semibold))
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1.5))
                        .focused($focused)
                    Text("Tip: tap the mic on your keyboard to talk instead of type.")
                        .font(.footnote).foregroundStyle(Theme.grey)

                    SectionLabel("WHEN SHOULD I BUG YOU?")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(When.allCases, id: \.self) { w in
                            let on = when == w
                            Button { when = w } label: {
                                Text(w.label)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(on ? .white : Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(on ? Theme.indigo : .white, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.indigo : Theme.line, lineWidth: 1.5))
                            }
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if when == .pick {
                        DatePicker("Time", selection: $picked, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    }

                    SectionLabel("TINY FIRST STEP (OPTIONAL)")
                    TextField("e.g. Just open the email", text: $step)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1.5))

                    Toggle(isOn: $nag) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nag me until it's done").font(.body.weight(.bold))
                            Text("Repeats up to your nudge limit").font(.footnote).foregroundStyle(Theme.grey)
                        }
                    }
                    .tint(Theme.green)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Brain dump")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                BigButton(title: "Save it", color: Theme.accent(accentName), action: save)
                    .disabled(cleanTitle.isEmpty)
                    .opacity(cleanTitle.isEmpty ? 0.5 : 1)
                    .padding(20)
                    .background(Theme.bg)
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        let s = step.trimmingCharacters(in: .whitespacesAndNewlines)
        store.add(NudgeTask(title: cleanTitle, steps: s.isEmpty ? [] : [s],
                            due: when.date(from: .now, picked: picked), nag: nag))
        haptic()
        dismiss()
    }
}
