import Foundation
import Observation

/// What Trekka calls the athlete.
///
/// A name and nothing else. There is no account, no birthday and no sex here,
/// because nothing in the app needs them — every number comes from Apple Health
/// or from a recorded workout, so asking for a profile would be collecting
/// personal detail for decoration.
@Observable
final class ProfileSettings {
    private static let storageKey = "profile.name.v1"
    /// Long enough for a real name, short enough not to break a dashboard header.
    private static let maximumLength = 24

    private(set) var name: String

    init() {
        name = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
    }

    var hasName: Bool { !name.isEmpty }

    /// What a greeting uses. "Alex Fitzgerald-Moore" becomes "Alex".
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Cleans and stores a typed name. Whitespace is collapsed rather than
    /// rejected, so a stray double space never turns into a validation error.
    func setName(_ value: String) {
        let cleaned = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .prefix(Self.maximumLength)
        let trimmed = String(cleaned)
        guard trimmed != name else { return }
        name = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.storageKey)
        }
    }

    func clear() { setName("") }

    /// "Good morning, Alex" — or just "Good morning" when there is no name.
    func greeting(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        case 18..<22: part = "Good evening"
        // Small hours: somebody up at 3am does not need to be told it is a good
        // night, and an alpine start deserves better than "good evening".
        default: part = "Still up"
        }
        return hasName ? "\(part), \(firstName)" : part
    }

    /// The greeting a typed name would produce, before it has been saved — so
    /// first run can show the result while the athlete is still typing it.
    static func preview(greetingFor name: String, at date: Date = .now) -> String {
        let first = name
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<18: part = "Good afternoon"
        case 18..<22: part = "Good evening"
        default: part = "Still up"
        }
        return first.isEmpty ? part : "\(part), \(first)"
    }

    /// A possessive for headings, e.g. "Alex's week". Falls back to "Your week".
    func possessive(_ noun: String) -> String {
        guard hasName else { return "Your \(noun)" }
        let suffix = firstName.lowercased().hasSuffix("s") ? "'" : "'s"
        return "\(firstName)\(suffix) \(noun)"
    }
}
