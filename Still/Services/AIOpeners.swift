import Foundation
import SwiftData

/// Personal openers written by the AI from recent entries and notes.
/// Returns the cached set instantly and refreshes in the background, so the
/// Today screen never waits on the model. New users (under 3 entries) only
/// see the starter set.
struct AIOpeners: OpenerProvider {
    let container: ModelContainer

    private static let cacheKey = "ai.openers.cipher"
    private static let dateKey = "ai.openers.date"
    private static let countKey = "ai.openers.entryCount"
    private static let minEntries = 3
    private static let maxAge: TimeInterval = 12 * 3600

    @MainActor private static var refreshing = false

    func personalOpeners() async -> [String] {
        guard AIService.isActive else { return [] }
        let cached = Self.cached()
        let container = container
        Task { @MainActor in await Self.refreshIfStale(container: container) }
        return cached
    }

    private static func cached() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let text = try? EntryCipher.open(data) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    @MainActor
    private static func refreshIfStale(container: ModelContainer) async {
        guard !refreshing, AIService.isActive else { return }
        let context = ModelContext(container)
        var latest = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        latest.fetchLimit = 6
        let entries = (try? context.fetch(latest)) ?? []
        let total = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard total >= minEntries else { return }

        let defaults = UserDefaults.standard
        let age = (defaults.object(forKey: dateKey) as? Date).map { Date.now.timeIntervalSince($0) } ?? .infinity
        guard age > maxAge || defaults.integer(forKey: countKey) != total else { return }

        var notes = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        notes.fetchLimit = 3
        let texts = entries.reversed().map { $0.plainText() }
            + ((try? context.fetch(notes)) ?? []).reversed().map { $0.plainText() }

        refreshing = true
        defer { refreshing = false }
        guard let reply = try? await AIService.run(.openers(texts)) else { return }
        let openers = AIService.parseOpeners(reply)
        guard !openers.isEmpty, let sealed = try? EntryCipher.seal(openers.joined(separator: "\n")) else { return }
        defaults.set(sealed, forKey: cacheKey)
        defaults.set(Date.now, forKey: dateKey)
        defaults.set(total, forKey: countKey)
    }
}
