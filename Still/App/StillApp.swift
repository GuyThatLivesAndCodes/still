import SwiftUI
import SwiftData

@main
struct StillApp: App {
    @State private var streak = StreakStore()
    @State private var wallet = TokenWallet()
    @State private var lock = AppLock()
    @State private var router = AppRouter.shared
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Entry.self, Note.self)
        } catch {
            fatalError("Could not open the journal store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(streak)
                .environment(wallet)
                .environment(lock)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear { PhoneLink.shared.start(container: container, streak: streak) }
                .onOpenURL { router.handle($0) }
        }
        .modelContainer(container)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, vault, notes, streak, you
    var id: String { rawValue }

    /// Notes stay hidden until the reflection server exists.
    static var visible: [AppTab] {
        allCases.filter { $0 != .notes || ReflectionQueue.isEnabled }
    }

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
    @Environment(AppRouter.self) private var router
    @AppStorage("streakVisible") private var streakVisible = true
    @AppStorage("acceptedTermsVersion") private var acceptedTermsVersion = 0
    @AppStorage("replayIntro") private var replayIntro = false
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

            if acceptedTermsVersion < LegalText.version || replayIntro {
                OnboardingView(startAtTerms: acceptedTermsVersion > 0 && !replayIntro) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        acceptedTermsVersion = LegalText.version
                        replayIntro = false
                    }
                }
                .transition(.opacity)
                .zIndex(5)
            }

            if faceIDEnabled && lock.isLocked {
                LockView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
        .onChange(of: router.writeRequest) { _, _ in
            menuOpen = false
            tab = .today
        }
        .onChange(of: streak.state) { _, _ in
            EntryWriter.syncSurroundings(context: context, streak: streak)
        }
        .onChange(of: streakVisible) { _, _ in
            EntryWriter.syncSurroundings(context: context, streak: streak)
        }
        .task {
            streak.refresh()
            EntryWriter.syncSurroundings(context: context, streak: streak)
            await ReflectionQueue.deliverIfDue(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfEnabled()
            case .active:
                streak.refresh()
                EntryWriter.syncSurroundings(context: context, streak: streak)
                Task { await ReflectionQueue.deliverIfDue(context: context) }
            default:
                break
            }
        }
    }
}
