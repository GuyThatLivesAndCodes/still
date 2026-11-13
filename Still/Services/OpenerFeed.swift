import Foundation

/// Source of personalised openers written by the AI.
protocol OpenerProvider {
    /// Cached openers right away (refreshing quietly when stale).
    func personalOpeners() async -> [String]
    /// Writes a fresh set now and returns it (empty if AI can't run).
    func freshOpeners() async -> [String]
}

/// Default when there's no AI: no personal openers.
struct NoPersonalOpeners: OpenerProvider {
    func personalOpeners() async -> [String] { [] }
    func freshOpeners() async -> [String] { [] }
}

enum OpenerFeed {
    static var provider: OpenerProvider = NoPersonalOpeners()

    typealias Lineup = (openers: [String], ai: Set<String>)

    static func load() async -> Lineup {
        let mix = QuestionPrefs.mix
        let personal = mix == .generic ? [] : await provider.personalOpeners()
        return (lineup(personal: personal, mix: mix), Set(personal))
    }

    /// Hold-to-shuffle: new order, and the AI writes a new set (unless AI is off for questions).
    static func shuffle(timeout: Double = 10) async -> Lineup {
        let mix = QuestionPrefs.mix
        guard mix != .generic else { return (lineup(personal: [], mix: mix), []) }
        let source = provider
        var personal: [String] = await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await source.freshOpeners() }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
        if personal.isEmpty { personal = await provider.personalOpeners() }
        return (lineup(personal: personal, mix: mix), Set(personal))
    }

    /// Interleaves preset and AI questions by the chosen mix. Falls back to presets
    /// when there are no AI questions yet, so the line is never empty.
    static func lineup(personal: [String], mix: AIMix = QuestionPrefs.mix,
                       categories: Set<OpenerCategory> = QuestionPrefs.categories) -> [String] {
        var starters = Openers.starter(in: categories).shuffled().filter { !personal.contains($0) }
        var ai = personal.shuffled()
        switch mix {
        case .generic:
            return starters
        case .ai:
            return ai.isEmpty ? starters : ai
        case .mild:
            return interleave(major: &starters, minor: &ai, firstGap: 2...3, gap: 3...6)
        case .mixed:
            return interleave(major: &ai, minor: &starters, firstGap: 1...2, gap: 2...4)
        }
    }

    /// Mostly `major`, with one `minor` line dropped in every few.
    private static func interleave(major: inout [String], minor: inout [String],
                                   firstGap: ClosedRange<Int>, gap gapRange: ClosedRange<Int>) -> [String] {
        var out: [String] = []
        var gap = Int.random(in: firstGap)
        while !major.isEmpty || !minor.isEmpty {
            if gap <= 0, let line = minor.popLast() {
                out.append(line)
                gap = Int.random(in: gapRange)
            } else if let line = major.popLast() {
                out.append(line)
                gap -= 1
            } else if let line = minor.popLast() {
                out.append(line)
            }
        }
        return out
    }
}
