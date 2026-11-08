import SwiftUI
import SwiftData

/// Shows an entry for 60 seconds, then reseals automatically.
struct RevealView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var endsAt = Date.now.addingTimeInterval(60)
    @State private var text = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(0, endsAt.timeIntervalSince(ctx.date))
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 44, height: 44)
                                .glass(22)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reseal and go back")
                        Spacer()
                        ring(left: left)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Fmt.period(entry.createdAt)) · \(daysAgo) days ago")
                            .sectionLabel()
                        Text(entry.createdAt.formatted(.dateTime.month(.wide).day()))
                            .font(.system(size: 28, weight: .semibold))
                            .kerning(-0.8)
                            .foregroundStyle(Theme.ink)
                    }

                    ScrollView {
                        Text(text)
                            .font(.system(size: 18))
                            .lineSpacing(6)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.disabled)
                            .privacySensitive()
                    }
                    .scrollIndicators(.hidden)

                    Text("This view reseals on its own. Nothing here can be changed.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)

                    Button("Reseal now") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .onChange(of: left <= 0) { _, done in if done { dismiss() } }
        }
        .onAppear { text = entry.plainText() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dismiss() }
        }
    }

    private var daysAgo: Int {
        Calendar.current.dateComponents([.day], from: entry.createdAt, to: .now).day ?? 0
    }

    private func ring(left: TimeInterval) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: left / 60)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: left)
            }
            .frame(width: 40, height: 40)
            Text("\(Int(left.rounded(.up)))")
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 34, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(left.rounded(.up))) seconds until this entry reseals")
    }
}

/// Six-hour deletion wait, then a second confirmation.
struct DeleteView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let confirmAt = entry.deletionConfirmableAt ?? ctx.date
            let left = max(0, confirmAt.timeIntervalSince(ctx.date))
            let progress = 1 - left / Entry.deletionWait
            VStack(spacing: 24) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 5).padding(.top, 10)

                Text("Deletion pending")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)

                Text(Fmt.entryLabel(entry.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)

                VStack(spacing: 14) {
                    Text(left > 0 ? "Can be confirmed in" : "Ready to confirm")
                        .sectionLabel()
                    Text(Fmt.clock(left))
                        .font(.system(size: 56, weight: .semibold))
                        .kerning(-2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(Theme.ink)
                        .frame(width: 220)
                    Text("Six hours gives you room to change your mind. After that, you'll confirm once more and the entry is gone for good.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: 300)
                }
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 10) {
                    Button(left > 0 ? "Confirm deletion · \(Fmt.hm(left))" : "Delete forever") {
                        confirming = true
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: left <= 0))
                    .disabled(left > 0)

                    Button("Keep this entry") {
                        entry.deletionRequestedAt = nil
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .presentationBackground(.black)
        .presentationDetents([.large])
        .alert("Delete forever?", isPresented: $confirming) {
            Button("Delete", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This entry will be permanently erased. This can't be undone.")
        }
    }
}
