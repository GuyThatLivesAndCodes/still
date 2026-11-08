import Foundation
import SwiftData

enum EntrySource: String, Codable {
    case text
    case voice
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

    static let sealDuration: TimeInterval = 14 * 24 * 3600
    static let deletionWait: TimeInterval = 6 * 3600

    init(cipher: Data, source: EntrySource, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.sealedUntil = createdAt.addingTimeInterval(Entry.sealDuration)
        self.cipher = cipher
        self.sourceRaw = source.rawValue
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .text }

    func isReady(at now: Date = .now) -> Bool { now >= sealedUntil }

    var deletionConfirmableAt: Date? {
        deletionRequestedAt?.addingTimeInterval(Entry.deletionWait)
    }

    var isPendingDeletion: Bool { deletionRequestedAt != nil }

    func plainText() -> String {
        (try? EntryCipher.open(cipher)) ?? ""
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
