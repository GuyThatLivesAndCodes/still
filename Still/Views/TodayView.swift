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
    @State private var handledWriteRequest = 0
    @State private var openers: [String] = []

    private var expanded: Bool { isEditing || !text.isEmpty }
    /// Openers show whenever the box isn't selected (hidden the moment it's tapped open).
    private var showOpener: Bool { !focused && !(isEditing && text.isEmpty) }
    private var canSeal: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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

                OpenerCarousel(openers: openers, active: showOpener, onTap: beginEditing)
                    .frame(height: showOpener ? 58 : 0)
                    .padding(.bottom, showOpener ? 20 : 0)
                    .opacity(showOpener ? 1 : 0)
                    .allowsHitTesting(showOpener)

                composer

                Text("Sealed for 14 days once you let it go.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 14)
                    .opacity(expanded ? 1 : 0)

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
            withAnimation(.easeOut(duration: 0.6)) { openers = loaded }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && text.isEmpty {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isEditing = false }
            }
        }
        .onChange(of: router.writeRequest) { _, _ in consumeWriteRequest() }
        .onAppear { consumeWriteRequest() }
        .sensoryFeedback(.success, trigger: sealCount)
        .fullScreenCover(item: $sealedEntry) { entry in
            SealedView(entry: entry)
        }
        .alert("Couldn't seal this entry", isPresented: Binding(
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
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .transition(.opacity)
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
        .frame(height: expanded ? 220 : 52)
        .glass(expanded ? 24 : 26)
        .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 30, y: 16)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
    }

    private func consumeWriteRequest() {
        guard router.writeRequest != handledWriteRequest else { return }
        handledWriteRequest = router.writeRequest
        beginEditing()
    }

    private func beginEditing() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isEditing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }

    private func seal() {
        guard canSeal else { return }
        do {
            let entry = try EntryWriter.seal(text, source: .text, context: context, streak: streak)
            focused = false
            text = ""
            isEditing = false
            sealCount += 1
            sealedEntry = entry
        } catch {
            errorMessage = "Your words are still here. Please try again."
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
