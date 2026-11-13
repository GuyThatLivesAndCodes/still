import SwiftUI

/// You → Quiet AI. Shows what this iPhone supports and lets the user pick
/// Automatic, on-device only, Cloudflare only, or off.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AIService.modeKey) private var modeRaw = AIMode.automatic.rawValue
    @AppStorage(AIService.consentKey) private var cloudConsent = false
    @State private var askConsent = false
    @State private var pendingMode: AIMode?
    /// Bumped to re-read engine availability (the Apple model can finish downloading while open).
    @State private var refresh = 0

    private var mode: AIMode { AIMode(rawValue: modeRaw) ?? .automatic }

    var body: some View {
        let _ = refresh
        let onDevice = AIService.onDeviceStatus
        let cloud = AIService.cloudStatus
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nowUsing

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where it runs").sectionLabel().padding(.horizontal, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(AIMode.allCases.enumerated()), id: \.element) { i, option in
                                if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                                modeRow(option, status: status(for: option, onDevice: onDevice, cloud: cloud))
                            }
                        }
                        .card(22)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cloudflare").sectionLabel().padding(.horizontal, 6)
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: Binding(get: { cloudConsent }, set: setConsent)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow Cloudflare").font(.body.weight(.medium))
                                    Text(CloudModel.endpoint == nil
                                         ? "Not set up in this build"
                                         : "Off unless you turn it on")
                                        .font(.footnote).foregroundStyle(Theme.tertiary)
                                }
                            }
                            .tint(Theme.accent)
                            .disabled(CloudModel.endpoint == nil)
                            Text("When it's used, only the text needed for that note or prompt is sent over HTTPS to a still. server on Cloudflare. It's answered and immediately discarded: no account, no logs, no storage, and it's never used for training or ads.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .card(22)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What it does").sectionLabel().padding(.horizontal, 6)
                        VStack(alignment: .leading, spacing: 16) {
                            feature("text.bubble", "A short, warm note",
                                    "10 to 30 minutes after you seal an entry. It listens rather than fixes.")
                            feature("bubble.left.and.bubble.right", "Talk it through",
                                    "Tap a note to reply. still. answers 3 to 5 minutes after your last message, so it feels like a letter, not a chat app.")
                            feature("text.quote", "Openers just for you",
                                    "After a few entries, some prompts above the box come from your own writing. Hold one to shuffle (once every 30 seconds), and pick the mix in You → Questions.")
                            feature("bell", "Reminders in its own words",
                                    "Your daily reminder can be written fresh each day. It never mentions anything sensitive. Turn it off in You → Notifications.")
                            feature("person", "Fits you",
                                    "If you add your name, age or gender in You → About you, it shapes how still. talks to you.")
                        }
                        .padding(18)
                        .card(22)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Quiet AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Allow Cloudflare?", isPresented: $askConsent) {
                Button("Not now", role: .cancel) { pendingMode = nil }
                Button("Allow") {
                    cloudConsent = true
                    if let next = pendingMode { modeRaw = next.rawValue }
                    pendingMode = nil
                }
            } message: {
                Text("The text needed for each note or prompt will be sent to a still. server on Cloudflare, answered, and discarded. Nothing is stored or logged. You can turn this off any time.")
            }
        }
        .presentationBackground(.black)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
        .task {
            // Light polling while the sheet is open, in case the model finishes downloading.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                refresh += 1
            }
        }
    }

    // MARK: Pieces

    private var nowUsing: some View {
        let engine = AIService.activeEngine
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(engine == nil ? Color.white.opacity(0.08) : Theme.accent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon(for: engine))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(engine == nil ? Theme.tertiary : Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Now using").sectionLabel()
                Text(engine?.title ?? "Nothing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.opacity)
                Text(nowUsingDetail(engine))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glass(24)
        .animation(.easeInOut(duration: 0.25), value: engine)
    }

    private func modeRow(_ option: AIMode, status: EngineStatus?) -> some View {
        let selected = option == mode
        let blocked: Bool = {
            if case .unavailable = status { return true }
            return false
        }()
        return Button { choose(option, status: status) } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.accent : Color.white.opacity(0.25), lineWidth: 1.5)
                    if selected { Circle().fill(Theme.accent).padding(5) }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.body.weight(selected ? .semibold : .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        if let status { pill(status) }
                    }
                    Text(option.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(blocked && !selected ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    private func pill(_ status: EngineStatus) -> some View {
        let ready = status.isReady
        return HStack(spacing: 5) {
            Circle()
                .fill(ready ? Color.green.opacity(0.85) : status == .needsConsent ? Theme.accent : Color.white.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(ready ? Theme.ink : Theme.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .fixedSize()
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Logic

    private func status(for option: AIMode, onDevice: EngineStatus, cloud: EngineStatus) -> EngineStatus? {
        switch option {
        case .onDevice: return onDevice
        case .cloud: return cloud
        case .automatic, .off: return nil
        }
    }

    private func choose(_ option: AIMode, status: EngineStatus?) {
        if status == .needsConsent {
            pendingMode = option
            askConsent = true
            return
        }
        modeRaw = option.rawValue
    }

    private func setConsent(_ on: Bool) {
        if on {
            pendingMode = nil
            askConsent = true
        } else {
            cloudConsent = false
            if mode == .cloud { modeRaw = AIMode.automatic.rawValue }
        }
    }

    private func icon(for engine: AIEngine?) -> String {
        switch engine {
        case .onDevice: return "iphone"
        case .cloud: return "cloud"
        case nil: return "moon.zzz"
        }
    }

    private func nowUsingDetail(_ engine: AIEngine?) -> String {
        switch engine {
        case .onDevice: return "Everything stays on this iPhone."
        case .cloud: return "Text is sent to Cloudflare, answered, and discarded."
        case nil:
            switch mode {
            case .off: return "Quiet AI is off."
            case .onDevice:
                return AIService.onDeviceStatus == .unavailable("Off in Settings")
                    ? "Turn on Apple Intelligence in Settings to use Apple's model."
                    : "This iPhone can't run Apple's model right now."
            case .cloud: return "Cloudflare isn't available right now."
            case .automatic: return "Neither option is available. Allow Cloudflare to use it on this iPhone."
            }
        }
    }
}
