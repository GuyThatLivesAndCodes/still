import Foundation
import SwiftData
import UserNotifications

/// Housekeeping for sealed entries: refunds early-reveal tokens once an entry
/// reaches its real open time, and schedules the "your entries opened" note
/// for around noon (never exactly, never at midnight when they unlock).
@MainActor
enum VaultCare {
    private static let scheduledKey = "still.unlock.scheduled"

    static func run(context: ModelContext, now: Date = .now) {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        refundMatured(entries, context: context, now: now)
        scheduleUnlocks(entries, now: now)
    }

    /// Returns how many tokens came back.
    @discardableResult
    static func refundMatured(_ entries: [Entry], context: ModelContext, now: Date = .now) -> Int {
        var count = 0
        for entry in entries where entry.revealedEarlyAt != nil && !entry.tokenRefunded && now >= entry.opensAt {
            entry.tokenRefunded = true
            TokenWallet.shared.refund(at: now)
            count += 1
        }
        if count > 0 { try? context.save() }
        return count
    }

    /// Late morning to early afternoon, the same minute each time for a given day.
    static func noonish(on day: Date) -> Date {
        let cal = Calendar.current
        let ordinal = cal.ordinality(of: .day, in: .era, for: day) ?? 0
        let offset = (ordinal * 37 % 61) - 30 // -30...+30 minutes
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return noon.addingTimeInterval(Double(offset) * 60 + Double(ordinal % 50))
    }

    static func scheduleUnlocks(_ entries: [Entry], now: Date = .now) {
        let old = UserDefaults.standard.stringArray(forKey: scheduledKey) ?? []
        Notifier.cancel(old)
        guard Notifier.unlocksEnabled else {
            UserDefaults.standard.removeObject(forKey: scheduledKey)
            return
        }

        let cal = Calendar.current
        let upcoming = entries.filter { !$0.isPendingDeletion && $0.opensAt > now.addingTimeInterval(-86400) }
        let byDay = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.opensAt) }

        var ids: [String] = []
        for day in byDay.keys.sorted().prefix(20) {
            let fire = noonish(on: day)
            guard fire > now, let group = byDay[day] else { continue }
            let id = "still.unlock.\(Int(day.timeIntervalSince1970))"
            let early = group.filter { $0.revealedEarlyAt != nil }.count
            let fresh = group.count - early
            var body: String
            if fresh == 0 {
                body = early == 1 ? "The entry you opened early has reached its day. Your early reveal is back."
                                  : "The entries you opened early have reached their day. Your early reveals are back."
            } else {
                let from = earliestLabel(group)
                body = fresh == 1 ? "Your entry from \(from) opened today. It's ready when you are."
                                  : "\(fresh) entries from \(from) opened today. They're ready when you are."
                if early > 0 { body += " An early reveal came back too." }
            }
            Notifier.schedule(id: id, title: "Ready to read", body: body, at: fire, route: "vault")
            ids.append(id)
        }
        UserDefaults.standard.set(ids, forKey: scheduledKey)
    }

    private static func earliestLabel(_ group: [Entry]) -> String {
        let first = group.map(\.createdAt).min() ?? .now
        return first.formatted(.dateTime.weekday(.wide))
    }
}
