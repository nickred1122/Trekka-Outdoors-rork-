import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a short summary of the athlete's week using Apple Intelligence,
/// entirely on the device.
///
/// Two rules shape this whole file. First, the model is never asked to do
/// arithmetic or to look at raw training data — it is handed sentences that
/// `InsightEngine` has already worked out, and asked only to join them up. The
/// on-device model is small, and a fitness app that invents a distance you did
/// not run is worse than one that says nothing.
///
/// Second, the output is checked before it is shown: any number in the summary
/// that does not appear in the facts means the model made something up, and the
/// summary is discarded. The figures below it are computed and always correct,
/// so losing the prose costs nothing.
@Observable
final class IntelligenceService {
    enum Availability: Equatable {
        case checking
        case ready
        /// Available in principle, but not right now — with a reason worth showing.
        case unavailable(String)

        var isReady: Bool { self == .ready }
    }

    private(set) var availability: Availability = .checking
    private(set) var summary: String?
    private(set) var isWorking = false
    /// Set when the model produced something that failed the numbers check, so
    /// the card can be honest instead of silently showing nothing.
    private(set) var wasDiscarded = false

    /// The facts the current summary was written from, so it is not regenerated
    /// on every redraw.
    private var lastFacts: [String] = []

    // MARK: - Availability

    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .unavailable("A written summary needs iOS 26.")
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .ready
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                availability = .unavailable("Turn on Apple Intelligence in Settings for a written summary.")
            case .modelNotReady:
                availability = .unavailable("Apple Intelligence is still setting itself up.")
            case .deviceNotEligible:
                availability = .unavailable("This iPhone doesn't support Apple Intelligence.")
            @unknown default:
                availability = .unavailable("Apple Intelligence isn't available right now.")
            }
        @unknown default:
            availability = .unavailable("Apple Intelligence isn't available right now.")
        }
        #else
        availability = .unavailable("A written summary needs iOS 26.")
        #endif
    }

    // MARK: - Summarising

    /// Writes a summary of the supplied facts, if the device can.
    ///
    /// - Parameter force: regenerate even when these facts were already summarised.
    func summarise(facts: [String], force: Bool = false) async {
        guard !facts.isEmpty else {
            summary = nil
            return
        }
        guard availability.isReady, !isWorking else { return }
        guard force || facts != lastFacts || summary == nil else { return }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }

        isWorking = true
        wasDiscarded = false
        defer { isWorking = false }

        let session = LanguageModelSession {
            "You summarise a person's own training week inside a hiking and running app."
            "You will be given facts already calculated from their recorded workouts and Apple Health."
            "Write two short sentences, at most 40 words in total."
            "DO NOT invent or calculate any number, distance, duration, date or heart rate that is not in the facts."
            "DO NOT give medical, dietary or injury advice."
            "DO NOT use bullet points, headings, emoji or exclamation marks."
            "Write plainly, in the second person, as a level-headed coach would."
        }

        do {
            let response = try await session.respond(
                to: Prompt {
                    "Here are the facts about this person's last seven days:"
                    facts.joined(separator: "\n")
                    "Summarise how their week is going."
                },
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 160)
            )

            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            guard Self.usesOnlyKnownNumbers(in: text, facts: facts) else {
                // The model produced a figure that is not in the source data.
                // There is no safe way to show that in a fitness app.
                summary = nil
                wasDiscarded = true
                lastFacts = facts
                return
            }

            summary = text
            lastFacts = facts
        } catch {
            // A failed summary is not worth interrupting anyone for — the
            // computed figures below it are the substance of the card.
            summary = nil
        }
        #endif
    }

    func clear() {
        summary = nil
        lastFacts = []
        wasDiscarded = false
    }

    // MARK: - Verification

    /// True when every number in `text` also appears in the source facts.
    ///
    /// This is what stands between a small language model and a confidently
    /// wrong training figure. Digits are compared rather than words, so a model
    /// writing "three sessions" where the facts say "3 sessions" is accepted,
    /// while one writing "12.4 km" that appears nowhere is not.
    static func usesOnlyKnownNumbers(in text: String, facts: [String]) -> Bool {
        let known = numbers(in: facts.joined(separator: " "))
        return numbers(in: text).isSubset(of: known)
    }

    private static func numbers(in text: String) -> Set<String> {
        var found: Set<String> = []
        var current = ""

        func flush() {
            var trimmed = current
            while let last = trimmed.last, last == "." || last == "," {
                trimmed.removeLast()
            }
            if !trimmed.isEmpty {
                // Held without its separator so "1.5" and "1,5" are the same
                // number written two ways rather than two different claims.
                found.insert(trimmed.replacingOccurrences(of: ",", with: "."))
            }
            current = ""
        }

        for character in text {
            if character.isNumber || ((character == "." || character == ",") && !current.isEmpty) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }
}
