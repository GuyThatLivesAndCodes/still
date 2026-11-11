import SwiftUI

/// Recorded audio waiting to be sealed with the entry.
struct VoiceTake: Equatable {
    let url: URL
    let duration: TimeInterval
}

/// The small control under the composer: "Speak" → live recording bar → attached take.
struct VoiceControl: View {
    let recorder: VoiceRecorder
    let player: VoicePlayer
    let take: VoiceTake?
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if recorder.state != .idle {
                recordingBar
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let take {
                takeBar(take)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                speakButton
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(height: 44)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: recorder.state)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: take)
    }

    private var speakButton: some View {
        Button(action: onStart) {
            HStack(spacing: 7) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Speak")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .glass(18)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Record a voice entry")
    }

    private var recordingBar: some View {
        let finishing = recorder.state == .finishing
        return HStack(spacing: 12) {
            PulseDot(active: !finishing)
            Text(Self.time(recorder.elapsed))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(width: 40, alignment: .leading)
            LiveWaveform(levels: recorder.levels, dimmed: finishing)
                .frame(maxWidth: .infinity)
            if finishing {
                ProgressView()
                    .tint(Theme.secondary)
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("Finishing transcript")
            } else {
                Button(action: onStop) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 11, height: 11)
                        .frame(width: 32, height: 32)
                        .background(Theme.ink, in: Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Stop recording")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 44)
        .glass(22)
    }

    private func takeBar(_ take: VoiceTake) -> some View {
        HStack(spacing: 10) {
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Theme.ink, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")

            PlaybackBar(progress: player.progress)
                .frame(maxWidth: .infinity)
                .frame(height: 4)

            Text(Self.time(take.duration))
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Remove recording")
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .glass(22)
    }

    static func time(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Bars that follow the microphone level, newest on the right.
struct LiveWaveform: View {
    let levels: [CGFloat]
    var dimmed = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(dimmed ? Theme.tertiary : Theme.accent)
                    .frame(width: 3, height: 4 + levels[i] * 22)
            }
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}

struct PlaybackBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Theme.accent)
                    .frame(width: max(4, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PulseDot: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.35))
                .frame(width: 18, height: 18)
                .scaleEffect(pulse && active ? 1 : 0.4)
                .opacity(pulse && active ? 0 : 1)
            Circle().fill(active ? Color.red : Theme.tertiary)
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Quick press-down feedback for small controls.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
