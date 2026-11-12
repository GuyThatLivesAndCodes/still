import Foundation
import UserNotifications

/// Schedules one gentle, personalized reminder at a time, near the user's usual
/// writing time. Rescheduled whenever the app opens or an entry is sealed.
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

    static func reschedule(entryDates: [Date], streak: StreakStore, enabled: Bool, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        let cal = Calendar.current
        let minute = typicalMinute(of: entryDates) ?? (20 * 60 + 30)
        let wroteToday = entryDates.first.map { cal.isDate($0, inSameDayAs: now) } ?? false

        func at(dayOffset: Int) -> Date? {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else { return nil }
            return cal.date(byAdding: .minute, value: minute, to: day)
        }

        guard var fire = wroteToday ? at(dayOffset: 1) : at(dayOffset: 0) else { return }
        if fire <= now.addingTimeInterval(60), let tomorrow = at(dayOffset: 1) { fire = tomorrow }

        let aiLine = NudgeWriter.current
        var body = aiLine ?? "Take a moment for yourself today."
        if let deadline = streak.deadline, deadline > now {
            // Never let the reminder land after the streak would end.
            if fire > deadline.addingTimeInterval(-3600) {
                let earlier = deadline.addingTimeInterval(-3 * 3600)
                if earlier > now.addingTimeInterval(60) { fire = earlier }
            }
            let hoursLeft = Int(deadline.timeIntervalSince(fire) / 3600)
            if hoursLeft >= 1 && body.count <= 80 {
                body += " You have \(hoursLeft) hour\(hoursLeft == 1 ? "" : "s") left on your streak."
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "still."
        content.body = body
        content.sound = nil

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
