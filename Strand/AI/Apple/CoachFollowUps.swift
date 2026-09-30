import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Follow-up chips written by Apple Intelligence after a Coach reply: short questions the person might ask
/// next, about the reply they just read. Written on-device in a separate session, so the chat's own context
/// is not spent on them. Anything the cleaner rejects falls back to `AICoachEngine.followUpSuggestions`.
enum CoachFollowUps {

    /// Instructions for the follow-up session. App-authored; the reply goes in the prompt.
    static let instructions = """
        You suggest what a person might ask their wellness coach next, inside a sleep and fitness wearable \
        app. The coach can look up sleep, Rest, Charge (recovery), Effort (strain), HRV, heart rate, stress, \
        energy, steps, tonight's sleep plan and the person's journal. Write each suggestion as the person \
        would type it to the coach, using "I" and "my", never "your": a short question, at most eight \
        words. Each one follows from the coach's last answer and asks something different: one digs deeper \
        into it, one connects it to another measure the coach can look up, one asks what to do today or \
        tonight. No numbers. Nothing about diagnoses, medication \
        or supplements.
        """

    static let maxCount = 3
    static let maxWords = 9
    static let maxCharacters = 60

    /// The prompt: the question and the coach's reply, trimmed so the request stays small.
    static func prompt(question: String, reply: String) -> String {
        "The person asked: \(question.prefix(300))\n\nThe coach answered: \(reply.prefix(1200))\n\nSuggest three follow-up questions."
    }

    /// The chips to show, or nil when fewer than two survive. Drops empty, over-long and duplicate
    /// suggestions, any with a digit (a chip is sent as the next question, so a number in it would be a number
    /// the model made up), any repeating the question just asked, and any in the coach's voice ("your HRV":
    /// the chip is sent as the person's own words). Adds a missing question mark. Pure; unit-tested.
    static func clean(_ raw: [String], asked: String) -> [String]? {
        var seen: Set<String> = [key(asked)]
        var out: [String] = []
        for s in raw {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”'‘’-•*")))
            guard !t.isEmpty, t.count <= maxCharacters, !t.contains(where: \.isNumber),
                  t.split(whereSeparator: \.isWhitespace).count <= maxWords, !coachVoice(t) else { continue }
            if let first = t.first, first.isLowercase { t = first.uppercased() + t.dropFirst() }
            if let last = t.last, !".?!".contains(last) { t += "?" }
            guard seen.insert(key(t)).inserted else { continue }
            out.append(t)
            if out.count == maxCount { break }
        }
        return out.count >= 2 ? out : nil
    }

    /// Addressed to the person rather than written by them. English only, as the Coach's strings are.
    private static func coachVoice(_ s: String) -> Bool {
        s.lowercased().split { !$0.isLetter && $0 != "’" && $0 != "'" }.contains {
            ["your", "yours", "yourself", "you’re", "you're"].contains(String($0))
        }
    }

    private static func key(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachFollowUpDraft {
    @Guide(description: "Three short follow-up questions the person might ask next, each at most eight words, no numbers",
           .count(3))
    var questions: [String]
}
#endif
