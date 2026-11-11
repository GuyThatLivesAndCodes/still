import WidgetKit
import SwiftUI

/// Watch complications. They only launch the app, so they need no shared data.
@main
struct StillWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchWriteComplication()
    }
}

struct WatchEntry: TimelineEntry {
    let date: Date
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        // New opener each day.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [WatchEntry(date: .now)], policy: .after(midnight)))
    }
}

struct WatchWriteComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchWrite", provider: WatchProvider()) { entry in
            WatchWriteView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Write")
        .description("Open still. to write.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct WatchWriteView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("still.").font(.headline).widgetAccentable()
                Text(Openers.forDay(entry.date)).font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "pencil.line")
                .font(.system(size: 20, weight: .semibold))
                .widgetLabel("still.")
        case .accessoryInline:
            Label("Write in still.", systemImage: "pencil.line")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Text("s.")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }
}
