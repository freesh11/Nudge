import WidgetKit
import SwiftUI
import AppIntents

struct NudgeEntry: TimelineEntry {
    let date: Date
    let task: NudgeTask?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeEntry {
        NudgeEntry(date: .now, task: NudgeTask(title: "Take your meds", steps: ["Grab the bottle"], due: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NudgeEntry) -> Void) {
        completion(NudgeEntry(date: .now, task: SharedStore.openTasks(in: SharedStore.load()).first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeEntry>) -> Void) {
        let entry = NudgeEntry(date: .now, task: SharedStore.openTasks(in: SharedStore.load()).first)
        // The app reloads the widget on every change; this just keeps "RIGHT NOW" vs "NEXT" fresh.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct NudgeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NudgeEntry

    var body: some View {
        content.containerBackground(for: .widget) { Theme.card }
    }

    @ViewBuilder private var content: some View {
        if let t = entry.task {
            switch family {
            case .accessoryInline:
                Text(t.title)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.headline).lineLimit(2)
                    if let step = t.currentStep { Text(step).font(.caption).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text((t.due ?? .now) <= entry.date ? "RIGHT NOW" : "NEXT · \(t.due!.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.heavy)).kerning(1).foregroundStyle(Theme.grey)
                    Text(t.title).font(.system(.title3, weight: .heavy)).lineLimit(family == .systemSmall ? 2 : 3)
                    if let step = t.currentStep {
                        Text(step).font(.caption.weight(.semibold)).foregroundStyle(Theme.grey).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button(intent: CompleteTaskIntent(taskID: t.id.uuidString)) {
                        Label("Done", systemImage: "checkmark").font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent(SharedStore.defaults.string(forKey: Keys.accent) ?? "orange"))
                    .foregroundStyle(Theme.onAccent)
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            let clear = VStack(alignment: .leading, spacing: 4) {
                Text("All clear.").font(.headline.weight(.heavy))
                if family != .accessoryInline { Text("Nothing needs you right now.").font(.caption) }
            }
            // Lock-screen widgets pick their own colors; only the white home-screen tile needs dark ink.
            if family == .accessoryInline || family == .accessoryRectangular { clear } else { clear.foregroundStyle(Theme.ink) }
        }
    }
}

struct NudgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeWidget", provider: Provider()) { NudgeWidgetView(entry: $0) }
            .configurationDisplayName("Right now")
            .description("The one thing to do next, with a Done button.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct NudgeWidgetBundle: WidgetBundle {
    var body: some Widget { NudgeWidget() }
}
