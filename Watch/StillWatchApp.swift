import SwiftUI
import WatchConnectivity
import Observation
import WidgetKit

@main
struct StillWatchApp: App {
    @State private var link = WatchLink.shared

    var body: some Scene {
        WindowGroup {
            WatchHome()
                .environment(link)
        }
    }
}

/// Watch side of the link. Sends text to the iPhone (which encrypts and seals
/// it) and receives streak info. Entries are never stored on the watch.
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    var days: Int
    var deadline: Date?
    var paused: Bool
    var visible: Bool

    override init() {
        let d = UserDefaults.standard
        days = d.integer(forKey: "days")
        let dl = d.double(forKey: "deadline")
        deadline = dl > 0 ? Date(timeIntervalSince1970: dl) : nil
        paused = d.bool(forKey: "paused")
        visible = d.object(forKey: "visible") as? Bool ?? true
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func seal(_ text: String) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([
            "text": text,
            "createdAt": Date.now.timeIntervalSince1970
        ])
    }

    func remaining(at now: Date) -> TimeInterval? {
        guard visible, !paused, days > 0, let deadline, deadline > now else { return nil }
        return deadline.timeIntervalSince(now)
    }

    private func apply(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        Task { @MainActor in
            days = context["days"] as? Int ?? 0
            deadline = (context["deadline"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            paused = context["paused"] as? Bool ?? false
            visible = context["visible"] as? Bool ?? true
            let d = UserDefaults.standard
            d.set(days, forKey: "days")
            d.set(deadline?.timeIntervalSince1970 ?? 0, forKey: "deadline")
            d.set(paused, forKey: "paused")
            d.set(visible, forKey: "visible")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

struct WatchHome: View {
    @Environment(WatchLink.self) private var link
    @State private var text = ""
    @State private var sealed = false

    private var canSeal: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if sealed {
                        sealedView
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            if let left = link.remaining(at: ctx.date), left < 12 * 3600 {
                                Label {
                                    Text(clock(left)).monospacedDigit()
                                } icon: {
                                    Circle().fill(Color(red: 0.667, green: 0.706, blue: 0.941)).frame(width: 6, height: 6)
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }

                        TextField("What's here right now?", text: $text, axis: .vertical)
                            .lineLimit(2...6)

                        Button {
                            link.seal(text)
                            text = ""
                            withAnimation { sealed = true }
                        } label: {
                            Label("Seal", systemImage: "lock")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(canSeal ? Color(white: 0.95) : Color(white: 0.2))
                        .foregroundStyle(canSeal ? Color.black : Color(white: 0.45))
                        .disabled(!canSeal)
                    }
                }
            }
            .navigationTitle("still.")
        }
        .containerBackground(Color.black.gradient, for: .navigation)
    }

    private var sealedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(white: 0.95))
            Text("Sealed.")
                .font(.headline)
            Text("It rests on your iPhone for 14 days.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { withAnimation { sealed = false } }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d:%02d left", s / 3600, (s % 3600) / 60, s % 60)
    }
}
