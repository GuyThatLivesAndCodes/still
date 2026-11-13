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
/// entries waiting at that point share a single note. The note is written right
/// away (while the app is open) and held back until the timer ends, when a
/// notification lets the person know it's there.
@MainActor
enum ReflectionQueue {
    /// Nil when AI is off or nothing is available, which also hides the Notes tab.
    nonisolated static var provider: ReflectionProvider? {
        AIService.isActive ? AIReflections() : nil
    }

    private static let idsKey = "still.reflection.pending"
    private static let fireKey = "still.reflection.fireAt"
    /// The fire date the waiting note was written for.
    private static let preparedKey = "still.reflection.preparedFor"

    nonisolated static var isEnabled: Bool { provider != nil }

    nonisolated static var pendingIDs: [String] {
        UserDefaults.standard.stringArray(forKey: idsKey) ?? []
    }

    nonisolated static var fireAt: Date? {
        UserDefaults.standard.object(forKey: fireKey) as? Date
    }

    private static var preparedFor: Date? {
        UserDefaults.standard.object(forKey: preparedKey) as? Date
    }

    /// Bumped per job so a slow reply for an older batch is thrown away.
    private static var job = 0

    static func enqueue(_ id: UUID, context: ModelContext, now: Date = .now) {
        guard isEnabled else { return }
        var ids = pendingIDs
        // The last batch already went out: start a new one.
        if let fire = fireAt, fire <= now, preparedFor == fire { ids = [] }
        ids.append(id.uuidString)
        UserDefaults.standard.set(ids, forKey: idsKey)
        UserDefaults.standard.set(now.addingTimeInterval(Double.random(in: 600...1800)), forKey: fireKey)
        UserDefaults.standard.removeObject(forKey: preparedKey)
        Notifier.cancel([Notifier.noteID])
        Notifier.askOnce()
        BackgroundWork.run("still.note") { await prepare(context: context) }
    }

    /// Called when the app opens: finishes a batch whose note never got written,
    /// and clears batches that have been delivered.
    static func deliverIfDue(context: ModelContext, now: Date = .now) async {
        guard let fire = fireAt else { return }
        if preparedFor == fire {
            if fire <= now { clear() }
            return
        }
        await prepare(context: context)
    }

    private static func prepare(context: ModelContext) async {
        guard let provider, let fire = fireAt else { return }
        let ids = Set(pendingIDs)
        guard !ids.isEmpty else { clear(); return }
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let texts = all.filter { ids.contains($0.id.uuidString) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.contextText() }
        guard !texts.isEmpty else { clear(); return }

        job += 1
        let mine = job
        guard let reply = try? await provider.reflect(on: texts) else { return }
        // A newer entry arrived while this was being written; that job wins.
        guard mine == job, fireAt == fire, let sealed = try? EntryCipher.seal(reply) else { return }

        let now = Date.now
        // Replace any note still waiting from an earlier version of this batch.
        let waiting = (try? context.fetch(FetchDescriptor<Note>()))?.filter { !$0.isVisible(at: now) } ?? []
        waiting.forEach { context.delete($0) }

        let deliver = max(fire, now)
        let note = Note(cipher: sealed, entryCount: texts.count, createdAt: now)
        note.deliverAt = deliver
        context.insert(note)
        try? context.save()
        UserDefaults.standard.set(fire, forKey: preparedKey)

        if deliver > now.addingTimeInterval(5), Notifier.repliesEnabled {
            Notifier.schedule(id: Notifier.noteID,
                              title: "still. wrote back",
                              body: texts.count > 1
                                  ? "A note about your last \(texts.count) entries is waiting for you."
                                  : "A note about what you sealed is waiting for you.",
                              at: deliver, route: "note:\(note.id.uuidString)")
        }
    }

    private static func clear() {
        UserDefaults.standard.removeObject(forKey: idsKey)
        UserDefaults.standard.removeObject(forKey: fireKey)
        UserDefaults.standard.removeObject(forKey: preparedKey)
    }
}
