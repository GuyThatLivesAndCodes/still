import SwiftUI
import SwiftData

struct NotesView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Notes")
                    .font(.system(size: 34, weight: .semibold))
                    .kerning(-1.2)
                    .foregroundStyle(Theme.ink)

                if !ReflectionQueue.isEnabled {
                    offState
                } else if notes.isEmpty {
                    emptyState
                } else {
                    if let latest = notes.first { featured(latest) }
                    if notes.count > 1 {
                        Text("Earlier").sectionLabel().padding(.top, 8)
                        ForEach(notes.dropFirst()) { note in
                            Text(note.plainText())
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .card(18)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func featured(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A note from still.")
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accent)
            Text(note.plainText())
                .font(.system(size: 19))
                .lineSpacing(5)
                .foregroundStyle(Theme.ink)
            Divider().overlay(Theme.hairline)
            Text(note.entryCount > 1 ? "For \(note.entryCount) entries · \(Fmt.entryLabel(note.createdAt))" : Fmt.entryLabel(note.createdAt))
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
        .padding(22)
        .glass(26)
    }

    private var offState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
            Text("Quiet AI is off")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Turn it on in You → Quiet AI to get a short, warm note 10 to 30 minutes after you seal an entry.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .padding(20)
        .card(22)
    }

    private var emptyState: some View {
        Text(ReflectionQueue.pendingIDs.isEmpty
             ? "Notes appear here a little while after you seal an entry."
             : "A note is on its way.")
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            .padding(.top, 8)
    }
}
