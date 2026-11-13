import Foundation
import UserNotifications
import UIKit

/// Local notifications for notes, chat replies and unlocked entries, plus
/// routing when one is tapped. Nothing private goes on the lock screen.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static let noteID = "still.note"
    static func chatID(_ note: UUID) -> String { "still.chat.\(note.uuidString)" }

    /// Settings → Notifications. Notes and replies are on by default.
    static let repliesKey = "notify.replies"
    static let unlocksKey = "notify.unlocks"
    private static let askedKey = "notify.asked"

    static var repliesEnabled: Bool { UserDefaults.standard.object(forKey: repliesKey) as? Bool ?? true }
    static var unlocksEnabled: Bool { UserDefaults.standard.object(forKey: unlocksKey) as? Bool ?? true }

    /// The chat currently on screen; its own replies don't need a banner.
    @MainActor static var openChat: UUID?

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks once, the first time something worth notifying about happens.
    static func askOnce() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        Task { _ = await ReminderService.requestAuthorization() }
    }

    static func schedule(id: String, title: String, body: String, at date: Date, route: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        content.threadIdentifier = id.hasPrefix("still.unlock") ? "still.unlock" : "still.notes"
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        Task { @MainActor in
            if let chat = Notifier.openChat, id == Notifier.chatID(chat) {
                completionHandler([])
            } else {
                completionHandler([.banner, .list])
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String ?? ""
        Task { @MainActor in
            AppRouter.shared.open(route: route)
            completionHandler()
        }
    }
}

/// Keeps a short piece of work alive for a few seconds if the app is closed
/// right after sealing or sending, so the reply can still be prepared.
enum BackgroundWork {
    @MainActor
    static func run(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { box.end() }
        }
        Task { @MainActor in
            await work()
            box.end()
        }
    }

    @MainActor
    private final class TaskBox: @unchecked Sendable {
        var id = UIBackgroundTaskIdentifier.invalid
        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
}
