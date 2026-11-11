import SwiftUI
import SwiftData

struct VaultView: View {
    @Environment(TokenWallet.self) private var wallet
    @Environment(\.modelContext) private var context
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var revealing: Entry?
    @State private var deleting: Entry?
    @State private var earlyCandidate: Entry?
    @State private var deleteCandidate: Entry?
    @State private var noTokens: Entry?
    @State private var revealed = 0
    @State private var denied = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vault")
                            .font(.system(size: 34, weight: .semibold))
                            .kerning(-1.2)
                            .foregroundStyle(Theme.ink)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }

                    WeekStrip(entries: entries, now: ctx.date)

                    if entries.isEmpty {
                        emptyState
                    } else {
                        Text("Resting").sectionLabel().padding(.top, 4)
                        LazyVStack(spacing: 10) {
                            ForEach(entries) { entry in
                                Button { tap(entry, now: ctx.date) } label: {
                                    EntryCard(entry: entry, now: ctx.date)
                                }
                                .buttonStyle(PressableCardStyle())
                                .contextMenu { menu(for: entry, now: ctx.date) }
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                        removal: .opacity.combined(with: .scale(scale: 0.96))))
                            }
                        }
                        .animation(.snappy, value: entries.map(\.id))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: revealed)
        .sensoryFeedback(.warning, trigger: denied)
        .fullScreenCover(item: $revealing) { RevealView(entry: $0) }
        .alert("Still resting", isPresented: Binding(
            get: { noTokens != nil }, set: { if !$0 { noTokens = nil } }), presenting: noTokens) { _ in
            Button("OK", role: .cancel) {}
        } message: { entry in
            Text("It opens \(Fmt.longDate(entry.opensAt)). Early reveals refill next week.")
        }
        .sheet(item: $deleting) { DeleteView(entry: $0) }
        .alert("Open this entry early?", isPresented: Binding(
            get: { earlyCandidate != nil }, set: { if !$0 { earlyCandidate = nil } }),
            presenting: earlyCandidate) { entry in
            Button("Not Now", role: .cancel) {}
            Button("Open") {
                guard wallet.spend() else { return }
                entry.revealedEarlyAt = .now
                try? context.save()
                revealed += 1
                revealing = entry
            }
            .keyboardShortcut(.defaultAction)
        } message: { _ in
            Text("Uses 1 of your \(wallet.available()) early reveals this week. It stays open from now on.")
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                entry.deletionRequestedAt = .now
                deleting = entry
            }
        } message: { _ in
            Text("You'll confirm once more in 2 hours. You can change your mind until then.")
        }
    }

    private var subtitle: String {
        let n = entries.count
        let month = Date.now.formatted(.dateTime.month(.wide).year())
        return n == 1 ? "\(month) · 1 entry resting" : "\(month) · \(n) entries resting"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 26))
                .foregroundStyle(Theme.tertiary)
            Text("Nothing resting yet.")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("What you seal on Today appears here, out of reach for 14 days.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func tap(_ entry: Entry, now: Date) {
        if entry.isPendingDeletion { deleting = entry }
        else if entry.isReady(at: now) { revealing = entry }
        else if wallet.available(at: now) > 0 { earlyCandidate = entry }
        else { denied += 1; noTokens = entry }
    }

    @ViewBuilder
    private func menu(for entry: Entry, now: Date) -> some View {
        if entry.isPendingDeletion {
            Button("View deletion", systemImage: "clock") { deleting = entry }
            Button("Cancel deletion", systemImage: "arrow.uturn.backward") { entry.deletionRequestedAt = nil }
        } else {
            if entry.isReady(at: now) {
                Button("Reveal for 60 seconds", systemImage: "eye") { revealing = entry }
            } else if wallet.available(at: now) > 0 {
                Button("Reveal early · 1 token", systemImage: "eye") { earlyCandidate = entry }
            }
            Button("Delete…", systemImage: "trash", role: .destructive) { deleteCandidate = entry }
        }
    }
}

private struct WeekStrip: View {
    let entries: [Entry]
    let now: Date

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - 6, to: today) }
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                let has = entries.contains { cal.isDate($0.createdAt, inSameDayAs: day) }
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.7)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 16, weight: .semibold))
                    Circle()
                        .fill(has ? (isToday ? Color.black : Theme.accent) : .clear)
                        .frame(width: 5, height: 5)
                }
                .foregroundStyle(isToday ? Color.black : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(isToday ? Theme.ink : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (has ? ", has an entry" : ""))
            }
        }
        .padding(8)
        .card(20)
    }
}

private struct EntryCard: View {
    let entry: Entry
    let now: Date

    private var ready: Bool { entry.isReady(at: now) && !entry.isPendingDeletion }

    private var placeholder: String {
        // AES-GCM adds 28 bytes (nonce + tag) to the plaintext.
        let length = min(140, max(24, entry.cipher.count - 28))
        let words = ["quiet", "today", "felt", "the", "and", "morning", "something", "I", "was", "light", "still", "about"]
        var out = ""
        var i = Int(entry.id.uuid.0)
        while out.count < length { out += words[i % words.count] + " "; i += 7 }
        return String(out.prefix(length))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Fmt.entryLabel(entry.createdAt))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                status
            }
            // Never decrypt for the list: the preview is blurred anyway, so a
            // placeholder of similar length looks the same and keeps scrolling smooth.
            Text(placeholder)
                .font(.system(size: 15))
                .lineLimit(2)
                .foregroundStyle(ready ? Color(white: 0.25) : Theme.secondary)
                .blur(radius: 7)
                .privacySensitive()
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
        }
        .foregroundStyle(ready ? Color.black : Theme.ink)
        .padding(16)
        .background {
            if ready {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.ink)
            }
        }
        .modifier(ConditionalCard(enabled: !ready))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let confirmAt = entry.deletionConfirmableAt {
            Text(confirmAt > now ? "Deleting · \(Fmt.hm(confirmAt.timeIntervalSince(now)))" : "Ready to delete")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        } else if ready {
            Text("READY")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black, in: Capsule())
                .foregroundStyle(Theme.ink)
        } else {
            Label("Opens \(Fmt.shortDate(entry.opensAt))", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private var footer: some View {
        if ready {
            HStack {
                Label("Reveal for 60 seconds", systemImage: "clock")
                    .font(.footnote.weight(.semibold))
                Spacer()
                if entry.wasOpenedEarly {
                    Text("Opened early")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.35))
                }
            }
        } else if entry.source == .voice {
            Label("Voice entry", systemImage: "waveform")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        } else if entry.source == .watch {
            Label("Written on Apple Watch", systemImage: "applewatch")
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
    }
}

/// Gives list cards the same quick press response as the app's buttons.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ConditionalCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.card(22) } else { content }
    }
}
