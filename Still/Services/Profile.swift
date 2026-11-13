import Foundation

enum Gender: String, CaseIterable, Identifiable {
    case unset, male, female, other, preferNot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unset: return "Not set"
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        case .preferNot: return "Prefer not to say"
        }
    }

    static var choices: [Gender] { [.male, .female, .other, .preferNot] }
}

/// What the person tells still. about themselves. Stays on this iPhone and is
/// only handed to Quiet AI so its words fit them better.
enum Profile {
    static let nameKey = "profile.name"
    static let birthdayKey = "profile.birthday"
    static let genderKey = "profile.gender"
    static let genderOtherKey = "profile.genderOther"

    private static var defaults: UserDefaults { .standard }

    static var name: String {
        (defaults.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var birthday: Date? {
        let t = defaults.double(forKey: birthdayKey)
        return t == 0 ? nil : Date(timeIntervalSince1970: t)
    }

    static var gender: Gender { Gender(rawValue: defaults.string(forKey: genderKey) ?? "") ?? .unset }

    static var genderOther: String {
        (defaults.string(forKey: genderOtherKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var age: Int? {
        guard let birthday else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0
        return (5...120).contains(years) ? years : nil
    }

    static var isEmpty: Bool { name.isEmpty && birthday == nil && gender == .unset }

    /// One short paragraph for the model. Empty when nothing is set.
    static var context: String {
        var parts: [String] = []
        if !name.isEmpty { parts.append("They go by \(String(name.prefix(40))).") }
        if let age { parts.append("They are \(age) years old.") }
        switch gender {
        case .male: parts.append("They are male.")
        case .female: parts.append("They are female.")
        case .other where !genderOther.isEmpty: parts.append("Their gender: \(String(genderOther.prefix(30))).")
        default: break
        }
        guard !parts.isEmpty else { return "" }
        return "About the person (only to fit your tone and wording; don't comment on it): " + parts.joined(separator: " ")
    }
}
