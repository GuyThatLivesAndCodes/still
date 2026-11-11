import Foundation

/// Source of personalised openers. The AI hooks in here later by writing
/// openers from past notes; nothing in the UI needs to change.
protocol OpenerProvider {
    func personalOpeners() async -> [String]
}

/// Default until the AI exists: no personal openers.
struct NoPersonalOpeners: OpenerProvider {
    func personalOpeners() async -> [String] { [] }
}

enum OpenerFeed {
    static var provider: OpenerProvider = NoPersonalOpeners()

    /// Personal openers first, then the starter set in a fresh order.
    static func load() async -> [String] {
        let personal = await provider.personalOpeners()
        let starters = Openers.starter.shuffled().filter { !personal.contains($0) }
        return personal + starters
    }
}
