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
    @State private var showTerms = false
    @State private var showPolicy = false
    @AppStorage("replayIntro") private var replayIntro = false
    @State private var remindersDenied = false
    @State private var showAI = false
    @State private var showProfile = false
    @AppStorage(Profile.nameKey) private var profileName = ""
    @AppStorage(Profile.birthdayKey) private var profileBirthday: Double = 0
    @AppStorage(Profile.genderKey) private var profileGender = Gender.unset.rawValue
    @AppStorage(NudgeWriter.enabledKey) private var aiNudges = true
    @AppStorage(Notifier.repliesKey) private var notifyReplies = true
    @AppStorage(Notifier.unlocksKey) private var notifyUnlocks = true
    @Environment(\.modelContext) private var context
    // Observed so the Quiet AI row updates when the sheet changes them.
    @AppStorage(AIService.modeKey) private var aiMode = AIMode.automatic.rawValue
    @AppStorage(AIService.consentKey) private var aiCloudConsent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("You")
                    .font(.system(size: 34, weight: .semibold))
                    .kerning(-1.2)
                    .foregroundStyle(Theme.ink)

                tokens

                section("About you") {
                    Button { showProfile = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Theme.accent.opacity(0.18))
                                Text(initial)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileName.isEmpty ? "Add your name" : profileName)
                                    .font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                                Text(profileLine).font(.footnote).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                section("Notifications") {
                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(get: { remindersEnabled }, set: setReminders)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Daily reminder").font(.body.weight(.medium))
                                Text(habitLine).font(.footnote).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .tint(Theme.accent)
                        .padding(16)
                        if remindersEnabled && AIService.isActive {
                            Divider().overlay(Theme.hairline).padding(.leading, 16)
                            Toggle(isOn: $aiNudges) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Written by Quiet AI").font(.body.weight(.medium))
                                    Text("A fresh line each day, never about anything sensitive")
                                        .font(.footnote).foregroundStyle(Theme.tertiary)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(16)
                        }
                        if ReflectionQueue.isEnabled {
                            Divider().overlay(Theme.hairline).padding(.leading, 16)
                            Toggle(isOn: Binding(get: { notifyReplies }, set: { setNotify(replies: $0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Notes and replies").font(.body.weight(.medium))
                                    Text("When a note or chat reply arrives").font(.footnote).foregroundStyle(Theme.tertiary)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(16)
                        }
                        Divider().overlay(Theme.hairline).padding(.leading, 16)
                        Toggle(isOn: Binding(get: { notifyUnlocks }, set: { setNotify(unlocks: $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlocked entries").font(.body.weight(.medium))
                                Text("Around midday on the day they open").font(.footnote).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .tint(Theme.accent)
                        .padding(16)
                        if remindersDenied {
                            Text("Notifications are off for still. in Settings.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .padding([.horizontal, .bottom], 16)
                        }
                    }
                    .animation(.snappy, value: remindersEnabled)
                }

                section("Quiet AI") {
                    Button { showAI = true } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notes, chats and openers").font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                                Text(aiLine).font(.footnote).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiary)
                        }
                        .padding(16)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

                section("About") {
                    VStack(spacing: 0) {
                        rowButton("Terms of Use") { showTerms = true }
                        Divider().overlay(Theme.hairline).padding(.horizontal, 16)
                        rowButton("Privacy Policy") { showPolicy = true }
                        Divider().overlay(Theme.hairline).padding(.horizontal, 16)
                        rowButton("Replay the intro") { replayIntro = true }
                    }
                }

                Text("still. 0.3 · Write it, seal it, and let it go.")
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
        .sheet(isPresented: $showAI) { AISettingsView() }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .onChange(of: aiNudges) { _, _ in
            ReminderService.reschedule(entryDates: entries.map(\.createdAt), streak: streak, enabled: remindersEnabled)
        }
        .sheet(isPresented: $showTerms) { LegalSheet(title: "Terms of Use", sections: LegalText.terms) }
        .sheet(isPresented: $showPolicy) { LegalSheet(title: "Privacy Policy", sections: LegalText.privacy) }
    }

    private var tokens: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Early reveals").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(wallet.bonus > 0
                     ? "\(TokenWallet.weeklyFree) free each week · \(wallet.bonus) refunded"
                     : "\(TokenWallet.weeklyFree) free each week · resets \(Fmt.shortDate(wallet.nextReset))")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                Text("Spent tokens come back when the entry opens.")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<max(TokenWallet.weeklyFree, wallet.available()), id: \.self) { i in
                    Circle()
                        .fill(i < wallet.available() ? Theme.accent : Color.white.opacity(0.15))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wallet.available()) early reveals left")
        }
        .padding(18)
        .glass(22)
    }

    private var initial: String {
        profileName.first.map { String($0).uppercased() } ?? "?"
    }

    private var profileLine: String {
        _ = (profileBirthday, profileGender)
        var parts: [String] = []
        if let age = Profile.age { parts.append("\(age)") }
        let g = Gender(rawValue: profileGender) ?? .unset
        if g != .unset && g != .preferNot { parts.append(g == .other ? (Profile.genderOther.isEmpty ? "Other" : Profile.genderOther) : g.title) }
        return parts.isEmpty ? "Helps Quiet AI fit its words to you" : parts.joined(separator: " · ")
    }

    private func setNotify(replies: Bool? = nil, unlocks: Bool? = nil) {
        if let replies { notifyReplies = replies }
        if let unlocks { notifyUnlocks = unlocks }
        if replies == false {
            Notifier.cancel([Notifier.noteID])
        }
        VaultCare.scheduleUnlocks(entries)
        if replies == true || unlocks == true {
            Task {
                let granted = await ReminderService.requestAuthorization()
                await MainActor.run { remindersDenied = !granted }
            }
        }
    }

    private var habitLine: String {
        guard let m = ReminderService.typicalMinute(of: entries.map(\.createdAt)) else {
            return "Timed to when you usually write"
        }
        return "You usually write in the \(ReminderService.periodName(forMinute: m)), around \(Fmt.timeOfDay(minute: m))"
    }

    private var aiLine: String {
        _ = (aiMode, aiCloudConsent)
        switch AIService.activeEngine {
        case .onDevice: return "Running on this iPhone"
        case .cloud: return "Running on Cloudflare"
        case nil: return AIService.mode == .off ? "Off" : "Not available yet · tap to see options"
        }
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

    private var points: [Point] {
        var list = basePoints
        list.insert(aiPoint, at: 2)
        if AIService.cloudConsent {
            list[1] = Point(icon: "iphone", title: "No account, no tracking",
                            detail: "still. has no sign-in, analytics, or ads. The only thing that can leave this iPhone is text for Quiet AI on Cloudflare, which you've allowed.")
        }
        return list
    }

    private var aiPoint: Point {
        AIService.cloudConsent
            ? Point(icon: "sparkles", title: "Quiet AI",
                    detail: "Notes and openers use Apple's on-device model when it's available. You've allowed Cloudflare, so when it's used the needed text is sent over HTTPS, answered, and discarded with no logs or storage.")
            : Point(icon: "sparkles", title: "Quiet AI",
                    detail: "Notes and openers only use Apple's on-device model. Cloudflare is off, so nothing you write leaves this iPhone.")
    }

    private let basePoints: [Point] = [
        Point(icon: "lock.shield", title: "Encrypted on this iPhone",
              detail: "Every entry is encrypted with AES-256-GCM before it's saved. The key is kept in the iOS Keychain and never leaves this device."),
        Point(icon: "iphone", title: "No account, no servers",
              detail: "still. has no sign-in, analytics, or ads. Nothing you write is sent anywhere."),
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
