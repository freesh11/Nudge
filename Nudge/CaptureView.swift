import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @State private var title = ""
    @State private var step = ""
    @State private var when = When(rawValue: SharedStore.defaults.string(forKey: Keys.defaultWhen) ?? "") ?? .later
    @State private var picked = Date.now.addingTimeInterval(3600)
    @State private var nag = SharedStore.defaults.bool(forKey: Keys.defaultNag)
    @State private var repeatRule: Repeat?
    @State private var prepMinutes = 0
    @State private var estimate: Int?
    @State private var effort: Int?
    @State private var showMore = false
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
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
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
                                    .background(on ? Theme.indigo : Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.indigo : Theme.line, lineWidth: 1.5))
                            }
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if when == .pick {
                        DatePicker("Time", selection: $picked, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    }
                    if when.place != nil && SharedStore.home == nil {
                        Text("Set your Home first in Settings › Places, or this reminder can't fire.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.link)
                    }

                    SectionLabel("TINY FIRST STEP (OPTIONAL)")
                    TextField("e.g. Just open the email", text: $step)
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1.5))

                    Toggle(isOn: $nag) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nag me until it's done").font(.body.weight(.bold))
                            Text("Repeats up to your nudge limit").font(.footnote).foregroundStyle(Theme.grey)
                        }
                    }
                    .tint(Theme.green)
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))

                    DisclosureGroup("More options", isExpanded: $showMore) {
                        VStack(spacing: 0) {
                            optionRow("Repeat") {
                                Picker("Repeat", selection: $repeatRule) {
                                    Text("Never").tag(Repeat?.none)
                                    ForEach(Repeat.allCases, id: \.self) { Text($0.label).tag(Repeat?.some($0)) }
                                }
                            }
                            if when.place == nil && when != .someday {
                                Divider()
                                optionRow("Get-ready time") {
                                    Picker("Get-ready time", selection: $prepMinutes) {
                                        Text("None").tag(0)
                                        ForEach([10, 15, 30, 45, 60, 90], id: \.self) { Text("\($0) min before").tag($0) }
                                    }
                                }
                            }
                            Divider()
                            optionRow("How long will it take?") {
                                Picker("How long will it take?", selection: $estimate) {
                                    Text("Not sure").tag(Int?.none)
                                    ForEach([5, 10, 15, 30, 60, 90], id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
                                }
                            }
                            Divider()
                            optionRow("Effort") {
                                Picker("Effort", selection: $effort) {
                                    Text("Not set").tag(Int?.none)
                                    Text("Easy").tag(Int?.some(1))
                                    Text("Medium").tag(Int?.some(2))
                                    Text("Hard").tag(Int?.some(3))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.body.weight(.bold))
                    .tint(Theme.ink)
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
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

    private func optionRow<P: View>(_ label: String, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(label).font(.body.weight(.semibold))
            Spacer()
            picker().pickerStyle(.menu).labelsHidden()
        }
        .frame(minHeight: 44)
    }

    private func save() {
        let s = step.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = when.date(from: .now, picked: picked)
        store.add(NudgeTask(title: cleanTitle, steps: s.isEmpty ? [] : [s], due: due, nag: nag,
                            repeatRule: repeatRule, prepMinutes: due == nil ? 0 : prepMinutes,
                            estimateMinutes: estimate, effort: effort, place: when.place))
        haptic()
        dismiss()
    }
}
