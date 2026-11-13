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
    private static let styleKey = "ai.openers.style"
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

    func freshOpeners() async -> [String] {
        guard AIService.isActive else { return [] }
        return await Self.refresh(container: container, force: true) ?? []
    }

    private static func cached() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let text = try? EntryCipher.open(data) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    @MainActor
    private static func refreshIfStale(container: ModelContainer) async {
        _ = await refresh(container: container, force: false)
    }

    /// Returns the new set when one was written.
    @MainActor
    private static func refresh(container: ModelContainer, force: Bool) async -> [String]? {
        guard !refreshing, AIService.isActive else { return nil }
        let context = ModelContext(container)
        var latest = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        latest.fetchLimit = 6
        let entries = (try? context.fetch(latest)) ?? []
        let total = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard total >= minEntries else { return nil }

        let defaults = UserDefaults.standard
        let age = (defaults.object(forKey: dateKey) as? Date).map { Date.now.timeIntervalSince($0) } ?? .infinity
        let style = QuestionPrefs.signature
        guard force || age > maxAge || defaults.integer(forKey: countKey) != total
                || (defaults.string(forKey: styleKey) ?? "") != style else { return nil }

        var notes = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        notes.fetchLimit = 3
        var chats = FetchDescriptor<ChatMessage>(predicate: #Predicate<ChatMessage> { !$0.fromAI },
                                                 sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        chats.fetchLimit = 3
        // Built in typed steps: one long `+` chain is too slow for the type checker.
        let noteRows: [Note] = (try? context.fetch(notes)) ?? []
        let chatRows: [ChatMessage] = (try? context.fetch(chats)) ?? []
        var texts: [String] = entries.reversed().map { $0.contextText() }
        texts += noteRows.reversed().map { $0.plainText() }
        texts += chatRows.reversed().map { $0.plainText() }
        if let hint = QuestionPrefs.aiHint { texts.append(hint) }

        refreshing = true
        defer { refreshing = false }
        guard let reply = try? await AIService.run(.openers(texts)) else { return nil }
        let openers = AIService.parseOpeners(reply)
        guard !openers.isEmpty, let sealed = try? EntryCipher.seal(openers.joined(separator: "\n")) else { return nil }
        defaults.set(sealed, forKey: cacheKey)
        defaults.set(Date.now, forKey: dateKey)
        defaults.set(total, forKey: countKey)
        defaults.set(style, forKey: styleKey)
        return openers
    }
}
