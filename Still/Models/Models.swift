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

    static let sealDays = 14
    static let deletionWait: TimeInterval = 6 * 3600

    init(cipher: Data, source: EntrySource, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sealedUntil = Entry.opensAt(for: createdAt)
        self.cipher = cipher
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .text }

    /// Entries open at the start (local midnight) of the 14th day after they were written.
    static func opensAt(for createdAt: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: createdAt)
        return cal.date(byAdding: .day, value: sealDays, to: day) ?? createdAt.addingTimeInterval(Double(sealDays) * 86400)
    }

    /// Always derived from the creation day, so older entries follow the same rule.
    var opensAt: Date { Entry.opensAt(for: createdAt) }

    func isReady(at now: Date = .now) -> Bool { now >= opensAt }

    var deletionConfirmableAt: Date? {
        deletionRequestedAt?.addingTimeInterval(Entry.deletionWait)
    }

    var isPendingDeletion: Bool { deletionRequestedAt != nil }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
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

    init(cipher: Data, entryCount: Int, createdAt: Date = .now) {
        self.id = UUID()
        self.cipher = cipher
        self.entryCount = entryCount
        self.createdAt = createdAt
    }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
    }
}
