import Foundation

/// Kinds of preset prompts. You -> Questions picks which ones show above the composer.
enum OpenerCategory: String, CaseIterable, Identifiable, Codable {
    case casual
    case deep
    case emotional
    case gratitude
    case growth
    case mindful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: return "Casual"
        case .deep: return "Deep"
        case .emotional: return "Emotional"
        case .gratitude: return "Gratitude"
        case .growth: return "Growth"
        case .mindful: return "Mindful"
        }
    }

    var blurb: String {
        switch self {
        case .casual: return "Light, everyday check-ins"
        case .deep: return "Bigger, more honest questions"
        case .emotional: return "How you're feeling"
        case .gratitude: return "What's good right now"
        case .growth: return "Change, lessons and letting go"
        case .mindful: return "Your body, energy and rest"
        }
    }

    var icon: String {
        switch self {
        case .casual: return "cup.and.saucer"
        case .deep: return "water.waves"
        case .emotional: return "heart"
        case .gratitude: return "leaf"
        case .growth: return "arrow.up.forward"
        case .mindful: return "wind"
        }
    }
}

/// Quiet, open-ended lines shown above the composer while someone is thinking.
/// These are the starter set: new users always see them, and personalised
/// openers (from the AI) are mixed in depending on You -> Questions.
enum Openers {
    static let catalog: [OpenerCategory: [String]] = [
        .casual: [
            "How's your day going so far?",
            "What made you smile recently?",
            "What are you looking forward to?",
            "What surprised you this week?",
            "What's a small win from today?",
            "If today had a title, what would it be?",
            "What's the first thing you thought about this morning?",
            "What moment from today would you replay?",
            "What's been easier than you expected?",
            "What did you notice today that others might have missed?",
            "What's the best thing you ate today?",
            "What song fits your mood right now?",
            "What's something small that went right today?",
            "What did you spend most of today doing?",
            "Who did you talk to today, and how was it?",
            "What's one thing you'd do tomorrow just for fun?",
        ],
        .deep: [
            "What would you say if no one would ever read it?",
            "What are you avoiding thinking about?",
            "What's something you haven't said out loud?",
            "What conversation keeps replaying in your head?",
            "What decision is sitting in front of you?",
            "What's the honest answer to \"how are you?\"",
            "What feeling is hiding under the obvious one?",
            "What are you afraid might happen?",
            "What's taking up the most space in your head?",
            "What do you believe now that you didn't a year ago?",
            "What part of yourself do you hide most often?",
        ],
        .emotional: [
            "What's on your mind right now?",
            "What are you carrying today?",
            "What's been quietly bothering you?",
            "What's the loudest feeling right now?",
            "What feels heavy, and what feels light?",
            "What's making you restless?",
            "What's keeping you up, or waking you up?",
            "Who's been on your mind lately?",
            "What do you wish someone had asked you today?",
            "What would you tell a friend feeling the way you do?",
        ],
        .gratitude: [
            "What are you grateful for in this moment?",
            "What are you proud of, even a little?",
            "What's something kind you did, or someone did for you?",
            "What do you want to remember about today?",
            "Who made today a little better?",
            "What's something you'd miss if it were gone tomorrow?",
            "What's a comfort you're thankful for lately?",
        ],
        .growth: [
            "What's one thing you'd like to let go of?",
            "What would make tomorrow a bit easier?",
            "What did you learn about yourself recently?",
            "What's changed since last week?",
            "What do you wish you'd done differently?",
            "What's something you're ready to forgive?",
            "What's unfinished that keeps tugging at you?",
            "What are you still waiting on?",
            "What's been harder than you expected?",
            "What are you hoping might happen?",
            "What do you want the rest of this week to hold?",
            "What would you say to yourself five days from now?",
        ],
        .mindful: [
            "How does your body feel right now?",
            "Where did your energy go today?",
            "What do you need more of right now?",
            "What do you need less of right now?",
            "What does rest look like for you right now?",
            "What can you hear, see and feel right now?",
            "What would a slow evening look like tonight?",
        ],
    ]

    /// Every preset prompt.
    static let starter: [String] = OpenerCategory.allCases.flatMap { catalog[$0] ?? [] }

    /// Preset prompts from the chosen categories (all of them if none are chosen).
    static func starter(in categories: Set<OpenerCategory>) -> [String] {
        let picked = categories.isEmpty ? Set(OpenerCategory.allCases) : categories
        return OpenerCategory.allCases.filter(picked.contains).flatMap { catalog[$0] ?? [] }
    }

    /// Short enough to fit small widgets and complications in two lines.
    static let compact: [String] = starter.filter { $0.count <= 34 }

    /// A stable pick for a calendar day, for widgets and complications.
    static func forDay(_ date: Date) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return compact[day % compact.count]
    }
}
