import Foundation
import SwiftData
import WidgetKit
import Observation
import AppIntents

/// Single path for sealing an entry, used by Today and by Apple Watch.
@MainActor
enum EntryWriter {
    @discardableResult
    static func seal(_ text: String, source: EntrySource, createdAt: Date = .now,
                     audio: Data? = nil, audioDuration: TimeInterval = 0,
                     context: ModelContext, streak: StreakStore) throws -> Entry {
        let entry = Entry(cipher: try EntryCipher.seal(text), source: source, createdAt: createdAt)
        if let audio {
            entry.audioCipher = try EntryCipher.seal(data: audio)
            entry.audioDuration = audioDuration
        }
        context.insert(entry)
        try context.save()
        streak.recordEntry(at: createdAt)
        ReflectionQueue.enqueue(entry.id)
        syncSurroundings(context: context, streak: streak)
        return entry
    }

    /// Updates reminders, widgets and the watch after anything streak-related changes.
    static func syncSurroundings(context: ModelContext, streak: StreakStore) {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 30
        let dates = ((try? context.fetch(descriptor)) ?? []).map(\.createdAt)
        let defaults = UserDefaults.standard
        ReminderService.reschedule(entryDates: dates, streak: streak,
                                   enabled: defaults.bool(forKey: "remindersEnabled"))
        let visible = defaults.object(forKey: "streakVisible") as? Bool ?? true
        let snapshot = WidgetSnapshot(days: streak.days, deadline: streak.deadline,
                                      paused: streak.isPaused, streakVisible: visible,
                                      lastEntry: dates.first)
        WidgetShared.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneLink.shared.push(snapshot)
    }
}

/// Cross-screen requests, e.g. "open a blank entry" from a widget or Siri.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var writeRequest = 0

    func requestWrite() { writeRequest += 1 }

    func handle(_ url: URL) {
        if url.scheme == "still", url.host == "write" { requestWrite() }
    }
}

/// Siri, Spotlight, Shortcuts and the Action Button: "Write in still."
struct WriteEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Write in still."
    static let description = IntentDescription("Open still. to a blank entry.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestWrite()
        return .result()
    }
}

struct StillShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WriteEntryIntent(),
                    phrases: ["Write in \(.applicationName)",
                              "New \(.applicationName) entry",
                              "Journal in \(.applicationName)"],
                    shortTitle: "Write",
                    systemImageName: "pencil.line")
    }
}
