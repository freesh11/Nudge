import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.bedtime, store: SharedStore.defaults) private var bedtime = 23
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"

    var body: some View {
        let accent = Theme.accent(accentName)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TimelineView(.everyMinute) { ctx in timeLeft(now: ctx.date, accent: accent) }
                        .padding(.bottom, 4)

                    if store.today.isEmpty {
                        Text("Nothing scheduled today yet.").foregroundStyle(Theme.grey)
                    }
                    ForEach(store.today) { t in row(t, accent: accent) }

                    if !store.inbox.isEmpty {
                        SectionLabel("BRAIN DUMP · NOT SCHEDULED").padding(.top, 12)
                        ForEach(store.inbox) { t in inboxRow(t) }
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
                .padding(.bottom, 80)
            }
            .background(AppBackground())
            .navigationTitle("Today")
        }
    }

    private func timeLeft(now: Date, accent: Color) -> some View {
        let cal = Calendar.current
        var bed = cal.date(bySettingHour: bedtime, minute: 0, second: 0, of: now) ?? now
        if bedtime < 5 && cal.component(.hour, from: now) >= 5 { bed = cal.date(byAdding: .day, value: 1, to: bed) ?? bed }
        let left = bed.timeIntervalSince(now)
        let awake: Double = 16 * 3600
        let next = store.openTasks.first { ($0.due ?? now) > now }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(left > 0 ? Self.hm(left) : "Past bedtime").font(.system(size: 30, weight: .heavy))
                Spacer()
                Text("left until bed · \(bed.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: 0xA3A9B6))
            }
            ProgressView(value: min(max(left / awake, 0), 1)).tint(accent)
            if let next, let due = next.due {
                Text("Next: \(next.title) in \(Self.hm(due.timeIntervalSince(now)))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: 0xA3A9B6))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.night, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    static func hm(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private func row(_ t: NudgeTask, accent: Color) -> some View {
        let isNow = t.id == store.current?.id
        let done = t.doneAt != nil
        return HStack(spacing: 12) {
            Text(t.due?.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.footnote.weight(.bold)).foregroundStyle(Theme.grey)
                .frame(width: 66, alignment: .leading)
            HStack {
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green) }
                Text(t.title).font(.body.weight(isNow ? .heavy : .bold))
                    .strikethrough(done).foregroundStyle(done ? Theme.grey : Theme.ink)
                Spacer()
                if isNow {
                    Text("NOW").font(.caption2.weight(.heavy)).kerning(1).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.night, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(isNow ? accent.opacity(0.2) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isNow ? accent : Theme.line, lineWidth: isNow ? 1.5 : 1))
        }
        .contextMenu {
            if !done {
                Button("Done", systemImage: "checkmark") { store.complete(t.id) }
                Button("Do it now", systemImage: "bolt") { store.doNow(t.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(t.id) }
        }
    }

    private func inboxRow(_ t: NudgeTask) -> some View {
        HStack {
            Text(t.title).font(.body.weight(.bold))
            Spacer()
            Button("Do now") { store.doNow(t.id) }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.link)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(t.id) }
        }
    }
}
