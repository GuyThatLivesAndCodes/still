import SwiftUI

/// Plain-language Terms of Use and Privacy Policy. Bump `version` whenever
/// either changes; users are asked to accept again.
enum LegalText {
    static let version = 3
    static let effective = "November 12, 2026"

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let terms: [Section] = [
        Section(title: "Using still.",
                body: "still. is a personal journal for your own private use. You must be at least 13 years old to use it."),
        Section(title: "Not a substitute for care",
                body: "still. is not therapy, medical advice, or a crisis service. If you are in danger or thinking about harming yourself, contact local emergency services right away. In the US you can call or text 988."),
        Section(title: "Sealed means sealed",
                body: "Entries can't be edited once sealed. They open at the start of the 5th day after you write them. Early reveals use tokens; you get 2 free each week. An entry opened early stays open afterward, and its token is returned on the day it would have opened anyway. Tokens are never needed to write, to keep your journal private, or to keep a streak."),
        Section(title: "Deletion is permanent",
                body: "Deleting an entry takes a 2-hour wait and a second confirmation. After that it is erased and cannot be recovered by anyone, including us."),
        Section(title: "Your responsibility for your device",
                body: "Your journal lives only on this iPhone. If the app is deleted, the device is lost, or you move to a new phone, sealed entries can't be recovered. Export opened entries if you want a copy."),
        Section(title: "As is",
                body: "still. is provided as is, without warranties of any kind. To the extent the law allows, we aren't liable for lost data or for decisions made based on what you write or read in the app."),
        Section(title: "Changes",
                body: "If these terms change, the app will show you the new version and ask you to accept it before you continue.")
    ]

    static let privacy: [Section] = [
        Section(title: "What we collect",
                body: "Nothing. still. has no account, no analytics, no advertising, and no tracking. We don't keep anything you write."),
        Section(title: "Where your journal lives",
                body: "Entries are encrypted on your iPhone with AES-256-GCM before they are saved. The encryption key is stored in the iOS Keychain and never leaves the device."),
        Section(title: "Quiet AI",
                body: "Quiet AI writes short notes after you write, replies when you chat with it about a note, suggests openers, and can write your daily reminder. It uses your recent entries, notes and chats for this, plus your name, age and gender if you add them in You → About you (your exact birthday is never shared). By default it uses Apple's on-device model, so nothing leaves your iPhone. You can choose Automatic, on this iPhone only, Cloudflare only, or off in You → Quiet AI."),
        Section(title: "Cloudflare (only if you allow it)",
                body: "Cloudflare is off until you turn it on. When it's used, only the text needed for one note, reply, reminder or prompt (and the details from About you, if you added any) is sent over HTTPS to a still. server on Cloudflare, processed by an AI model, and discarded. It isn't logged, stored, linked to you, or used for training or advertising. Cloudflare may briefly see your IP address to deliver and rate-limit the request."),
        Section(title: "Apple Watch",
                body: "If you write on Apple Watch, the text is sent directly to your iPhone through Apple's encrypted watch connection, then encrypted and sealed there. The watch keeps it only until your iPhone receives it."),
        Section(title: "Widgets and reminders",
                body: "Widgets see only your streak count and timing, never entry text. Reminders and notifications are scheduled locally on your iPhone; no server sends them. They never show the text of your entries, notes or chats."),
        Section(title: "Face ID",
                body: "Face ID is handled entirely by iOS. still. never receives your biometric data."),
        Section(title: "If this ever changes",
                body: "If a feature ever needs to send anything off your device, it will be off by default, explained in plain words, and only turned on with your permission, just like Cloudflare for Quiet AI.")
    ]
}

struct LegalSheet: View {
    let title: String
    let sections: [LegalText.Section]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Effective \(LegalText.effective)")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title).font(.headline).foregroundStyle(Theme.ink)
                            Text(section.body).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.black)
    }
}
