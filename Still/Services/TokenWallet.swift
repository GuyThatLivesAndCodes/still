import Foundation
import Observation

/// Early-reveal tokens: 2 free per calendar week. Never needed for journaling,
/// privacy, or streaks.
@Observable
final class TokenWallet {
    static let weeklyFree = 2

    private(set) var weekKey: String
    private(set) var used: Int

    init() {
        weekKey = UserDefaults.standard.string(forKey: "still.tokens.week") ?? ""
        used = UserDefaults.standard.integer(forKey: "still.tokens.weekUsed")
    }

    private static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    func available(at now: Date = .now) -> Int {
        weekKey == Self.key(for: now) ? max(0, Self.weeklyFree - used) : Self.weeklyFree
    }

    var nextReset: Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: .now)?.end
            ?? cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now)) ?? .now
    }

    @discardableResult
    func spend(at now: Date = .now) -> Bool {
        let current = Self.key(for: now)
        if weekKey != current {
            weekKey = current
            used = 0
        }
        guard used < Self.weeklyFree else { return false }
        used += 1
        UserDefaults.standard.set(weekKey, forKey: "still.tokens.week")
        UserDefaults.standard.set(used, forKey: "still.tokens.weekUsed")
        return true
    }
}
