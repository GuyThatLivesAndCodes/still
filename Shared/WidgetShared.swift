import Foundation

/// The small, non-sensitive state widgets need. Never contains entry text.
struct WidgetSnapshot: Codable {
    var days: Int = 0
    var deadline: Date?
    var paused: Bool = false
    var streakVisible: Bool = true
    var lastEntry: Date?

    func wroteToday(at now: Date = .now) -> Bool {
        guard let lastEntry else { return false }
        return Calendar.current.isDate(lastEntry, inSameDayAs: now)
    }

    func hasRunningStreak(at now: Date = .now) -> Bool {
        guard streakVisible, !paused, days > 0, let deadline else { return false }
        return deadline > now
    }
}

enum WidgetShared {
    static let appGroup = "group.com.guythatlives.still"
    static let writeURL = URL(string: "still://write")!
    private static let key = "still.widget.snapshot"

    /// Falls back to standard defaults if the App Group isn't available
    /// (for example, when a signing tool strips it). Widgets then show defaults.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func read() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    static func write(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }
}
