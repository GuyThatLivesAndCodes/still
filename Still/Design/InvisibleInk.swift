import SwiftUI

/// Invisible ink: a field of drifting, twinkling specks that covers content.
/// Revealing scatters the specks outward from the tap point while the content
/// fades in behind them; hiding pulls them back in.
struct InvisibleInk: ViewModifier {
    var hidden: Bool
    var tint: Color
    /// Where the reveal starts, in the modified view's own coordinates. Nil = center.
    var origin: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changedAt: Date = .distantPast
    @State private var transitioning = false

    static let duration: TimeInterval = 0.65

    func body(content: Content) -> some View {
        content
            .mask { inkMask }
            .overlay {
                particles
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: hidden) { _, _ in
                let start = Date.now
                changedAt = start
                transitioning = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.duration + 0.05))
                    if changedAt == start { transitioning = false }
                }
            }
    }

    /// 0 = fully covered, 1 = fully shown.
    private func shown(at date: Date) -> Double {
        guard transitioning else { return hidden ? 0 : 1 }
        let p = min(1, max(0, date.timeIntervalSince(changedAt) / Self.duration))
        let eased = 1 - pow(1 - p, 3)
        return hidden ? 1 - eased : eased
    }

    @ViewBuilder private var inkMask: some View {
        if transitioning {
            TimelineView(.animation) { ctx in
                let s = shown(at: ctx.date)
                Canvas { gc, size in
                    let o = origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
                    let reach = InkField.reach(from: o, in: size)
                    let radius = CGFloat(max(0.001, s * reach * 1.5))
                    gc.fill(Path(CGRect(origin: .zero, size: size)),
                            with: .radialGradient(Gradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.7),
                                .init(color: .clear, location: 1)
                            ]), center: o, startRadius: 0, endRadius: radius))
                }
            }
        } else {
            Rectangle().opacity(hidden ? 0 : 1)
        }
    }

    @ViewBuilder private var particles: some View {
        if hidden || transitioning {
            if reduceMotion && !transitioning {
                Canvas { gc, size in InkField.draw(in: &gc, size: size, time: 0, shown: 0, origin: origin, tint: tint) }
            } else {
                TimelineView(.animation(minimumInterval: transitioning ? nil : 1.0 / 30)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    let s = shown(at: ctx.date)
                    Canvas { gc, size in
                        InkField.draw(in: &gc, size: size, time: reduceMotion ? 0 : t, shown: s, origin: origin, tint: tint)
                    }
                }
            }
        }
    }
}

/// The speck field itself. Positions come from a fixed per-index hash, so the
/// field looks the same frame to frame and only drifts.
enum InkField {
    private static let levels = 5
    private static let maxCount = 1400

    /// One speck's fixed traits; the field only varies by time and reveal.
    private struct Speck {
        let x, y, phase, amp, speed, twinkle, weight, radius: Double
    }

    private static func rand(_ i: Int, _ salt: UInt64) -> Double {
        var z = UInt64(truncatingIfNeeded: i) &* 0x9E3779B97F4A7C15 &+ salt &* 0xD1B54A32D192ED03
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    private static let specks: [Speck] = (0..<InkField.maxCount).map { i in
        Speck(x: InkField.rand(i, 1), y: InkField.rand(i, 2), phase: InkField.rand(i, 3) * .pi * 2,
              amp: 1.5 + InkField.rand(i, 4) * 3.5, speed: 0.35 + InkField.rand(i, 5) * 0.9,
              twinkle: 1.2 + InkField.rand(i, 6) * 2.4, weight: 0.55 + InkField.rand(i, 7) * 0.45,
              radius: 0.45 + InkField.rand(i, 8) * 0.55)
    }

    static func reach(from o: CGPoint, in size: CGSize) -> Double {
        let dx = Double(max(o.x, size.width - o.x)), dy = Double(max(o.y, size.height - o.y))
        return (dx * dx + dy * dy).squareRoot()
    }

    static func draw(in gc: inout GraphicsContext, size: CGSize, time t: Double,
                     shown: Double, origin: CGPoint?, tint: Color) {
        guard size.width > 1, size.height > 1, shown < 1 else { return }
        let w = Double(size.width), h = Double(size.height)
        let count = min(maxCount, Int(w * h / 13))
        let o = origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let ox = Double(o.x), oy = Double(o.y)
        let reach = reach(from: o, in: size) * 1.15
        let front = shown * reach
        var buckets = Array(repeating: Path(), count: levels)

        for i in 0..<count {
            let p = specks[i]
            var x = p.x * w + sin(t * p.speed + p.phase) * p.amp
            var y = p.y * h + cos(t * p.speed * 0.8 + p.phase * 1.3) * p.amp
            var alpha = (0.35 + 0.65 * (0.5 + 0.5 * sin(t * p.twinkle + p.phase))) * p.weight

            if shown > 0 {
                // Specks inside the reveal front get pushed outward and fade.
                let dx = x - ox, dy = y - oy
                let d = max(0.001, (dx * dx + dy * dy).squareRoot())
                let k = min(1, max(0, (front - d) / (reach * 0.3) + 0.15 * shown))
                if k >= 1 { continue }
                x += dx / d * k * 22
                y += dy / d * k * 22
                alpha *= (1 - k) * (1 - shown)
            }

            guard alpha > 0.08 else { continue }
            let level = min(levels - 1, Int(alpha * Double(levels)))
            let r = p.radius
            buckets[level].addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }

        for (level, path) in buckets.enumerated() where !path.isEmpty {
            gc.fill(path, with: .color(tint.opacity((Double(level) + 0.6) / Double(levels))))
        }
    }
}

extension View {
    /// Covers the view in invisible ink while `hidden` is true.
    func invisibleInk(_ hidden: Bool, tint: Color = Theme.ink, origin: CGPoint? = nil) -> some View {
        modifier(InvisibleInk(hidden: hidden, tint: tint, origin: origin))
    }

    /// Makes this view the tap target for an inked part of it (see `InkReveal`).
    func inkReveal(hidden: Binding<Bool>, origin: Binding<CGPoint?>, inset: CGSize = .zero,
                   autoHide: TimeInterval = 60) -> some View {
        modifier(InkReveal(autoHide: autoHide, inset: inset, hidden: hidden, origin: origin))
    }
}

/// Tap to show, tap again to hide; hides on its own after `autoHide`
/// seconds and whenever the app leaves the foreground.
struct InkReveal: ViewModifier {
    var autoHide: TimeInterval = 60
    /// Where the inked part sits inside the tappable area, so the reveal starts under the finger.
    var inset: CGSize = .zero
    @Binding var hidden: Bool
    @Binding var origin: CGPoint?

    @Environment(\.scenePhase) private var scenePhase
    @State private var shownAt = 0

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { loc in
                origin = CGPoint(x: loc.x - inset.width, y: loc.y - inset.height)
                hidden.toggle()
                if !hidden { shownAt += 1 }
            }
            .task(id: shownAt) {
                guard !hidden else { return }
                try? await Task.sleep(for: .seconds(autoHide))
                if !Task.isCancelled { origin = nil; hidden = true }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { hidden = true }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hidden)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(hidden ? "Double-tap to show" : "Double-tap to hide")
    }
}
