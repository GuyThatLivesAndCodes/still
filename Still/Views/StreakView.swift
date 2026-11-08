import SwiftUI

struct StreakView: View {
    @Environment(StreakStore.self) private var streak
    @AppStorage("streakVisible") private var visible = true
    @State private var askPause = false
    @State private var askResume = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Streak")
                        .font(.system(size: 34, weight: .semibold))
                        .kerning(-1.2)
                        .foregroundStyle(Theme.ink)

                    hero(now: ctx.date)
                    controls(now: ctx.date)

                    Text("While paused, you can keep writing as usual. Entries won't count toward the streak, and reminders won't ask you to resume.")
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
            .onChange(of: Int(ctx.date.timeIntervalSince1970) / 30) { _, _ in streak.refresh() }
        }
        .onAppear { streak.refresh() }
        .confirmationDialog("Pause your streak?", isPresented: $askPause, titleVisibility: .visible) {
            Button("Pause in 6 hours") { streak.requestPause() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("The pause takes effect after 6 hours, so you can change your mind. Pausing is unlimited and always free.")
        }
        .confirmationDialog("Resume your streak?", isPresented: $askResume, titleVisibility: .visible) {
            Button("Resume in 6 hours") { streak.requestResume() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("After 6 hours a fresh 36-hour window begins.")
        }
    }

    private func hero(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(streak.days)")
                    .font(.system(size: 72, weight: .semibold))
                    .kerning(-3)
                    .foregroundStyle(Theme.ink)
                Text(streak.days == 1 ? "day of showing up" : "days of showing up")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
            }

            if streak.isPaused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondary)
            } else if streak.isExpired(at: now) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This streak ended. Writing again starts a new one.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    if streak.revivesLeft > 0 {
                        Button("Use a revive (\(streak.revivesLeft) left)") { streak.revive() }
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
                    ProgressView(value: left / StreakStore.window)
                        .tint(Theme.accent)
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
        .glass(26)
    }

    private func controls(now: Date) -> some View {
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

            Divider().overlay(Theme.hairline).padding(.horizontal, 16)

            pauseRow(now: now)
                .padding(16)
        }
        .card(22)
    }

    @ViewBuilder
    private func pauseRow(now: Date) -> some View {
        if let at = streak.pauseEffectiveAt {
            pendingRow(title: "Pausing in \(Fmt.hm(at.timeIntervalSince(now)))") { streak.cancelPauseRequest() }
        } else if let at = streak.resumeEffectiveAt {
            pendingRow(title: "Resuming in \(Fmt.hm(at.timeIntervalSince(now)))") { streak.cancelResumeRequest() }
        } else if streak.isPaused {
            actionRow(title: "Resume streak", subtitle: "Takes effect after 6 hours.") { askResume = true }
        } else {
            actionRow(title: "Pause streak", subtitle: "Takes effect after 6 hours. Unlimited, always free.") { askPause = true }
                .disabled(!streak.isActive(at: now))
                .opacity(streak.isActive(at: now) ? 1 : 0.5)
        }
    }

    private func actionRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pendingRow(title: String, cancel: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink).monospacedDigit()
            Spacer()
            Button("Cancel", action: cancel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
    }
}
