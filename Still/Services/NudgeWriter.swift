import Foundation
import SwiftData

/// Writes the daily reminder text with Quiet AI, from recent entries, notes and
/// chats. Lock-screen safe: the prompt rules out sensitive topics and a word
/// filter catches anything that slips through. Falls back to the preset line.
@MainActor
enum NudgeWriter {
    /// You → Reminders → "Written by Quiet AI". On unless turned off.
    static let enabledKey = "ai.nudges"
    private static let cacheKey = "ai.nudge.cipher"
    private static let dateKey = "ai.nudge.date"
    private static let maxAge: TimeInterval = 20 * 3600
    private static var refreshing = false

    nonisolated static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// The current AI line, if it's fresh and allowed.
    nonisolated static var current: String? {
        guard enabled, AIService.isActive,
              let date = UserDefaults.standard.object(forKey: dateKey) as? Date,
              Date.now.timeIntervalSince(date) < 36 * 3600,
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let text = try? EntryCipher.open(data) else { return nil }
        return text
    }

    /// Refreshes in the background when stale, then reschedules the reminder.
    static func refreshIfStale(context: ModelContext, onUpdate: @escaping @MainActor () -> Void) {
        guard enabled, AIService.isActive, !refreshing,
              UserDefaults.standard.bool(forKey: "remindersEnabled") else { return }
        let age = (UserDefaults.standard.object(forKey: dateKey) as? Date).map { Date.now.timeIntervalSince($0) } ?? .infinity
        guard age > maxAge else { return }

        var entries = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        entries.fetchLimit = 5
        var notes = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        notes.fetchLimit = 2
        var chats = FetchDescriptor<ChatMessage>(predicate: #Predicate<ChatMessage> { !$0.fromAI },
                                                 sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        chats.fetchLimit = 5
        let texts = ((try? context.fetch(entries)) ?? []).reversed().map { $0.contextText() }
            + ((try? context.fetch(notes)) ?? []).reversed().map { $0.plainText() }
            + ((try? context.fetch(chats)) ?? []).reversed().map { $0.plainText() }
        let input = texts.isEmpty ? ["(No writing yet.)"] : texts

        refreshing = true
        Task { @MainActor in
            defer { refreshing = false }
            guard let reply = try? await AIService.run(.nudge(input)),
                  let line = clean(reply),
                  let sealed = try? EntryCipher.seal(line) else { return }
            UserDefaults.standard.set(sealed, forKey: cacheKey)
            UserDefaults.standard.set(Date.now, forKey: dateKey)
            onUpdate()
        }
    }

    /// Words that should never be on a lock screen, whatever the model says.
    private static let blocked = [
        "suicid", "kill", "die", "death", "dead", "hurt", "harm", "self-harm", "cut", "pain", "sad",
        "depress", "anxi", "panic", "therap", "trauma", "grief", "griev", "funeral", "cancer", "sick",
        "ill", "hospital", "diagnos", "breakup", "break up", "divorce", "cheat", "ex ", "sex", "drunk",
        "drug", "debt", "money", "fired", "abuse", "lonely", "cry", "tears", "scared", "afraid", "hate"
    ]

    static func clean(_ raw: String) -> String? {
        var line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespaces)
        while let f = line.first, "\"“”'".contains(f) { line.removeFirst() }
        while let l = line.last, "\"“”'".contains(l) { line.removeLast() }
        guard line.count >= 10, line.count <= 110 else { return nil }
        let lower = " " + line.lowercased() + " "
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
        for term in blocked {
            if term.contains(" ") || term.count > 4 {
                if lower.contains(term) { return nil }
            } else if words.contains(where: { $0 == term || $0.hasPrefix(term) && term.count >= 4 }) {
                return nil
            }
        }
        return line
    }
}
