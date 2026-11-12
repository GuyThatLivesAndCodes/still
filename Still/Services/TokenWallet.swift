import Foundation
import Observation

/// Early-reveal tokens: 2 free per calendar week. Never needed for journaling,
/// privacy, or streaks. A token spent on an entry comes back once that entry
/// would have opened anyway.
@Observable
final class TokenWallet {
    static let shared = TokenWallet()
    static let weeklyFree = 2
    /// Refunds that land in a later week are kept here, up to this many.
    static let maxBonus = 4

    private(set) var weekKey: String
    private(set) var used: Int
    private(set) var bonus: Int

    init() {
        weekKey = UserDefaults.standard.string(forKey: "still.tokens.week") ?? ""
        used = UserDefaults.standard.integer(forKey: "still.tokens.weekUsed")
        bonus = UserDefaults.standard.integer(forKey: "still.tokens.bonus")
    }

    private static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    private func weeklyLeft(at now: Date) -> Int {
        weekKey == Self.key(for: now) ? max(0, Self.weeklyFree - used) : Self.weeklyFree
    }

    func available(at now: Date = .now) -> Int { weeklyLeft(at: now) + bonus }

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
        if used < Self.weeklyFree {
            used += 1
        } else if bonus > 0 {
            bonus -= 1
        } else {
            return false
        }
        persist()
        return true
    }

    /// Gives one token back: to this week's allowance if it came from it, otherwise as a bonus.
    func refund(at now: Date = .now) {
        if weekKey == Self.key(for: now), used > 0 {
            used -= 1
        } else {
            bonus = min(Self.maxBonus, bonus + 1)
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(weekKey, forKey: "still.tokens.week")
        UserDefaults.standard.set(used, forKey: "still.tokens.weekUsed")
        UserDefaults.standard.set(bonus, forKey: "still.tokens.bonus")
    }
}
