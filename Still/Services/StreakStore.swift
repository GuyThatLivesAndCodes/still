import Foundation
import Observation

struct StreakState: Codable, Equatable {
    var days: Int = 0
    /// Start of the current 36-hour window.
    var anchor: Date?
    var lastCreditedDay: Date?
    var revivesYear: Int = 0
    var revivesUsed: Int = 0
}

@Observable
final class StreakStore {
    static let window: TimeInterval = 36 * 3600
    static let revivesPerYear = 2

    private(set) var state: StreakState
    private let storageKey = "still.streak.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           var decoded = try? JSONDecoder().decode(StreakState.self, from: data) {
            // Pausing was removed. Anyone paused (or about to be) gets a fresh
            // 36-hour window instead of a streak that silently expired.
            if let legacy = try? JSONDecoder().decode(LegacyPause.self, from: data),
               legacy.pausedAt != nil || legacy.pauseRequestedAt != nil,
               decoded.days > 0 {
                decoded.anchor = .now
            }
            state = decoded
        } else {
            state = StreakState()
        }
        save()
    }

    private struct LegacyPause: Decodable {
        var pausedAt: Date?
        var pauseRequestedAt: Date?
    }

    // MARK: Derived

    var days: Int { state.days }

    var deadline: Date? {
        guard state.days > 0, let anchor = state.anchor else { return nil }
        return anchor.addingTimeInterval(Self.window)
    }

    func isExpired(at now: Date = .now) -> Bool {
        guard let deadline else { return false }
        return now > deadline
    }

    func isActive(at now: Date = .now) -> Bool {
        state.days > 0 && !isExpired(at: now)
    }

    /// Time left in the current window; nil when there is no running streak.
    func remaining(at now: Date = .now) -> TimeInterval? {
        guard let deadline, now <= deadline else { return nil }
        return deadline.timeIntervalSince(now)
    }

    var revivesLeft: Int {
        let year = Calendar.current.component(.year, from: .now)
        return state.revivesYear == year ? max(0, Self.revivesPerYear - state.revivesUsed) : Self.revivesPerYear
    }

    // MARK: Mutations

    func recordEntry(at now: Date = .now) {
        let cal = Calendar.current
        if state.days == 0 || isExpired(at: now) {
            state.days = 1
            state.lastCreditedDay = now
        } else if let last = state.lastCreditedDay, !cal.isDate(last, inSameDayAs: now) {
            state.days += 1
            state.lastCreditedDay = now
        }
        state.anchor = now
        save()
    }

    @discardableResult
    func revive(at now: Date = .now) -> Bool {
        guard state.days > 0, isExpired(at: now), revivesLeft > 0 else { return false }
        let year = Calendar.current.component(.year, from: now)
        if state.revivesYear != year {
            state.revivesYear = year
            state.revivesUsed = 0
        }
        state.revivesUsed += 1
        state.anchor = now
        save()
        return true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
