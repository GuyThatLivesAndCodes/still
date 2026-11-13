import Foundation
import UserNotifications

/// Schedules gentle reminders near the user's usual writing time. Rescheduled whenever the app opens or an entry is sealed.
enum ReminderService {
    static let identifier = "still.reminder"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Typical writing time as minutes after midnight (circular mean of recent entries).
    static func typicalMinute(of dates: [Date]) -> Int? {
        let recent = dates.prefix(30)
        guard !recent.isEmpty else { return nil }
        let cal = Calendar.current
        var x = 0.0, y = 0.0
        for d in recent {
            let c = cal.dateComponents([.hour, .minute], from: d)
            let minute = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            let angle = minute / 1440.0 * 2 * .pi
            x += cos(angle); y += sin(angle)
        }
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * 1440).rounded()) % 1440
    }

    static func periodName(forMinute m: Int) -> String {
        switch m / 60 {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }

    /// Gap after the usual time before the "still haven't written" follow-up.
    static let followUpDelay: TimeInterval = 90 * 60
    /// The streak warning is skipped when it would land this close to another reminder.
    static let overlapWindow: TimeInterval = 45 * 60

    /// Every id this service may have pending (two days ahead, three kinds each).
    static var allIdentifiers: [String] {
        [identifier] + (0...2).flatMap { d in ["\(identifier).\(d)", "\(identifier).follow.\(d)"] }
            + ["\(identifier).expiry"]
    }

    /// Up to three reminders per unwritten day: the usual time, a follow-up
    /// ~1.5 hours later, and one an hour before the streak ends (unless it would
    /// overlap another). Covers today (if not written) and the next day, so
    /// reminders still come if the app isn't opened. Sealing reschedules,
    /// which clears everything for a day that's been written.
    static func reschedule(entryDates: [Date], streak: StreakStore, enabled: Bool, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
        guard enabled else { return }

        let cal = Calendar.current
        let minute = typicalMinute(of: entryDates) ?? (20 * 60 + 30)
        let wroteToday = entryDates.first.map { cal.isDate($0, inSameDayAs: now) } ?? false
        let deadline = streak.deadline.flatMap { $0 > now ? $0 : nil }
        let soonest = now.addingTimeInterval(60)

        func usual(dayOffset: Int) -> Date? {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { return nil }
            return cal.date(byAdding: .minute, value: minute, to: day)
        }

        var planned: [(id: String, at: Date, body: String)] = []
        var usedAI = false
        for offset in (wroteToday ? [1, 2] : [0, 1]) {
            guard var first = usual(dayOffset: offset) else { continue }
            // Never let the main reminder land in the streak's last hour.
            if let deadline, first > deadline.addingTimeInterval(-3600), first <= deadline {
                let earlier = deadline.addingTimeInterval(-3 * 3600)
                if earlier > soonest && cal.isDate(earlier, inSameDayAs: first) { first = earlier }
            }
            let follow = first.addingTimeInterval(followUpDelay)

            if first > soonest {
                var body = "Take a moment for yourself today."
                if !usedAI, let line = NudgeWriter.current { body = line; usedAI = true }
                if let deadline, deadline > first {
                    let hoursLeft = Int(deadline.timeIntervalSince(first) / 3600)
                    if hoursLeft >= 1 && hoursLeft <= 24 && body.count <= 80 {
                        body += " You have \(hoursLeft) hour\(hoursLeft == 1 ? "" : "s") left on your streak."
                    }
                }
                planned.append(("\(identifier).\(offset)", first, body))
            }
            // Follow-up only while the streak (if any) is still alive.
            if follow > soonest, deadline.map({ follow < $0 }) ?? true {
                planned.append(("\(identifier).follow.\(offset)", follow,
                                "Still time to write today. Even one line counts."))
            }
        }

        if let deadline {
            let warn = deadline.addingTimeInterval(-3600)
            let overlaps = planned.contains { abs($0.at.timeIntervalSince(warn)) < overlapWindow }
            if warn > soonest && !overlaps {
                let days = streak.days
                planned.append(("\(identifier).expiry", warn,
                                "Your \(days)-day streak ends in an hour. A few words keeps it going."))
            }
        }

        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = "still."
            content.body = item.body
            content.sound = item.id.hasSuffix("expiry") ? .default : nil
            content.threadIdentifier = "still.reminder"
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
