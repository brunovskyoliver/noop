import Foundation

/// The on-device Coach's context budget: when to condense the conversation before a turn.
///
/// The session's context holds the instructions, the tool schemas, every prompt, tool output and reply so
/// far, and the reply being generated. Designed for 4096 tokens; `contextSize` is read at runtime (larger
/// models get more room). On 26.4+ the engine counts with `tokenCount(for:)`; below that it uses the
/// character estimate here (about 3.5 characters per token in Latin scripts, one per CJK character, rounded
/// up so the estimate errs towards condensing early). Pure; unit-tested.
enum CoachTokenBudget {

    /// Room kept free for the reply and the turn's tool output.
    static let replyReserve = 900
    /// Fraction of the context the conversation may fill before the next turn condenses it.
    static let condenseAt = 0.9
    /// The context Apple documents for the on-device model; used when the runtime value is unknown.
    static let designContextSize = 4096

    /// Tokens `text` is likely to use.
    static func estimate(_ text: String) -> Int {
        var cjk = 0, other = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar) { cjk += 1 } else { other += 1 }
        }
        return cjk + Int((Double(other) / 3.5).rounded(.up))
    }

    /// Tokens for a count of Latin-script characters (the running tally of what went into a session).
    static func estimate(latinCharacters: Int) -> Int {
        Int((Double(max(0, latinCharacters)) / 3.5).rounded(.up))
    }

    /// Whether a turn needs the conversation condensed first: what is already in the session plus the new
    /// prompt plus the reply reserve would pass `condenseAt` of the context.
    static func needsCondense(sessionTokens: Int, promptTokens: Int, contextSize: Int) -> Bool {
        let size = contextSize > 0 ? contextSize : designContextSize
        return Double(sessionTokens + promptTokens + replyReserve) > Double(size) * condenseAt
    }

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
    }
}
