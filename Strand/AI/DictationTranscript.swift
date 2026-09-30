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
    /// Finished utterances, oldest first.
    private(set) var utterances: [String] = []
    private(set) var current = ""

    /// The text to show: finished utterances, then the one in progress.
    var text: String { (utterances + [current]).filter { !$0.isEmpty }.joined(separator: " ") }

    /// Take one recognition result; returns the text to show.
    @discardableResult
    mutating func update(_ result: String, utteranceEnded: Bool) -> String {
        let next = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !next.isEmpty {
            if current.isEmpty, let last = utterances.last, Self.continues(previous: last, next: next) {
                // The recognizer is still revising the utterance it marked finished (an end marker on a
                // partial result): take it back rather than repeat it.
                utterances.removeLast()
            } else if !current.isEmpty, Self.startsNewUtterance(previous: current, next: next) {
                utterances.append(current)
            }
            current = next
        }
        if utteranceEnded, !current.isEmpty {
            utterances.append(current)
            current = ""
        }
        return text
    }

    static func startsNewUtterance(previous: String, next: String) -> Bool {
        let p = words(previous), n = words(next)
        guard let pf = p.first, let nf = n.first else { return false }
        return pf != nf && n.count < p.count
    }

    /// `next` is the same utterance as `previous`, carried on: it repeats all of it, or its first two words
    /// and at least as many words.
    static func continues(previous: String, next: String) -> Bool {
        let p = words(previous), n = words(next)
        guard !p.isEmpty, n.count >= p.count else { return false }
        if Array(n.prefix(p.count)) == p { return true }
        return p.count >= 2 && Array(n.prefix(2)) == Array(p.prefix(2))
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.map(String.init)
    }
}

/// Which speech-recognition locale to use for the person's locale. The raw locale can carry extensions the
/// recognizer does not match ("en_US@rg=skzzzz": English with a Slovak region setting), for which it reported
/// no on-device speech. Picks, from the recognizer's supported identifiers: the same language and region,
/// then the same language (its US or GB variant first for English), else nil. Pure; unit-tested.
enum DictationLocale {
    static func pick(language: String?, region: String?, supported: [String]) -> String? {
        guard let language = language?.lowercased() else { return nil }
        let parsed = supported.map { id -> (id: String, lang: String, region: String?) in
            let parts = id.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            return (id, parts.first?.lowercased() ?? "", parts.count > 1 ? parts[1].uppercased() : nil)
        }
        let same = parsed.filter { $0.lang == language }
        if let region = region?.uppercased(), let exact = same.first(where: { $0.region == region }) { return exact.id }
        for preferred in ["US", "GB"] where language == "en" {
            if let hit = same.first(where: { $0.region == preferred }) { return hit.id }
        }
        return same.sorted { $0.id < $1.id }.first?.id
    }
}
