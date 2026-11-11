import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(StreakStore.self) private var streak
    @Environment(AppRouter.self) private var router

    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool
    @State private var sealedEntry: Entry?
    @State private var sealCount = 0
    @State private var errorMessage: String?
    @State private var openers: [String] = []
    @State private var aiOpeners: Set<String> = []
    @State private var alertTitle = "Couldn't seal this entry"
    @Environment(\.scenePhase) private var scenePhase

    // Voice entries
    @State private var recorder = VoiceRecorder()
    @State private var player = VoicePlayer()
    @State private var take: VoiceTake?
    @State private var textBeforeVoice = ""
    @State private var textAfterVoice = ""
    @State private var noTranscript = false

    private var recording: Bool { recorder.state != .idle }
    private var expanded: Bool { isEditing || !text.isEmpty || recording || take != nil }
    /// Openers show whenever the box isn't selected (hidden the moment it's tapped open).
    private var showOpener: Bool { !focused && !recording && !(isEditing && text.isEmpty) }
    private var canSeal: Bool {
        !recording && (take != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focused = false }

            VStack(spacing: 0) {
                StreakCountdown()
                    .frame(height: 44)
                    .padding(.top, 6)

                Spacer(minLength: 24)

                OpenerCarousel(openers: openers, aiOpeners: aiOpeners, active: showOpener, onTap: beginEditing)
                    .frame(height: showOpener ? 58 : 0)
                    .padding(.bottom, showOpener ? 20 : 0)
                    .opacity(showOpener ? 1 : 0)
                    .allowsHitTesting(showOpener)

                composer
                    .layoutPriority(1)

                VoiceControl(recorder: recorder, player: player, take: take,
                             onStart: startRecording, onStop: stopRecording, onRemove: removeTake)
                    .padding(.top, 12)

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .padding(.top, 10)
                    .opacity(expanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: footnote)

                Spacer(minLength: 24)

                Button(action: seal) {
                    Label("Seal", systemImage: "lock")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: canSeal))
                .disabled(!canSeal)
                .animation(.easeInOut(duration: 0.25), value: canSeal)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showOpener)
        }
        .task {
            guard openers.isEmpty else { return }
            let loaded = await OpenerFeed.load()
            withAnimation(.easeOut(duration: 0.6)) {
                openers = loaded.openers
                aiOpeners = loaded.ai
            }
        }
        .onChange(of: recorder.transcript) { _, spoken in
            guard recording, !spoken.isEmpty else { return }
            text = textBeforeVoice.isEmpty ? spoken : textBeforeVoice + "\n\n" + spoken
        }
        .onChange(of: recorder.state) { old, new in
            if old == .finishing && new == .idle { finishTake() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && recorder.isRecording { stopRecording() }
        }
        .onDisappear {
            if recorder.isRecording { stopRecording() }
            player.stop()
        }
        .sensoryFeedback(.start, trigger: recorder.isRecording) { _, now in now }
        .sensoryFeedback(.stop, trigger: recorder.isRecording) { was, now in was && !now }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && text.isEmpty && !recording && take == nil {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isEditing = false }
            }
        }
        .onChange(of: router.writeRequest) { _, _ in consumeWriteRequest() }
        .onAppear { consumeWriteRequest() }
        .sensoryFeedback(.success, trigger: sealCount)
        .fullScreenCover(item: $sealedEntry) { entry in
            SealedView(entry: entry)
        }
        .alert(alertTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // Small glass pill until tapped; grows into a writing surface.
    private var composer: some View {
        ZStack(alignment: .topLeading) {
            if expanded {
                TextEditor(text: $text)
                    .focused($focused)
                    .disabled(recording)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .transition(.opacity)
                if recording && text.isEmpty {
                    Text(recorder.transcribing ? "Listening…" : "Recording…")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 19)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            } else {
                Button(action: beginEditing) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 15, weight: .medium))
                        Text("Write")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: expanded ? .infinity : 270)
        // Shrinks (down to 120) on short screens when the keyboard is up, so the
        // voice control and Seal button never get pushed under it.
        .frame(minHeight: expanded ? 120 : 52, maxHeight: expanded ? 220 : 52)
        .glass(expanded ? 24 : 26)
        .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 30, y: 16)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
    }

    private func consumeWriteRequest() {
        guard router.writeRequest != router.handledWriteRequest else { return }
        router.handledWriteRequest = router.writeRequest
        beginEditing()
    }

    private func beginEditing() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isEditing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }

    private var footnote: String {
        if recorder.isRecording {
            let left = VoiceRecorder.maxDuration - recorder.elapsed
            if left <= 30 { return "Stops in \(Int(left.rounded(.up)))s." }
            return recorder.transcribing ? "Transcribing on this iPhone. Nothing leaves it."
                                         : "Recording audio only. Transcription isn't available here."
        }
        if noTranscript && take != nil { return "No transcript this time. Your recording is kept." }
        return "Sealed for 14 days once you let it go."
    }

    private func startRecording() {
        player.stop()
        Task { @MainActor in
            let granted = await VoiceRecorder.requestPermissions()
            guard granted.mic else {
                show("Microphone is off", VoiceRecorder.RecorderError.micDenied.localizedDescription)
                return
            }
            focused = false
            textBeforeVoice = text.trimmingCharacters(in: .whitespacesAndNewlines)
            noTranscript = false
            do {
                try recorder.start(transcribe: granted.speech)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isEditing = true }
            } catch {
                show("Couldn't record", error.localizedDescription)
            }
        }
    }

    private func stopRecording() { recorder.stop() }

    private func finishTake() {
        guard let url = recorder.recordingURL, recorder.elapsed >= 0.5 else {
            recorder.discard()
            return
        }
        player.load(url)
        textAfterVoice = text
        noTranscript = recorder.transcript.isEmpty
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            take = VoiceTake(url: url, duration: player.duration > 0 ? player.duration : recorder.elapsed)
        }
    }

    private func removeTake() {
        player.stop()
        recorder.discard()
        // Drop the transcript too, unless it was edited by hand.
        if text == textAfterVoice { text = textBeforeVoice }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { take = nil }
        noTranscript = false
    }

    private func show(_ title: String, _ message: String) {
        alertTitle = title
        errorMessage = message
    }

    private func seal() {
        guard canSeal else { return }
        do {
            let audio = take.flatMap { try? Data(contentsOf: $0.url) }
            if take != nil && audio == nil {
                show("Couldn't seal this entry", "The recording couldn't be read. Please try again.")
                return
            }
            let entry = try EntryWriter.seal(text, source: take != nil ? .voice : .text,
                                             audio: audio, audioDuration: take?.duration ?? 0,
                                             context: context, streak: streak)
            player.stop()
            recorder.discard()
            take = nil
            focused = false
            text = ""
            isEditing = false
            sealCount += 1
            sealedEntry = entry
        } catch {
            show("Couldn't seal this entry", "Your words are still here. Please try again.")
        }
    }
}

/// Small countdown shown only when a running streak has under 12 hours left.
struct StreakCountdown: View {
    @Environment(StreakStore.self) private var streak
    @AppStorage("streakVisible") private var visible = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if visible, let left = streak.remaining(at: ctx.date), left < 12 * 3600 {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(Fmt.clock(left))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.ink)
                    Text("left on streak")
                        .foregroundStyle(Theme.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct SealedView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @State private var breathe = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1)
                        .frame(width: 200, height: 200)
                        .scaleEffect(breathe ? 1.06 : 1)
                        .opacity(breathe ? 0.6 : 0.3)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 156, height: 156)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 104, height: 104)
                    Image(systemName: "lock")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.black)
                }
                .accessibilityHidden(true)
                .padding(.bottom, 40)

                Text("Sealed.")
                    .font(.system(size: 40, weight: .semibold))
                    .kerning(-1.5)
                    .foregroundStyle(Theme.ink)
                Text("This entry opens on\n\(Fmt.longDate(entry.opensAt)).")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 12)
                Spacer()
                Button("Let it go") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
