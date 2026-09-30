import Foundation

/// The whole transcript of one dictation session, across pauses.
///
/// iOS's on-device recognizer starts a new utterance after a pause of a second or two, and the results that
/// follow carry only the new words. Passing each result straight to a text field replaced everything said
/// before the pause. This keeps the finished utterances and appends the one in progress. An utterance ends
/// when the recognizer says so (`utteranceEnded`, from `speechRecognitionMetadata`) or, as a fallback, when
/// a result no longer continues the previous one: a different first word and fewer words, which a
/// revision of the same utterance does not produce. Pure; unit-tested.
struct DictationTranscript: Equatable, Sendable {
    private(set) var committed = ""
    private(set) var current = ""

    /// The text to show: finished utterances, then the one in progress.
    var text: String { Self.join(committed, current) }

    /// Take one recognition result; returns the text to show.
    @discardableResult
    mutating func update(_ result: String, utteranceEnded: Bool) -> String {
        let next = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !next.isEmpty, Self.startsNewUtterance(previous: current, next: next) {
            committed = Self.join(committed, current)
        }
        current = next
        if utteranceEnded {
            committed = Self.join(committed, current)
            current = ""
        }
        return text
    }

    static func startsNewUtterance(previous: String, next: String) -> Bool {
        let p = words(previous), n = words(next)
        guard let pf = p.first, let nf = n.first else { return false }
        return pf != nf && n.count < p.count
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.map(String.init)
    }

    private static func join(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}
