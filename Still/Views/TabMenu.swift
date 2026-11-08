import SwiftUI
import SwiftData

/// Top-left menu button that opens a small frosted list of tabs.
struct TabMenu: View {
    @Binding var tab: AppTab
    @Binding var open: Bool
    @Query private var notes: [Note]
    @Environment(StreakStore.self) private var streak

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { open.toggle() }
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

            if open {
                VStack(spacing: 2) {
                    ForEach(AppTab.allCases) { item in
                        row(item)
                    }
                }
                .padding(6)
                .frame(width: 216)
                .glass(22)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity),
                    removal: .opacity))
            }
        }
    }

    private func row(_ item: AppTab) -> some View {
        let selected = item == tab
        return Button {
            tab = item
            withAnimation(.easeOut(duration: 0.18)) { open = false }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selected ? Theme.accent : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                Text(item.title)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(meta(item))
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(selected ? Color.white.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func meta(_ item: AppTab) -> String {
        switch item {
        case .streak: return streak.days > 0 ? "\(streak.days)d" : ""
        case .notes: return notes.isEmpty ? "" : "\(notes.count)"
        default: return ""
        }
    }
}
