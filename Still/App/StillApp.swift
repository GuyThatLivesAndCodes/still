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
        OpenerFeed.provider = AIOpeners(container: container)
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

    /// Notes stay hidden while AI is off or unavailable on this iPhone.
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
    /// Live finger offset while dragging the side panel open or closed.
    @State private var panelDrag: CGFloat = 0

    /// 0 = closed, 1 = fully open; follows the finger during a drag.
    private var panelProgress: CGFloat {
        let base: CGFloat = menuOpen ? 1 : 0
        return min(max(base + panelDrag / SidePanel.width, 0), 1)
    }

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
            .offset(x: panelProgress * 36)
            .allowsHitTesting(panelProgress == 0)

            // Invisible strip on the left edge: swipe right to pull the panel in.
            Color.clear
                .frame(width: 18)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(panelGesture)
                .allowsHitTesting(!menuOpen)
                .ignoresSafeArea()

            if panelProgress > 0 {
                Color.black.opacity(0.5 * panelProgress)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(SidePanel.spring) { menuOpen = false } }
                    .gesture(panelGesture)
            }

            SidePanel(tab: $tab, open: $menuOpen)
                .offset(x: (panelProgress - 1) * (SidePanel.width + 12))
                .gesture(panelGesture)
                .opacity(panelProgress > 0 ? 1 : 0)
                .accessibilityHidden(!menuOpen)

            MenuButton(open: $menuOpen)
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
        .onChange(of: menuOpen) { _, open in
            if open { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: menuOpen)
        .sensoryFeedback(.selection, trigger: tab)
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
            EntryWriter.syncSurroundings(context: context, streak: streak)
            await ReflectionQueue.deliverIfDue(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfEnabled()
            case .active:
                EntryWriter.syncSurroundings(context: context, streak: streak)
                Task { await ReflectionQueue.deliverIfDue(context: context) }
            default:
                break
            }
        }
    }
}

extension RootView {
    /// One drag handles both directions: right opens, left closes.
    fileprivate var panelGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Only horizontal drags move the panel, so vertical scrolling is untouched.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                panelDrag = value.translation.width
            }
            .onEnded { value in
                let flick = value.predictedEndTranslation.width
                let progress = panelProgress
                withAnimation(SidePanel.spring) {
                    if menuOpen {
                        menuOpen = !(progress < 0.6 || flick < -120)
                    } else {
                        menuOpen = progress > 0.35 || flick > 160
                    }
                    panelDrag = 0
                }
            }
    }
}
