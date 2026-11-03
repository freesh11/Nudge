import SwiftUI

private struct DayGroup: Identifiable {
    let day: Date
    let tasks: [NudgeTask]
    var id: Date { day }
}

/// Everything you finished in the last 7 days. Only wins, never a list of misses.
struct WinsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    private var days: [DayGroup] {
        let grouped = Dictionary(grouping: store.winsThisWeek) { Calendar.current.startOfDay(for: $0.doneAt!) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, tasks: grouped[$0]!) }
    }

    /// How much longer things take than you guess, once there are a few to compare.
    private var guessInsight: String? {
        let pairs = store.winsThisWeek.compactMap { t -> Double? in
            guard let actual = t.actualSeconds, let guess = t.estimateMinutes, guess > 0 else { return nil }
            return actual / Double(guess * 60)
        }
        guard pairs.count >= 3 else { return nil }
        let ratio = pairs.reduce(0, +) / Double(pairs.count)
        if ratio > 1.2 { return "Things take about \(String(format: "%.1f", ratio))× longer than you guess. Try padding your estimates." }
        if ratio < 0.8 { return "You finish faster than you guess. Nice." }
        return "Your time guesses are spot on."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.winsThisWeek.count)").font(.system(size: 56, weight: .heavy))
                        Text(store.winsThisWeek.count == 1 ? "thing done this week" : "things done this week")
                            .font(.title3.weight(.semibold)).foregroundStyle(Theme.grey)
                        if let guessInsight {
                            Text(guessInsight).font(.subheadline.weight(.semibold)).padding(.top, 6)
                        }
                    }
                    .padding(.vertical, 8)
                }
                if days.isEmpty {
                    Section { Text("Finish something and it shows up here.").foregroundStyle(Theme.grey) }
                }
                ForEach(days) { day in
                    Section(day.day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(day.tasks) { t in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                                Text(t.title).font(.body.weight(.semibold))
                                Spacer()
                                if let took = t.actualSeconds {
                                    Text(formatMinutes(took)).font(.subheadline).foregroundStyle(Theme.grey)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your wins")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
