import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case text
    case voice
    case watch
}

@Model
final class Entry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var sealedUntil: Date = Date()
    /// AES-GCM sealed box (combined representation). Plain text is never stored.
    var cipher: Data = Data()
    var sourceRaw: String = EntrySource.text.rawValue
    var deletionRequestedAt: Date?
    /// Encrypted voice recording (AAC), kept outside the database row.
    @Attribute(.externalStorage) var audioCipher: Data?
    var audioDuration: Double = 0
    /// Set when a token opens the entry early. From then on it behaves as if
    /// its open date has passed: it still reseals after each 60-second view.
    var revealedEarlyAt: Date?
    /// True once the early-reveal token for this entry was handed back (at its real open time).
    var tokenRefunded: Bool = false
    /// The prompt the person tapped to answer, sealed like the entry. Nil = free writing.
    var promptCipher: Data?

    static let sealDays = 5
    static let deletionWait: TimeInterval = 2 * 3600

    init(cipher: Data, source: EntrySource, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sealedUntil = Entry.opensAt(for: createdAt)
        self.cipher = cipher
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .text }

    /// Entries open at the start (local midnight) of the 5th day after they were written.
    static func opensAt(for createdAt: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: createdAt)
        return cal.date(byAdding: .day, value: sealDays, to: day) ?? createdAt.addingTimeInterval(Double(sealDays) * 86400)
    }

    /// Always derived from the creation day, so older entries follow the same rule.
    var opensAt: Date { Entry.opensAt(for: createdAt) }

    func isReady(at now: Date = .now) -> Bool { revealedEarlyAt != nil || now >= opensAt }

    var wasOpenedEarly: Bool { revealedEarlyAt != nil && Date.now < opensAt }

    var deletionConfirmableAt: Date? {
        deletionRequestedAt?.addingTimeInterval(Entry.deletionWait)
    }

    var isPendingDeletion: Bool { deletionRequestedAt != nil }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
    }

    /// The question this entry answers, if one was attached.
    func promptText() -> String? {
        promptCipher.flatMap { try? EntryCipher.open($0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Entry text with its question in front, for the AI and exports.
    func contextText() -> String {
        guard let q = promptText() else { return plainText() }
        return "Question: \(q)\nAnswer: \(plainText())"
    }

    var hasAudio: Bool { audioCipher != nil }

    func audioData() -> Data? {
        audioCipher.flatMap { try? EntryCipher.openData($0) }
    }
}

@Model
final class Note {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var cipher: Data = Data()
    var entryCount: Int = 1
    /// When the note becomes visible. Notes are written right away but held back
    /// for 10–30 minutes so they arrive like a reply. Nil = visible.
    var deliverAt: Date?
    /// First time the person opened it; unopened notes show a dot.
    var openedAt: Date?

    init(cipher: Data, entryCount: Int, createdAt: Date = .now) {
        self.id = UUID()
        self.cipher = cipher
        self.entryCount = entryCount
        self.createdAt = createdAt
    }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
    }

    func isVisible(at now: Date = .now) -> Bool { (deliverAt ?? .distantPast) <= now }

    /// The time the note actually arrived, for labels.
    var arrivedAt: Date { deliverAt ?? createdAt }
}

/// One message in a short chat about a note. Encrypted like everything else.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var noteID: UUID = UUID()
    var createdAt: Date = Date()
    var cipher: Data = Data()
    var fromAI: Bool = false
    /// AI replies are written right away but only show after a 3–5 minute pause.
    var visibleAt: Date = Date()

    init(noteID: UUID, cipher: Data, fromAI: Bool, createdAt: Date = .now, visibleAt: Date = .now) {
        self.id = UUID()
        self.noteID = noteID
        self.cipher = cipher
        self.fromAI = fromAI
        self.createdAt = createdAt
        self.visibleAt = visibleAt
    }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
    }

    func isVisible(at now: Date = .now) -> Bool { visibleAt <= now }
}
