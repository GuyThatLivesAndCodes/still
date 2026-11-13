import Foundation
import SwiftData

/// Small chats about a note. Every message the person sends restarts a 3–5
/// minute pause; only one reply is ever waiting, written from the whole chat.
@MainActor
enum NoteChat {
    static let replyDelay: ClosedRange<TimeInterval> = 180...300
    static let maxLength = 1000

    /// noteID → when its waiting reply should appear, for retries after a failure.
    private static let pendingKey = "still.chat.pending"
    private static var jobs: [UUID: Int] = [:]
    private static var inFlight: Set<UUID> = []

    static func pendingReply(for note: UUID) -> Date? {
        (UserDefaults.standard.dictionary(forKey: pendingKey)?[note.uuidString] as? Double)
            .map(Date.init(timeIntervalSince1970:))
    }

    private static func setPending(_ date: Date?, for note: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: pendingKey) ?? [:]
        all[note.uuidString] = date?.timeIntervalSince1970
        UserDefaults.standard.set(all, forKey: pendingKey)
    }

    static func messages(for note: UUID, context: ModelContext) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.noteID == note },
            sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func send(_ raw: String, note: Note, context: ModelContext) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard !text.isEmpty, let sealed = try? EntryCipher.seal(text) else { return }
        let now = Date.now

        // Restart, don't stack: drop the reply that hasn't shown up yet.
        for message in messages(for: note.id, context: context) where message.fromAI && !message.isVisible(at: now) {
            context.delete(message)
        }
        Notifier.cancel([Notifier.chatID(note.id)])

        context.insert(ChatMessage(noteID: note.id, cipher: sealed, fromAI: false, createdAt: now))
        try? context.save()

        let replyAt = now.addingTimeInterval(.random(in: replyDelay))
        setPending(replyAt, for: note.id)
        Notifier.askOnce()
        let noteID = note.id
        let noteText = note.plainText()
        BackgroundWork.run("still.chat") {
            await prepareReply(noteID: noteID, noteText: noteText, replyAt: replyAt, context: context)
        }
    }

    private static func prepareReply(noteID: UUID, noteText: String, replyAt: Date, context: ModelContext) async {
        let mine = (jobs[noteID] ?? 0) + 1
        jobs[noteID] = mine
        inFlight.insert(noteID)
        defer { if jobs[noteID] == mine { inFlight.remove(noteID) } }
        let now = Date.now
        let turns = messages(for: noteID, context: context)
            .filter { $0.isVisible(at: now) }
            .map { ChatTurn(fromAI: $0.fromAI, text: $0.plainText()) }
        guard turns.last?.fromAI == false else { setPending(nil, for: noteID); return }

        guard let reply = try? await AIService.run(.chat(note: noteText, turns: turns)),
              let sealed = try? EntryCipher.seal(String(reply.prefix(1200))) else { return }
        // The person sent something else meanwhile; that newer job answers instead.
        guard jobs[noteID] == mine, pendingReply(for: noteID) == replyAt else { return }

        let deliver = max(replyAt, Date.now)
        context.insert(ChatMessage(noteID: noteID, cipher: sealed, fromAI: true,
                                   createdAt: deliver, visibleAt: deliver))
        try? context.save()
        setPending(nil, for: noteID)

        if deliver > Date.now.addingTimeInterval(5), Notifier.repliesEnabled {
            Notifier.schedule(id: Notifier.chatID(noteID), title: "still. replied",
                              body: "There's a reply waiting in your chat.",
                              at: deliver, route: "note:\(noteID.uuidString)")
        }
    }

    /// Retries replies that failed (offline, app closed mid-way) when the app opens.
    static func retryPending(context: ModelContext) async {
        guard AIService.isActive else { return }
        let all = UserDefaults.standard.dictionary(forKey: pendingKey) ?? [:]
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        for (key, value) in all {
            guard let id = UUID(uuidString: key), let t = value as? Double, !inFlight.contains(id) else { continue }
            guard let note = notes.first(where: { $0.id == id }) else { setPending(nil, for: id); continue }
            await prepareReply(noteID: id, noteText: note.plainText(),
                               replyAt: Date(timeIntervalSince1970: t), context: context)
        }
    }

    /// Removes a note and its chat.
    static func delete(_ note: Note, context: ModelContext) {
        messages(for: note.id, context: context).forEach { context.delete($0) }
        setPending(nil, for: note.id)
        Notifier.cancel([Notifier.chatID(note.id)])
        context.delete(note)
        try? context.save()
    }
}
