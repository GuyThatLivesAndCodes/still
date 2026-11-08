import Foundation
import Observation

/// Early-reveal tokens: 3 free per calendar month. Never needed for journaling,
/// privacy, or streaks.
@Observable
final class TokenWallet {
    static let monthlyFree = 3

    private(set) var monthKey: String
    private(set) var used: Int

    init() {
        monthKey = UserDefaults.standard.string(forKey: "still.tokens.month") ?? ""
        used = UserDefaults.standard.integer(forKey: "still.tokens.used")
    }

    private static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    func available(at now: Date = .now) -> Int {
        monthKey == Self.key(for: now) ? max(0, Self.monthlyFree - used) : Self.monthlyFree
    }

    var nextReset: Date {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        return cal.date(byAdding: .month, value: 1, to: start) ?? .now
    }

    @discardableResult
    func spend(at now: Date = .now) -> Bool {
        let current = Self.key(for: now)
        if monthKey != current {
            monthKey = current
            used = 0
        }
        guard used < Self.monthlyFree else { return false }
        used += 1
        UserDefaults.standard.set(monthKey, forKey: "still.tokens.month")
        UserDefaults.standard.set(used, forKey: "still.tokens.used")
        return true
    }
}
