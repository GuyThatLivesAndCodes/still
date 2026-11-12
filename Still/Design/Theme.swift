import SwiftUI

enum Theme {
    static let bg = Color.black
    static let ink = Color(white: 0.95)
    static let secondary = Color(white: 0.64)
    static let tertiary = Color(white: 0.55)
    static let card = Color(white: 0.06)
    static let hairline = Color.white.opacity(0.09)
    static let accent = Color(red: 0.667, green: 0.706, blue: 0.941)
    /// Anything Quiet AI wrote is purple; preset text stays gray.
    static let ai = Color(red: 0.76, green: 0.62, blue: 1.0)
}

extension View {
    /// Frosted glass surface used for interactive elements.
    func glass(_ radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    /// Quiet solid card used for list content.
    func card(_ radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }

    func sectionLabel() -> some View {
        self.font(.caption.weight(.semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.tertiary)
    }
}

/// Large primary capsule button (white on black).
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.22))
            .background(enabled ? Theme.ink : Color.white.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(enabled ? 0 : 0.06), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(Theme.ink)
            .glass(27)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum Fmt {
    static func period(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    static func entryLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today · \(period(date))" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(period(date))" }
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day) · \(period(date))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Tue, Nov 3 · 9:41 PM", with the year when it isn't this year.
    static func exact(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let day = sameYear
            ? date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        return "\(day) · \(time(date))"
    }

    /// "Opens in 3 days", then hours, minutes, and finally seconds.
    static func opensIn(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.up)))
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if s >= 86400 { return "Opens in " + unit(s / 86400, "day") }
        if s >= 3600 { return "Opens in " + unit(s / 3600, "hour") }
        if s >= 60 { return "Opens in " + unit(s / 60, "minute") }
        return "Opens in " + unit(s, "second")
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func hm(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func timeOfDay(minute: Int) -> String {
        var c = DateComponents()
        c.hour = minute / 60
        c.minute = minute % 60
        let d = Calendar.current.date(from: c) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
}
