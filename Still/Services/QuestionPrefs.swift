import Foundation

/// How many of the prompts above the composer come from Quiet AI.
enum AIMix: String, CaseIterable, Identifiable {
    case generic, mild, mixed, ai
    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: return "Only generic"
        case .mild: return "Mild AI"
        case .mixed: return "Mixed AI"
        case .ai: return "Only AI"
        }
    }

    var detail: String {
        switch self {
        case .generic: return "Preset questions only. No AI."
        case .mild: return "Mostly preset, with a few written for you."
        case .mixed: return "Mostly written for you, with a few presets."
        case .ai: return "Only questions written for you."
        }
    }
}

/// You → Questions: which preset categories show, and how much AI is mixed in.
enum QuestionPrefs {
    static let categoriesKey = "questions.categories"
    static let mixKey = "questions.aiMix"
    /// Hold-to-shuffle can run once per this many seconds.
    static let shuffleCooldown: TimeInterval = 30

    /// Empty string = every category.
    static var categories: Set<OpenerCategory> {
        decode(UserDefaults.standard.string(forKey: categoriesKey) ?? "")
    }

    static var mix: AIMix {
        AIMix(rawValue: UserDefaults.standard.string(forKey: mixKey) ?? "") ?? .mild
    }

    static func decode(_ raw: String) -> Set<OpenerCategory> {
        let set = Set(raw.split(separator: ",").compactMap { OpenerCategory(rawValue: String($0)) })
        return set.isEmpty ? Set(OpenerCategory.allCases) : set
    }

    static func encode(_ set: Set<OpenerCategory>) -> String {
        set.count == OpenerCategory.allCases.count ? ""
            : OpenerCategory.allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Changes whenever the AI should write a new set for different categories.
    static var signature: String { encode(categories) }

    /// Extra line handed to the AI so its questions lean toward the chosen kinds.
    static var aiHint: String? {
        let picked = categories
        guard picked.count < OpenerCategory.allCases.count else { return nil }
        let names = OpenerCategory.allCases.filter(picked.contains).map { $0.title.lowercased() }
        return "Style note for the questions (not part of their writing): keep them \(names.joined(separator: ", ")) in tone."
    }

    // MARK: Shuffle cooldown (shared across screens for this launch)

    static var lastShuffle: Date?

    static func shuffleWait(at now: Date = .now) -> TimeInterval {
        guard let lastShuffle else { return 0 }
        return max(0, shuffleCooldown - now.timeIntervalSince(lastShuffle))
    }
}
