import SwiftUI
import SwiftData
import UserNotifications

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @State private var opened: Note?
    @State private var deleteCandidate: Note?
    /// Bumped by pull-to-refresh so the list and ETA re-read right away.
    @State private var refreshedAt = Date.distantPast
    @State private var refreshes = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let now = max(ctx.date, refreshedAt)
            let visible = notes.filter { $0.isVisible(at: now) }
            let waiting = notes.count > visible.count || !ReflectionQueue.pendingIDs.isEmpty
            let eta = arrival(now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.system(size: 34, weight: .semibold))
                            .kerning(-1.2)
                            .foregroundStyle(Theme.ink)
                        Text(subtitle(visible))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }

                    if !ReflectionQueue.isEnabled {
                        offState
                    } else {
                        if waiting { onItsWay(eta: eta, now: now) }
                        if visible.isEmpty && !waiting {
                            emptyState
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visible) { note in
                                    Button { open(note) } label: {
                                        NoteCard(note: note, replies: replyCount(note, now: now),
                                                 waitingReply: NoteChat.pendingReply(for: note.id) != nil)
                                    }
                                    .buttonStyle(NotePressStyle())
                                    .contextMenu {
                                        Button("Open", systemImage: "text.bubble") { open(note) }
                                        Button("Delete Note", systemImage: "trash", role: .destructive) {
                                            deleteCandidate = note
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .animation(.snappy, value: visible.map(\.id))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: refreshes)
        .sheet(item: $opened) { NoteChatView(note: $0) }
        .alert("Delete this note?", isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            presenting: deleteCandidate) { note in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                withAnimation(.snappy) { NoteChat.delete(note, context: context) }
            }
        } message: { _ in
            Text("The note and its chat will be erased. Your entries aren't affected.")
        }
        .onAppear(perform: consumeRequest)
        .onChange(of: router.noteRequest) { _, _ in consumeRequest() }
    }

    private func subtitle(_ visible: [Note]) -> String {
        let unread = visible.filter { $0.openedAt == nil }.count
        let count = visible.count == 1 ? "1 note" : "\(visible.count) notes"
        return unread > 0 ? "\(count) · \(unread) new" : count
    }

    private func replyCount(_ note: Note, now: Date) -> Int {
        messages.filter { $0.noteID == note.id && $0.isVisible(at: now) }.count
    }

    private func open(_ note: Note) {
        opened = note
    }

    private func consumeRequest() {
        guard let id = router.noteRequest else { return }
        router.noteRequest = nil
        if let note = notes.first(where: { $0.id == id }), note.isVisible() { opened = note }
    }

    /// When the next note lands: a written note's delivery time, else the batch timer.
    private func arrival(now: Date) -> Date? {
        let held = notes.filter { !$0.isVisible(at: now) }.compactMap(\.deliverAt).min()
        if let held { return held }
        return ReflectionQueue.pendingIDs.isEmpty ? nil : ReflectionQueue.fireAt
    }

    /// Pull to refresh: deliver anything due, retry chats, and re-read the clock.
    private func refresh() async {
        let started = Date.now
        await ReflectionQueue.deliverIfDue(context: context)
        await NoteChat.retryPending(context: context)
        // Long enough for the spinner to read as a real check.
        let wait = 0.6 - Date.now.timeIntervalSince(started)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        refreshedAt = .now
        refreshes += 1
    }

    /// "About 12 min", or "Coming in soon" once under ~3 minutes (or overdue).
    static func etaText(_ eta: Date?, now: Date) -> (title: String, detail: String) {
        guard let eta else {
            return ("A note is on its way", "still. is reading what you sealed. You'll get a notification when it's here.")
        }
        let left = eta.timeIntervalSince(now)
        if left <= 180 {
            return ("Coming in soon", "Almost here. Pull down to check, or wait for the notification.")
        }
        let minutes = Int((left / 60).rounded(.up))
        let time = eta.formatted(date: .omitted, time: .shortened)
        let span = minutes >= 60 ? "about \(minutes / 60)h \(minutes % 60)m" : "about \(minutes) min"
        return ("Next note in \(span)", "Expected around \(time). You'll get a notification when it's here.")
    }

    private func onItsWay(eta: Date?, now: Date) -> some View {
        let copy = Self.etaText(eta, now: now)
        return HStack(spacing: 14) {
            Image(systemName: "ellipsis.bubble")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.ai)
                .symbolEffect(.pulse, options: .repeating)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: copy.title)
                Text(copy.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(20)
        .accessibilityElement(children: .combine)
    }

    private var offState: some View {
        ContentUnavailableView {
            Label("Quiet AI is off", systemImage: "sparkles")
        } description: {
            Text("Turn it on in You → Quiet AI to get a short, warm note 10 to 30 minutes after you seal an entry.")
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "text.bubble")
        } description: {
            Text("A little while after you seal an entry, still. leaves a note here. Tap one to read it and talk it through.")
        }
        .foregroundStyle(Theme.ink)
        .padding(.top, 40)
    }
}

