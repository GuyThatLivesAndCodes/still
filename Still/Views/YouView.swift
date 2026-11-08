import SwiftUI
import SwiftData

struct YouView: View {
    @Environment(TokenWallet.self) private var wallet
    @Environment(StreakStore.self) private var streak
    @Environment(AppLock.self) private var lock
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @State private var showPrivacy = false
    @State private var remindersDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("You")
                    .font(.system(size: 34, weight: .semibold))
                    .kerning(-1.2)
                    .foregroundStyle(Theme.ink)

                tokens

                section("Reminders") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(get: { remindersEnabled }, set: setReminders)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gentle nudges").font(.body.weight(.medium))
                                Text(habitLine).font(.footnote).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .tint(Theme.accent)
                        if remindersDenied {
                            Text("Notifications are off for still. in Settings.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(16)
                }

                section("Privacy") {
                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(get: { faceIDEnabled }, set: setFaceID)) {
                            Text("Lock with Face ID").font(.body.weight(.medium))
                        }
                        .tint(Theme.accent)
                        .padding(16)
                        Divider().overlay(Theme.hairline).padding(.horizontal, 16)
                        rowButton("How your data is handled") { showPrivacy = true }
                        Divider().overlay(Theme.hairline).padding(.horizontal, 16)
                        ShareLink(item: exportText) {
                            rowLabel("Export opened entries")
                        }
                        .buttonStyle(.plain)
                        .disabled(readyEntries.isEmpty)
                        .opacity(readyEntries.isEmpty ? 0.5 : 1)
                    }
                }

                Text("still. 0.1 · Write it, seal it, and let it go.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPrivacy) { PrivacySheet() }
    }

    private var tokens: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Early reveals").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(TokenWallet.monthlyFree) free each month · resets \(Fmt.shortDate(wallet.nextReset))")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<TokenWallet.monthlyFree, id: \.self) { i in
                    Circle()
                        .fill(i < wallet.available() ? Theme.accent : Color.white.opacity(0.15))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wallet.available()) of \(TokenWallet.monthlyFree) left")
        }
        .padding(18)
        .glass(22)
    }

    private var habitLine: String {
        guard let m = ReminderService.typicalMinute(of: entries.map(\.createdAt)) else {
            return "Timed to when you usually write"
        }
        return "You usually write in the \(ReminderService.periodName(forMinute: m)), around \(Fmt.timeOfDay(minute: m))"
    }

    private var readyEntries: [Entry] {
        entries.filter { $0.isReady() && !$0.isPendingDeletion }
    }

    private var exportText: String {
        readyEntries.reversed().map { e in
            "\(e.createdAt.formatted(date: .complete, time: .shortened))\n\n\(e.plainText())"
        }.joined(separator: "\n\n———\n\n")
    }

    private func setReminders(_ on: Bool) {
        if !on {
            remindersEnabled = false
            ReminderService.reschedule(entryDates: [], streak: streak, enabled: false)
            return
        }
        Task {
            let granted = await ReminderService.requestAuthorization()
            await MainActor.run {
                remindersEnabled = granted
                remindersDenied = !granted
                ReminderService.reschedule(entryDates: entries.map(\.createdAt), streak: streak, enabled: granted)
            }
        }
    }

    private func setFaceID(_ on: Bool) {
        Task {
            let ok = await lock.authenticate(reason: on ? "Turn on Face ID lock" : "Turn off Face ID lock")
            if ok { faceIDEnabled = on }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabel().padding(.horizontal, 6)
            content().card(22)
        }
        .padding(.top, 4)
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title) }.buttonStyle(.plain)
    }

    private func rowLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Plain statements that match what this build actually does.
struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Point: Identifiable {
        let icon: String, title: String, detail: String
        var id: String { title }
    }

    private let points: [Point] = [
        Point(icon: "lock.shield", title: "Encrypted on this iPhone",
              detail: "Every entry is encrypted with AES-256-GCM before it's saved. The key is kept in the iOS Keychain and never leaves this device."),
        Point(icon: "iphone", title: "No account, no servers",
              detail: "still. has no sign-in, analytics, or ads. In this build, nothing you write is sent anywhere."),
        Point(icon: "exclamationmark.triangle", title: "Device-bound by design",
              detail: "Because the key never leaves this iPhone, entries can't be restored on a different device. Export opened entries if you want a copy."),
        Point(icon: "faceid", title: "Face ID stays with iOS",
              detail: "Face ID is handled by iOS. still. never sees your biometric data."),
        Point(icon: "applewatch", title: "Apple Watch",
              detail: "Entries written on Apple Watch go straight to your iPhone and are encrypted there. The watch only holds them until your iPhone receives them.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(points) { point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.title).font(.headline).foregroundStyle(Theme.ink)
                                Text(point.detail).font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.black)
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("still.")
                    .font(.system(size: 40, weight: .semibold))
                    .kerning(-1.8)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    Task { await lock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task { await lock.authenticate() }
    }
}
