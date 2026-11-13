import SwiftUI

struct StreakView: View {
    @Environment(StreakStore.self) private var streak
    @AppStorage("streakVisible") private var visible = true
    @State private var revived = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Streak")
                        .font(.system(size: 34, weight: .semibold))
                        .kerning(-1.2)
                        .foregroundStyle(Theme.ink)

                    hero(now: ctx.date)
                    controls

                    Text("Life happens. You have a full 36 hours between entries, and two revives a year if a window slips by.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 6)

                    Toggle(isOn: $visible) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show streak").font(.body.weight(.medium))
                            Text("Hide it anytime. Nothing is lost.")
                                .font(.footnote).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .tint(Theme.accent)
                    .padding(16)
                    .card(22)
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.success, trigger: revived)
    }

    private func hero(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(streak.days)")
                    .font(.system(size: 72, weight: .semibold))
                    .kerning(-3)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.ink)
                Text(streak.days == 1 ? "day of showing up" : "days of showing up")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }

            if streak.isExpired(at: now) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This streak ended. Writing again starts a new one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    if streak.revivesLeft > 0 {
                        Button("Use a revive (\(streak.revivesLeft) left)") {
                            withAnimation(.snappy) { if streak.revive() { revived += 1 } }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else if let left = streak.remaining(at: now) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Next entry within").font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Fmt.hm(left)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .foregroundStyle(Theme.ink)
                    ProgressView(value: min(max(left / StreakStore.window, 0), 1))
                        .tint(Theme.accent)
                        .animation(.linear(duration: 1), value: left)
                    Text("Each entry opens a fresh 36-hour window.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                }
            } else {
                Text("Write on Today to start a streak.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(26)
        .animation(.snappy, value: streak.isExpired(at: now))
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revives").font(.body.weight(.medium))
                    Text("Free, reset every January").font(.footnote).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<StreakStore.revivesPerYear, id: \.self) { i in
                        Circle()
                            .fill(i < streak.revivesLeft ? Theme.ink : Color.white.opacity(0.15))
                            .frame(width: 12, height: 12)
                    }
                    Text("\(streak.revivesLeft) left").font(.subheadline.weight(.semibold)).padding(.leading, 4)
                }
                .accessibilityElement(children: .combine)
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
        }
        .card(22)
        .animation(.snappy, value: streak.revivesLeft)
    }
}
