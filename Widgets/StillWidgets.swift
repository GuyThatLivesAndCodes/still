import WidgetKit
import SwiftUI

// MARK: - Palette (mirrors the app)

private enum W {
    static let ink = Color(white: 0.95)
    static let secondary = Color(white: 0.64)
    static let tertiary = Color(white: 0.55)
    static let accent = Color(red: 0.667, green: 0.706, blue: 0.941)
    static let glass = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.14)
}

@main
struct StillWidgetBundle: WidgetBundle {
    var body: some Widget {
        WriteWidget()
        StreakWidget()
        if #available(iOS 18.0, *) {
            WriteControl()
        }
    }
}

// MARK: - Timeline

struct StillEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StillProvider: TimelineProvider {
    func placeholder(in context: Context) -> StillEntry {
        StillEntry(date: .now, snapshot: WidgetSnapshot(days: 12, deadline: .now.addingTimeInterval(9 * 3600)))
    }

    func getSnapshot(in context: Context, completion: @escaping (StillEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StillEntry(date: .now, snapshot: WidgetShared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StillEntry>) -> Void) {
        let snap = WidgetShared.read()
        let now = Date.now
        var dates: [Date] = [now]
        // Re-render when the countdown should appear, when the streak would lapse, and at midnight.
        if let deadline = snap.deadline, snap.hasRunningStreak(at: now) {
            let countdownStart = deadline.addingTimeInterval(-12 * 3600)
            if countdownStart > now { dates.append(countdownStart) }
            dates.append(deadline.addingTimeInterval(1))
        }
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        dates.append(midnight)
        let entries = dates.sorted().map { StillEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: - Write widget

struct WriteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WriteWidget", provider: StillProvider()) { entry in
            WriteWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
                .widgetURL(WidgetShared.writeURL)
        }
        .configurationDisplayName("Write")
        .description("Open straight to a blank entry.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WriteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StillEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pencil.line")
                    .font(.system(size: 20, weight: .semibold))
            }
            .widgetAccentable()
            .accessibilityLabel("Write in still.")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("still.").font(.headline).widgetAccentable()
                Text(entry.snapshot.wroteToday(at: entry.date) ? "Something else on your mind?" : "What's here right now?")
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("Write in still.", systemImage: "pencil.line")
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var prompt: String {
        entry.snapshot.wroteToday(at: entry.date) ? "Anything else?" : "What's here right now?"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("still.")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(W.ink)
                Spacer()
                StreakBadge(snapshot: entry.snapshot, now: entry.date)
            }
            Spacer()
            Text(entry.date.formatted(.dateTime.weekday(.wide)))
                .font(.caption)
                .foregroundStyle(W.tertiary)
            Text(prompt)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(W.ink)
                .lineLimit(2)
                .padding(.bottom, 10)
            pill(height: 34, label: "Write")
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("still.")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(W.ink)
                Spacer()
                StreakBadge(snapshot: entry.snapshot, now: entry.date)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 15, weight: .medium))
                Text(prompt)
                    .font(.system(size: 16))
                Spacer()
            }
            .foregroundStyle(W.secondary)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(W.glass, in: Capsule())
            .overlay(Capsule().strokeBorder(W.stroke, lineWidth: 1))
        }
    }

    private func pill(height: CGFloat, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.line").font(.system(size: 13, weight: .semibold))
            Text(label).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(W.ink, in: Capsule())
    }
}

/// Small top-right streak indicator. Shows a live countdown under 12 hours.
struct StreakBadge: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if snapshot.hasRunningStreak(at: now), let deadline = snapshot.deadline {
            if deadline.timeIntervalSince(now) < 12 * 3600 {
                Text(deadline, style: .timer)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(W.accent)
                    .frame(maxWidth: 64, alignment: .trailing)
            } else {
                Text("\(snapshot.days)d")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(W.secondary)
            }
        }
    }
}

// MARK: - Streak widget

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: StillProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
                .widgetURL(WidgetShared.writeURL)
        }
        .configurationDisplayName("Streak")
        .description("Your streak, and the time left when it matters.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StillEntry

    private var snap: WidgetSnapshot { entry.snapshot }
    private var running: Bool { snap.hasRunningStreak(at: entry.date) }
    private var urgent: Bool {
        guard running, let d = snap.deadline else { return false }
        return d.timeIntervalSince(entry.date) < 12 * 3600
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(running ? "\(snap.days)" : "s.")
                        .font(.system(size: 20, weight: .semibold))
                        .widgetAccentable()
                    if running {
                        Text("days").font(.system(size: 9, weight: .medium))
                    }
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(running ? "\(snap.days)-day streak" : "still.")
                    .font(.headline)
                    .widgetAccentable()
                if urgent, let d = snap.deadline {
                    HStack(spacing: 4) {
                        Text(d, style: .timer).monospacedDigit()
                        Text("left")
                    }
                    .font(.caption)
                } else {
                    Text(statusLine).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            if urgent, let d = snap.deadline {
                Text("Streak: \(d, style: .timer) left")
            } else {
                Text(running ? "\(snap.days)-day streak" : "Write in still.")
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("still.")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(W.ink)
                Spacer()
                Text(running ? "\(snap.days)" : "—")
                    .font(.system(size: 48, weight: .semibold))
                    .kerning(-2)
                    .foregroundStyle(W.ink)
                if urgent, let d = snap.deadline {
                    HStack(spacing: 4) {
                        Circle().fill(W.accent).frame(width: 6, height: 6)
                        Text(d, style: .timer).monospacedDigit().fontWeight(.semibold)
                        Text("left")
                    }
                    .font(.caption)
                    .foregroundStyle(W.ink)
                } else {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(W.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusLine: String {
        if !snap.streakVisible { return "Tap to write" }
        if snap.paused { return "Paused" }
        if running { return snap.days == 1 ? "day of showing up" : "days of showing up" }
        return "Tap to start a streak"
    }
}

// MARK: - Control Center / Action Button / Lock Screen control

@available(iOS 18.0, *)
struct WriteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.guythatlives.still.write") {
            ControlWidgetButton(action: OpenWriteIntent()) {
                Label("Write", systemImage: "pencil.line")
            }
        }
        .displayName("Write in still.")
        .description("Open straight to a blank entry.")
    }
}
