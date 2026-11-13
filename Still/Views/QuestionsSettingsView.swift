import SwiftUI

/// You → Questions. Picks the kinds of preset prompts and how much Quiet AI
/// writes. Today rebuilds its line as soon as either changes.
struct QuestionsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(QuestionPrefs.categoriesKey) private var categoriesRaw = ""
    @AppStorage(QuestionPrefs.mixKey) private var mixRaw = AIMix.mild.rawValue
    @State private var blocked = 0
    @State private var sample: [String] = []

    private var selected: Set<OpenerCategory> { QuestionPrefs.decode(categoriesRaw) }
    private var mix: AIMix { AIMix(rawValue: mixRaw) ?? .mild }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Kinds of questions").sectionLabel()
                            Spacer()
                            Text("\(selected.count) of \(OpenerCategory.allCases.count)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.tertiary)
                        }
                        .padding(.horizontal, 6)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(OpenerCategory.allCases) { category in
                                categoryTile(category)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where they come from").sectionLabel().padding(.horizontal, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(AIMix.allCases.enumerated()), id: \.element) { i, option in
                                if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 16) }
                                mixRow(option)
                            }
                        }
                        .card(22)
                        if mix != .generic && !AIService.isActive {
                            Label("Quiet AI is off, so you'll see preset questions until it's on.",
                                  systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if mix != .generic {
                            Text("Questions written for you show in purple. They start after a few entries.")
                                .font(.footnote)
                                .foregroundStyle(Theme.tertiary)
                                .padding(.horizontal, 6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A taste").sectionLabel().padding(.horizontal, 6)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sample, id: \.self) { line in
                                Text(verbatim: line)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity)
                            }
                        }
                        .padding(16)
                        .card(22)
                        .animation(.easeInOut(duration: 0.25), value: sample)
                    }

                    Label("Hold the question above Write to shuffle. You can shuffle once every 30 seconds.",
                          systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.black)
        .sensoryFeedback(.selection, trigger: categoriesRaw)
        .sensoryFeedback(.selection, trigger: mixRaw)
        .sensoryFeedback(.warning, trigger: blocked)
        .onAppear(perform: refreshSample)
        .onChange(of: categoriesRaw) { _, _ in refreshSample() }
    }

    private func categoryTile(_ category: OpenerCategory) -> some View {
        let on = selected.contains(category)
        return Button { toggle(category) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(on ? Theme.accent : Theme.tertiary)
                        .frame(width: 22, height: 22)
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(on ? Theme.accent : Theme.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(category.blurb)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Theme.accent.opacity(0.1) : Theme.card,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(on ? Theme.accent.opacity(0.55) : Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .animation(.snappy(duration: 0.2), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on && selected.count == 1 ? "At least one kind stays on" : "")
    }

    private func mixRow(_ option: AIMix) -> some View {
        let on = option == mix
        return Button { mixRaw = option.rawValue } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(option.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    MixBar(aiShare: share(option))
                        .frame(width: 120, height: 6)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Theme.accent : Theme.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func share(_ option: AIMix) -> Double {
        switch option {
        case .generic: return 0
        case .mild: return 0.2
        case .mixed: return 0.75
        case .ai: return 1
        }
    }

    private func toggle(_ category: OpenerCategory) {
        var next = selected
        if next.contains(category) {
            guard next.count > 1 else { blocked += 1; return }
            next.remove(category)
        } else {
            next.insert(category)
        }
        categoriesRaw = QuestionPrefs.encode(next)
    }

    private func refreshSample() {
        sample = Array(Openers.starter(in: selected).shuffled().prefix(3))
    }
}

/// Ten small segments: gray for preset questions, purple for AI ones.
private struct MixBar: View {
    let aiShare: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                Capsule()
                    .fill(Double(i) < aiShare * 10 ? Theme.ai : Color.white.opacity(0.2))
            }
        }
        .animation(.snappy, value: aiShare)
        .accessibilityHidden(true)
    }
}
