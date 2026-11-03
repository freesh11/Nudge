import SwiftUI
import EventKit

/// Today's timed events from the phone's calendars (read-only).
struct CalEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}

enum CalendarFeed {
    static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func today() -> [CalEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay }
            .map { CalEvent(id: "\($0.eventIdentifier ?? UUID().uuidString)-\($0.startDate.timeIntervalSince1970)",
                            title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate) }
    }
}

/// One line of the Today timeline: a task or a calendar event.
private struct TodayItem: Identifiable {
    let id: String
    let date: Date
    var task: NudgeTask? = nil
    var event: CalEvent? = nil
}

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @AppStorage(Keys.bedtime, store: SharedStore.defaults) private var bedtime = 23
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @AppStorage(Keys.showCalendar, store: SharedStore.defaults) private var showCalendar = false
    @State private var events: [CalEvent] = []

    private var timeline: [TodayItem] {
        let tasks = store.today.map { TodayItem(id: $0.id.uuidString, date: $0.due ?? .now, task: $0) }
        let cal = events.map { TodayItem(id: $0.id, date: $0.start, event: $0) }
        return (tasks + cal).sorted { $0.date < $1.date }
    }

    var body: some View {
        let accent = Theme.accent(accentName)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TimelineView(.everyMinute) { ctx in timeLeft(now: ctx.date, accent: accent) }
                        .padding(.bottom, 4)

                    if timeline.isEmpty {
                        Text("Nothing scheduled today yet.").foregroundStyle(Theme.grey)
                    }
                    ForEach(timeline) { item in
                        if let t = item.task { row(t, accent: accent) }
                        if let e = item.event { eventRow(e) }
                    }

                    if !store.placeTasks.isEmpty {
                        SectionLabel("WHEN YOU LEAVE OR GET HOME").padding(.top, 12)
                        if SharedStore.home == nil {
                            Text("Set your Home in Settings › Places so these can fire.")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.link)
                        }
                        ForEach(store.placeTasks) { t in placeRow(t) }
                    }

                    if !store.inbox.isEmpty {
                        HStack {
                            SectionLabel("BRAIN DUMP · NOT SCHEDULED")
                            Spacer()
                            Button { haptic(); store.pickOne() } label: {
                                Label("Pick one for me", systemImage: "dice").font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(Theme.link)
                            .frame(minHeight: 44)
                        }
                        .padding(.top, 12)
                        ForEach(store.inbox) { t in inboxRow(t) }
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(20)
                .padding(.bottom, 80)
            }
            .background(AppBackground())
            .task(id: showCalendar) { events = showCalendar ? CalendarFeed.today() : [] }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.body.weight(isNow ? .heavy : .bold))
                        .strikethrough(done).foregroundStyle(done ? Theme.grey : Theme.ink)
                    if let took = t.actualSeconds {
                        Text("Took \(formatMinutes(took))" + (t.estimateMinutes.map { " · guessed \($0)m" } ?? ""))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.grey)
                    }
                }
                .padding(.vertical, 8)
                if t.repeatRule != nil {
                    Image(systemName: "repeat").font(.caption.weight(.bold)).foregroundStyle(Theme.grey)
                        .accessibilityLabel(t.repeatRule!.label)
                }
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

    private func eventRow(_ e: CalEvent) -> some View {
        HStack(spacing: 12) {
            Text(e.start.formatted(date: .omitted, time: .shortened))
                .font(.footnote.weight(.bold)).foregroundStyle(Theme.grey)
                .frame(width: 66, alignment: .leading)
            HStack {
                Image(systemName: "calendar").foregroundStyle(Theme.grey)
                Text(e.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("until \(e.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.grey)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .accessibilityElement(children: .combine)
    }

    private func placeRow(_ t: NudgeTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: t.place == .leaveHome ? "figure.walk.departure" : "house")
                .foregroundStyle(Theme.grey)
                .frame(width: 28)
                .accessibilityLabel(t.place == .leaveHome ? "When you leave home" : "When you get home")
            Text(t.title).font(.body.weight(.bold))
            if t.repeatRule != nil { Image(systemName: "repeat").font(.caption.weight(.bold)).foregroundStyle(Theme.grey) }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .contextMenu {
            Button("Done", systemImage: "checkmark") { store.complete(t.id) }
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
