import SwiftUI
import SwiftData

/// Top-left button that opens the side panel.
struct MenuButton: View {
    @Binding var open: Bool

    var body: some View {
        Button {
            withAnimation(SidePanel.spring) { open.toggle() }
        } label: {
            Image(systemName: open ? "xmark" : "line.3.horizontal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
                .glass(22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? "Close menu" : "Open menu")
    }
}

/// Slide-in panel listing the app's sections. Opens from the menu button or
/// by swiping in from the left edge; swipe left or tap outside to close.
struct SidePanel: View {
    static let width: CGFloat = 272
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @Binding var tab: AppTab
    @Binding var open: Bool
    @Environment(StreakStore.self) private var streak
    @AppStorage("streakVisible") private var streakVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("still.")
                .font(.system(size: 26, weight: .semibold))
                .kerning(-1)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(AppTab.visible) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.footnote)
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(white: 0.04).opacity(0.7))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                }
                .ignoresSafeArea()
        }
    }

    private func row(_ item: AppTab) -> some View {
        let selected = item == tab
        return Button {
            tab = item
            withAnimation(Self.spring) { open = false }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                Text(item.title)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(meta(item))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(selected ? Color.white.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func meta(_ item: AppTab) -> String {
        switch item {
        case .streak: return streakVisible && streak.days > 0 ? "\(streak.days)d" : ""
        default: return ""
        }
    }
}

private struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension AppTab {
    var icon: String {
        switch self {
        case .today: return "square.and.pencil"
        case .vault: return "lock"
        case .notes: return "sparkles"
        case .streak: return "flame"
        case .you: return "person.crop.circle"
        }
    }
}
