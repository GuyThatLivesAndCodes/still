import Foundation
import SwiftData
import WatchConnectivity

/// iPhone side of the Apple Watch link. The watch sends text; the iPhone
/// encrypts and seals it. The iPhone sends back streak info only.
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    private var container: ModelContainer?
    private var streak: StreakStore?

    func start(container: ModelContainer, streak: StreakStore) {
        self.container = container
        self.streak = streak
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var context: [String: Any] = [
            "days": snapshot.days,
            "visible": snapshot.streakVisible
        ]
        if let deadline = snapshot.deadline { context["deadline"] = deadline.timeIntervalSince1970 }
        if let last = snapshot.lastEntry { context["lastEntry"] = last.timeIntervalSince1970 }
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard let container = self.container, let streak = self.streak else { return }
            EntryWriter.syncSurroundings(context: container.mainContext, streak: streak)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let text = userInfo["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let created = (userInfo["createdAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? .now
        Task { @MainActor in
            guard let container = self.container, let streak = self.streak else { return }
            try? EntryWriter.seal(text, source: .watch, createdAt: created,
                                  context: container.mainContext, streak: streak)
        }
    }
}
