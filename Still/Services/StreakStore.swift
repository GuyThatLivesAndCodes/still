import Foundation
import Observation

struct StreakState: Codable {
    var days: Int = 0
    /// Start of the current 36-hour window.
    var anchor: Date?
    var lastCreditedDay: Date?
    var pauseRequestedAt: Date?
    var pausedAt: Date?
    var resumeRequestedAt: Date?
    var revivesYear: Int = 0
    var revivesUsed: Int = 0
}

@Observable
final class StreakStore {
    static let window: TimeInterval = 36 * 3600
    static let switchDelay: TimeInterval = 6 * 3600
    static let revivesPerYear = 2

    private(set) var state: StreakState
    private let storageKey = "still.streak.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(StreakState.self, from: data) {
            state = decoded
        } else {
            state = StreakState()
        }
        refresh()
    }

    // MARK: Derived

    var isPaused: Bool { state.pausedAt != nil }
    var days: Int { state.days }

    var deadline: Date? {
        guard !isPaused, state.days > 0, let anchor = state.anchor else { return nil }
        return anchor.addingTimeInterval(Self.window)
    }

    func isExpired(at now: Date = .now) -> Bool {
        guard let deadline else { return false }
        return now > deadline
    }

    func isActive(at now: Date = .now) -> Bool {
        state.days > 0 && !isPaused && !isExpired(at: now)
    }

    /// Time left in the current window; nil when there is no running streak.
    func remaining(at now: Date = .now) -> TimeInterval? {
        guard let deadline, now <= deadline else { return nil }
        return deadline.timeIntervalSince(now)
    }

    var pauseEffectiveAt: Date? { state.pauseRequestedAt?.addingTimeInterval(Self.switchDelay) }
    var resumeEffectiveAt: Date? { state.resumeRequestedAt?.addingTimeInterval(Self.switchDelay) }

    var revivesLeft: Int {
        let year = Calendar.current.component(.year, from: .now)
        return state.revivesYear == year ? max(0, Self.revivesPerYear - state.revivesUsed) : Self.revivesPerYear
    }

    // MARK: Mutations

    /// Applies pending pause/resume requests whose 6-hour wait has passed.
    func refresh(now: Date = .now) {
        var s = state
        var changed = false
        if let effective = pauseEffectiveAt, now >= effective {
            s.pausedAt = effective
            s.pauseRequestedAt = nil
            changed = true
        }
        if let effective = resumeEffectiveAt, now >= effective {
            s.pausedAt = nil
            s.resumeRequestedAt = nil
            if s.days > 0 { s.anchor = effective }
            changed = true
        }
        if changed { state = s; save() }
    }

    func recordEntry(at now: Date = .now) {
        refresh(now: now)
        guard !isPaused else { return }
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

    func requestPause(at now: Date = .now) {
        guard !isPaused, state.pauseRequestedAt == nil else { return }
        state.pauseRequestedAt = now
        save()
    }

    func cancelPauseRequest() {
        state.pauseRequestedAt = nil
        save()
    }

    func requestResume(at now: Date = .now) {
        guard isPaused, state.resumeRequestedAt == nil else { return }
        state.resumeRequestedAt = now
        save()
    }

    func cancelResumeRequest() {
        state.resumeRequestedAt = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
