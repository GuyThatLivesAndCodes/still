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
        let personal = await provider.personalOpeners()
        return (lineup(personal: personal), Set(personal))
    }

    /// Hold-to-shuffle: new order, and the AI writes a new set.
    static func shuffle(timeout: Double = 10) async -> Lineup {
        let source = provider
        var personal: [String] = await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await source.freshOpeners() }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
        if personal.isEmpty { personal = await provider.personalOpeners() }
        return (lineup(personal: personal), Set(personal))
    }

    /// Mostly the preset openers, with an AI one dropped in every few lines.
    static func lineup(personal: [String]) -> [String] {
        var starters = Openers.starter.shuffled().filter { !personal.contains($0) }
        var ai = personal.shuffled()
        var out: [String] = []
        var gap = Int.random(in: 2...3)
        while !starters.isEmpty || !ai.isEmpty {
            if gap <= 0, let line = ai.popLast() {
                out.append(line)
                gap = Int.random(in: 3...6)
            } else if let line = starters.popLast() {
                out.append(line)
                gap -= 1
            } else if let line = ai.popLast() {
                out.append(line)
            }
        }
        return out
    }
}
