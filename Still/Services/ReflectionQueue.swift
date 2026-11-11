import Foundation
import SwiftData

/// Something that can write a short, warm reflection.
protocol ReflectionProvider {
    func reflect(on entries: [String]) async throws -> String
}

/// Routes reflections through whichever engine the user's AI setting picks.
struct AIReflections: ReflectionProvider {
    func reflect(on entries: [String]) async throws -> String {
        try await AIService.run(.reflection(entries))
    }
}

/// Coalesces submissions: each new entry resets a 10–30 minute timer, and all
/// entries waiting at that point share a single note.
enum ReflectionQueue {
    /// Nil when AI is off or nothing is available, which also hides the Notes tab.
    static var provider: ReflectionProvider? {
        AIService.isActive ? AIReflections() : nil
    }

    private static let idsKey = "still.reflection.pending"
    private static let fireKey = "still.reflection.fireAt"

    static var isEnabled: Bool { provider != nil }

    static var pendingIDs: [String] {
        UserDefaults.standard.stringArray(forKey: idsKey) ?? []
    }

    static var fireAt: Date? {
        UserDefaults.standard.object(forKey: fireKey) as? Date
    }

    static func enqueue(_ id: UUID, now: Date = .now) {
        guard isEnabled else { return }
        var ids = pendingIDs
        ids.append(id.uuidString)
        UserDefaults.standard.set(ids, forKey: idsKey)
        UserDefaults.standard.set(now.addingTimeInterval(Double.random(in: 600...1800)), forKey: fireKey)
    }

    @MainActor
    static func deliverIfDue(context: ModelContext, now: Date = .now) async {
        guard let provider, let fire = fireAt, now >= fire else { return }
        let ids = Set(pendingIDs)
        guard !ids.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let texts = all.filter { ids.contains($0.id.uuidString) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.plainText() }
        guard !texts.isEmpty else { clear(); return }
        do {
            let reply = try await provider.reflect(on: texts)
            let note = Note(cipher: try EntryCipher.seal(reply), entryCount: texts.count)
            context.insert(note)
            try? context.save()
            clear()
        } catch {
            // Leave the queue in place; it will retry next time the app is opened.
        }
    }

    private static func clear() {
        UserDefaults.standard.removeObject(forKey: idsKey)
        UserDefaults.standard.removeObject(forKey: fireKey)
    }
}
