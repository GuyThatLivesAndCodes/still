import Foundation

/// Quiet, open-ended lines shown above the composer while someone is thinking.
/// These are the starter set: new users always see them, and personalised
/// openers (later, from the AI) are mixed in ahead of them.
enum Openers {
    static let starter: [String] = [
        "What's on your mind right now?",
        "How's your day going so far?",
        "What's taking up the most space in your head?",
        "What are you carrying today?",
        "What do you wish someone had asked you today?",
        "What are you looking forward to?",
        "What's been quietly bothering you?",
        "What made you smile recently?",
        "What would you say if no one would ever read it?",
        "What are you avoiding thinking about?",
        "How does your body feel right now?",
        "What's one thing you'd like to let go of?",
        "Who's been on your mind lately?",
        "What surprised you this week?",
        "What are you proud of, even a little?",
        "What's the loudest feeling right now?",
        "What would make tomorrow a bit easier?",
        "What did you notice today that others might have missed?",
        "What are you grateful for in this moment?",
        "What's something you haven't said out loud?",
        "What's keeping you up, or waking you up?",
        "What do you need more of right now?",
        "What do you need less of right now?",
        "Where did your energy go today?",
        "What's a small win from today?",
        "What's unfinished that keeps tugging at you?",
        "If today had a title, what would it be?",
        "What are you afraid might happen?",
        "What are you hoping might happen?",
        "What conversation keeps replaying in your head?",
        "What does rest look like for you right now?",
        "What did you learn about yourself recently?",
        "What's changed since last week?",
        "What would you tell a friend feeling the way you do?",
        "What's the first thing you thought about this morning?",
        "What are you still waiting on?",
        "What's been easier than you expected?",
        "What's been harder than you expected?",
        "What do you want to remember about today?",
        "What's something you're ready to forgive?",
        "What decision is sitting in front of you?",
        "What's the honest answer to \"how are you?\"",
        "What moment from today would you replay?",
        "What do you wish you'd done differently?",
        "What's something kind you did, or someone did for you?",
        "What's making you restless?",
        "What feels heavy, and what feels light?",
        "What do you want the rest of this week to hold?",
        "What would you say to yourself five days from now?",
        "What feeling is hiding under the obvious one?",
    ]

    /// Short enough to fit small widgets and complications in two lines.
    static let compact: [String] = starter.filter { $0.count <= 34 }

    /// A stable pick for a calendar day, for widgets and complications.
    static func forDay(_ date: Date) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return compact[day % compact.count]
    }
}