/// A note in the list: covered in ink until opened, like entries in the vault.
private struct NoteCard: View {
    let note: Note
    let replies: Int
    let waitingReply: Bool

    private var placeholder: String {
        let length = min(150, max(40, note.cipher.count - 28))
        let words = ["it", "sounds", "like", "you", "were", "carrying", "a", "lot", "and", "still", "found", "room"]
        var out = ""
        var i = Int(note.id.uuid.1)
        while out.count < length { out += words[i % words.count] + " "; i += 5 }
        return String(out.prefix(length))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if note.openedAt == nil {
                    Circle().fill(Theme.ai).frame(width: 8, height: 8)
                        .accessibilityLabel("New")
                }
                Text(Fmt.exact(note.arrivedAt))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if waitingReply {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ai)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityLabel("Reply on its way")
                }
                if replies > 0 {
                    Label("\(replies)", systemImage: "bubble.left.and.bubble.right")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("\(replies) messages")
                }
            }
            Text(placeholder)
                .font(.system(size: 16))
                .lineLimit(3)
                .foregroundStyle(Theme.ai.opacity(0.8))
                .invisibleInk(true, tint: Theme.ai)
                .privacySensitive()
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Label(note.entryCount > 1 ? "For \(note.entryCount) entries" : "Tap to read and reply",
                      systemImage: note.entryCount > 1 ? "square.stack" : "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(16)
        .card(22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the note and a chat about it")
    }
}

private struct NotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A note opened in full, with a small chat underneath. Replies take 3–5
/// minutes, and each new message restarts the wait.
struct NoteChatView: View {
    let note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var messages: [ChatMessage]
    @State private var draft = ""
    @State private var noteText = ""
    @State private var sent = 0
    @State private var noteHidden = true
    @State private var noteOrigin: CGPoint?
    @FocusState private var typing: Bool

    init(note: Note) {
        self.note = note
        let id = note.id
        _messages = Query(filter: #Predicate<ChatMessage> { $0.noteID == id }, sort: \.createdAt)
    }

    private var canSend: Bool {
        AIService.isActive && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 5)) { ctx in
                let shown = messages.filter { $0.isVisible(at: ctx.date) }
                let pending = NoteChat.pendingReply(for: note.id)
                    ?? messages.first(where: { $0.fromAI && !$0.isVisible(at: ctx.date) })?.visibleAt
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            noteCard
                                .padding(.bottom, 10)

                            if shown.isEmpty && pending == nil {
                                Text("Want to say more? Reply below and still. will answer in a few minutes.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            ForEach(shown) { message in
                                Bubble(text: message.plainText(), fromAI: message.fromAI, time: message.visibleAt)
                                    .id(message.id)
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                            removal: .opacity))
                            }

