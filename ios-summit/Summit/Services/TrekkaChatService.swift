import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// One turn of the conversation.
nonisolated struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Speaker: Hashable, Sendable {
        case athlete
        case trekka
    }

    var id: UUID = UUID()
    var speaker: Speaker
    var text: String
    var date: Date = .now
    /// True when Trekka declined to answer rather than answering. Shown
    /// differently, because "I don't have that" is not the same kind of reply as
    /// an answer and should not be mistaken for one.
    var isDeclined: Bool = false
}

/// Trekka's assistant: a conversation about the athlete's own training, run
/// entirely on the device.
///
/// Three rules shape this file, and they are the reason it is worth having at
/// all.
///
/// It answers from facts, not from data. Every question is answered against a
/// list of sentences Trekka has already worked out from recorded workouts and
/// Apple Health — the model never sees a raw workout and is never asked to do
/// arithmetic. The on-device model is small, and a training app that invents a
/// distance is worse than one that says nothing.
///
/// Every answer is checked before it is shown: a number that does not appear in
/// the facts means the model made it up, and the reply is replaced with an
/// honest refusal rather than published.
///
/// And nothing leaves the phone. This is Apple's on-device model, so the
/// athlete's health data stays where the rest of Trekka keeps it — which is the
/// only basis on which an app like this should be answering questions about
/// somebody's sleep.
@Observable
final class TrekkaChatService {
    enum Availability: Equatable {
        case checking
        case ready
        case unavailable(String)

        var isReady: Bool { self == .ready }
    }

    private static let enabledKey = "assistant.enabled.v1"

    /// Whether the assistant appears at all. On by default, and one switch away
    /// from gone — bubble included.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { clear() }
        }
    }

    private(set) var availability: Availability = .checking
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var hasConversation: Bool { !messages.isEmpty }

    // MARK: - Availability

    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .unavailable("Talking to Trekka needs iOS 26.")
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .ready
        case let .unavailable(reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                availability = .unavailable("Turn on Apple Intelligence in Settings to talk to Trekka.")
            case .modelNotReady:
                availability = .unavailable("Apple Intelligence is still setting itself up.")
            case .deviceNotEligible:
                availability = .unavailable("This iPhone doesn't support Apple Intelligence, so Trekka can't hold a conversation on it.")
            @unknown default:
                availability = .unavailable("Apple Intelligence isn't available right now.")
            }
        @unknown default:
            availability = .unavailable("Apple Intelligence isn't available right now.")
        }
        #else
        availability = .unavailable("Talking to Trekka needs iOS 26.")
        #endif
    }

    // MARK: - Asking

    /// Puts a question to Trekka.
    ///
    /// - Parameters:
    ///   - question: what the athlete typed.
    ///   - facts: sentences already computed from their own recorded data. This
    ///     is the entire world the answer may draw on.
    ///   - name: what to call them, or empty.
    func ask(_ question: String, facts: [String], name: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(speaker: .athlete, text: trimmed))

        guard availability.isReady else {
            appendDecline("Trekka can't answer on this device right now.")
            return
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            appendDecline("Trekka can't answer on this device right now.")
            return
        }

        isThinking = true
        defer { isThinking = false }

        let history = recentTranscript()
        let session = LanguageModelSession {
            "You are Trekka, the assistant inside a hiking, running and training app, talking to the person whose own data this is."
            "You will be given facts already calculated from their recorded workouts, Apple Health and food diary. Those facts are the only information you have about them."
            "Answer in two to four short sentences, plainly, in the second person, as a level-headed coach would."
            "DO NOT state any number, distance, duration, pace, date or heart rate that does not appear in the facts."
            "If the facts do not answer the question, say so plainly and say what you do have instead. Never guess."
            "DO NOT give medical, diagnostic or injury advice, and do not prescribe a diet. For anything of that kind, say it is worth asking a doctor or a qualified coach."
            "DO NOT use bullet points, headings, emoji or exclamation marks."
            if !name.isEmpty {
                "The person is called \(name). You may use their name occasionally, at most once per answer."
            }
        }

        do {
            let response = try await session.respond(
                to: Prompt {
                    "Facts about this person, as of today:"
                    facts.isEmpty ? "There is no recorded training or health data yet." : facts.joined(separator: "\n")
                    if !history.isEmpty {
                        "The conversation so far:"
                        history
                    }
                    "Their question:"
                    trimmed
                },
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 260)
            )

            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                appendDecline("Trekka couldn't put an answer together for that one.")
                return
            }

            guard IntelligenceService.usesOnlyKnownNumbers(in: text, facts: facts + [trimmed]) else {
                // A figure appeared that is in none of the athlete's own data.
                // There is no safe way to show that in a training app, so the
                // answer is thrown away rather than published with a caveat.
                appendDecline("Trekka started quoting a figure it can't back up from your own data, so it stopped. Ask again in a different way, or check the number on its own screen.")
                return
            }

            messages.append(ChatMessage(speaker: .trekka, text: text))
        } catch {
            EventLog.shared.warning("Assistant", "Answer failed", detail: error.localizedDescription)
            appendDecline("Trekka couldn't answer that just now.")
        }
        #else
        appendDecline("Trekka can't answer on this device right now.")
        #endif
    }

    func clear() {
        messages = []
    }

    private func appendDecline(_ text: String) {
        messages.append(ChatMessage(speaker: .trekka, text: text, isDeclined: true))
    }

    /// The last few turns, so a follow-up question makes sense without handing
    /// the model the whole conversation to wander through.
    private func recentTranscript() -> String {
        messages
            .dropLast()
            .suffix(6)
            .map { "\($0.speaker == .athlete ? "Them" : "You"): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Openers offered on an empty conversation, chosen to match what Trekka can
    /// actually answer from the facts it holds.
    static let suggestions: [String] = [
        "How has my week gone?",
        "Am I training more or less than usual?",
        "How was my sleep?",
        "What should I make of my readiness today?",
    ]
}
