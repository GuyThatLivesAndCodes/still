import SwiftUI
import SwiftData

@main
struct StillApp: App {
    @State private var streak = StreakStore()
    @State private var wallet = TokenWallet()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(streak)
                .environment(wallet)
                .environment(lock)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: [Entry.self, Note.self])
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, vault, notes, streak, you
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .vault: return "Vault"
        case .notes: return "Notes"
        case .streak: return "Streak"
        case .you: return "You"
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(StreakStore.self) private var streak
    @Environment(AppLock.self) private var lock
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false

    @State private var tab: AppTab = .today
    @State private var menuOpen = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()

            Group {
                switch tab {
                case .today: TodayView()
                case .vault: VaultView()
                case .notes: NotesView()
                case .streak: StreakView()
                case .you: YouView()
                }
            }
            .transition(.opacity)

            if menuOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { menuOpen = false } }
                    .transition(.opacity)
            }

            TabMenu(tab: $tab, open: $menuOpen)
                .padding(.leading, 20)
                .padding(.top, 6)

            if faceIDEnabled && lock.isLocked {
                LockView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
        .task {
            streak.refresh()
            ReminderService.reschedule(entryDates: entries.map(\.createdAt), streak: streak, enabled: remindersEnabled)
            await ReflectionQueue.deliverIfDue(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfEnabled()
            case .active:
                streak.refresh()
                ReminderService.reschedule(entryDates: entries.map(\.createdAt), streak: streak, enabled: remindersEnabled)
                Task { await ReflectionQueue.deliverIfDue(context: context) }
            default:
                break
            }
        }
    }
}
