import SwiftUI

/// Gray line above the composer that slowly cycles through openers.
/// Fades to the next one every 15 seconds; swipe left for next, right for previous.
struct OpenerCarousel: View {
    let openers: [String]
    /// When false the carousel is hidden and its timer stops.
    let active: Bool
    var onTap: () -> Void = {}

    static let interval: Duration = .seconds(15)

    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var shown = true
    @State private var swap: Task<Void, Never>?
    @State private var target: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: String {
        openers.isEmpty ? "" : openers[index % openers.count]
    }

    private var textBlur: CGFloat { shown || reduceMotion ? 0 : 6 }

    private var textOpacity: Double {
        guard shown else { return 0 }
        return 1 - min(Double(abs(drag)) / 160, 0.6)
    }

    var body: some View {
        Text(verbatim: current)
            .font(.system(size: 19, weight: .regular))
            .foregroundStyle(Theme.tertiary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .blur(radius: textBlur)
            .opacity(textOpacity)
            .offset(x: drag)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(swipe)
        .onTapGesture { onTap() }
        .task(id: TimerKey(index: index, active: active, count: openers.count)) {
            guard active, openers.count > 1 else { return }
            try? await Task.sleep(for: Self.interval)
            guard !Task.isCancelled else { return }
            step(1, fade: 0.9)
        }
        .onChange(of: openers) { _, _ in index = 0 }
        .onDisappear { swap?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current)
        .accessibilityHint("Swipe up or down for another prompt. Double-tap to start writing.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(.default) { onTap() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Follow the finger with resistance so it feels attached, not loose.
                drag = value.translation.width * 0.45
            }
            .onEnded { value in
                let dx = value.translation.width
                let flick = value.predictedEndTranslation.width
                let goNext = dx < -50 || flick < -140
                let goBack = dx > 50 || flick > 140
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                if goNext { step(1) } else if goBack { step(-1) }
            }
    }

    /// Fade out, swap the line, fade back in, so two lines never overlap.
    private func step(_ delta: Int, fade: Double = 0.22) {
        guard openers.count > 1 else { return }
        swap?.cancel()
        // Quick repeated swipes accumulate instead of being dropped.
        let next = ((target ?? index) + delta + openers.count) % openers.count
        target = next
        withAnimation(.easeIn(duration: fade)) { shown = false }
        swap = Task { @MainActor in
            try? await Task.sleep(for: .seconds(fade))
            guard !Task.isCancelled else { return }
            index = next
            target = nil
            withAnimation(.easeOut(duration: fade * 1.4)) { shown = true }
        }
    }

    private struct TimerKey: Equatable {
        let index: Int
        let active: Bool
        let count: Int
    }
}
