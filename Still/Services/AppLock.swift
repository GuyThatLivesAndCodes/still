import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLock {
    var isLocked: Bool

    init() {
        isLocked = UserDefaults.standard.bool(forKey: "faceIDEnabled")
    }

    func lockIfEnabled() {
        if UserDefaults.standard.bool(forKey: "faceIDEnabled") { isLocked = true }
    }

    /// Returns true on success. Falls back to the device passcode.
    @discardableResult
    func authenticate(reason: String = "Unlock your journal") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return true
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }
}