                            if let pending {
                                Thinking(replyAt: pending, now: ctx.date)
                                    .id("thinking")
                                    .transition(.opacity)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .animation(.snappy, value: shown.map(\.id))
                        .animation(.easeInOut(duration: 0.25), value: pending)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: shown.count) { _, _ in
                        withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: typing) { _, isTyping in
                        guard isTyping else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.black)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .light), trigger: sent)
        .onAppear {
            noteText = note.plainText()
            if note.openedAt == nil {
                note.openedAt = .now
                try? context.save()
            }
            Notifier.openChat = note.id
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [Notifier.chatID(note.id), Notifier.noteID])
        }
        .onDisappear { if Notifier.openChat == note.id { Notifier.openChat = nil } }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A note from still.", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.ai)
            Text(noteText)
                .font(.system(size: 19))
                .lineSpacing(5)
                .foregroundStyle(Theme.ai)
                .privacySensitive()
                .frame(maxWidth: .infinity, alignment: .leading)
                .invisibleInk(noteHidden, tint: Theme.ai, origin: noteOrigin)
                .inkReveal(hidden: $noteHidden, origin: $noteOrigin)
                .accessibilityLabel(noteHidden ? "Hidden note" : noteText)
            Divider().overlay(Theme.hairline)
            Text(note.entryCount > 1
                 ? "\(Fmt.exact(note.arrivedAt)) · for \(note.entryCount) entries"
                 : Fmt.exact(note.arrivedAt))
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
        }
        .padding(20)
        .glass(24)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if !AIService.isActive {
                Text("Turn on Quiet AI in You to reply.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Reply to still.", text: $draft, axis: .vertical)
                    .focused($typing)
                    .lineLimit(1...5)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .disabled(!AIService.isActive)
                    .onChange(of: draft) { _, value in
                        if value.count > NoteChat.maxLength { draft = String(value.prefix(NoteChat.maxLength)) }
                    }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend ? Color.black : Theme.tertiary)
                        .frame(width: 34, height: 34)
                        .background(canSend ? Theme.ink : Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canSend)
                .padding(.trailing, 5)
                .padding(.bottom, 5)
                .accessibilityLabel("Send")
                .animation(.easeOut(duration: 0.15), value: canSend)
            }
            .glass(22)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
    }

    private func send() {
        guard canSend else { return }
        NoteChat.send(draft, note: note, context: context)
        draft = ""
        sent += 1
    }
}

/// One chat message, covered in ink: tap to show, tap again (or wait a minute) to hide.
private struct Bubble: View {
    let text: String
    let fromAI: Bool
    let time: Date
    @State private var hidden = true
    @State private var origin: CGPoint?

    var body: some View {
        HStack {
            if !fromAI { Spacer(minLength: 48) }
            VStack(alignment: fromAI ? .leading : .trailing, spacing: 4) {
                Text(text)
                    .font(.system(size: 17))
                    .lineSpacing(2)
                    .foregroundStyle(fromAI ? Theme.ai : Color.black)
                    .invisibleInk(hidden, tint: fromAI ? Theme.ai : Color.black, origin: origin)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(fromAI ? Theme.card : Theme.ink,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        if fromAI {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                    }
                    .privacySensitive()
                    .inkReveal(hidden: $hidden, origin: $origin, inset: CGSize(width: 14, height: 10))
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 6)
            }
            if fromAI { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((fromAI ? "still.: " : "You: ") + (hidden ? "hidden message" : text))
    }
}

/// Shown while a reply is waiting out its 3–5 minute pause.
private struct Thinking: View {
    let replyAt: Date
    let now: Date

    private var label: String {
        let minutes = Int((replyAt.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 1 { return "Replying in a moment" }
        return "Replying in about \(minutes) minutes"
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.ai.opacity(0.8)).frame(width: 6, height: 6)
                        .phaseAnimator([0.3, 1.0]) { dot, phase in
                            dot.opacity(phase)
                        } animation: { _ in .easeInOut(duration: 0.6).delay(Double(i) * 0.2) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
                .contentTransition(.numericText())
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("still. is thinking. \(label).")
    }
}
