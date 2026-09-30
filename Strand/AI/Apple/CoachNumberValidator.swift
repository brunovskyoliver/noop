import Foundation

/// Checks that every number in a Coach reply came from the facts that turn gave the model.
///
/// The on-device model phrases; it must not compute or recall numbers (Apple's own guidance is not to use it
/// for math or facts). Every figure the app states comes from the screens' resolvers, so a reply may only
/// repeat a number that appears in the turn's fact sheet or tool output, rounded the way a display rounds
/// (48.3 may be said as 48, never 48 as 48.3), or a count or time the user typed. Anything else is treated
/// as invented: the engine retries once with a stricter instruction, then shows the facts without the prose.
///
/// Times compare as minutes of the day, so "21:40" and "9:40 PM" are the same fact. A leading sign is ignored
/// because a hyphen between two numbers ("7-9") cannot be told apart from a minus. Markdown list markers
/// ("1. ", "2) ") and digits inside words ("SpO2", "AFM3") are not numbers. Pure; unit-tested.
enum CoachNumberValidator {

    struct Result: Equatable, Sendable {
        /// The reply's numbers with no source, as written.
        let offending: [String]
        var isValid: Bool { offending.isEmpty }
    }

    /// One number or clock time found in text.
    struct Token: Equatable, Sendable {
        let raw: String
        /// Minutes after midnight when the token is a clock time.
        let minuteOfDay: Int?
        let value: Double
        /// Digits after the decimal separator.
        let decimals: Int
    }

    static func validate(reply: String, sources: [String]) -> Result {
        let allowed = sources.flatMap(tokens(in:))
        let allowedTimes = Set(allowed.compactMap(\.minuteOfDay))
        let allowedNumbers = allowed.filter { $0.minuteOfDay == nil }
        var offending: [String] = []
        for t in tokens(in: reply) {
            if let m = t.minuteOfDay {
                if !allowedTimes.contains(m) { offending.append(t.raw) }
            } else if !allowedNumbers.contains(where: { matches(t, $0) }) {
                offending.append(t.raw)
            }
        }
        return Result(offending: offending)
    }

    /// `reply` may state `source` at its own precision: the source rounded to the reply's decimals, and no
    /// more decimals than the source carries.
    static func matches(_ reply: Token, _ source: Token) -> Bool {
        guard reply.decimals <= source.decimals else { return false }
        let scale = pow(10, Double(reply.decimals))
        let rounded = (source.value * scale).rounded(.toNearestOrAwayFromZero) / scale
        return abs(rounded - reply.value) < 1e-9
    }

    // MARK: Tokenising

    private static let timePattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d:.,])(\d{1,2}):(\d{2})(?:\s?([AaPp])\.?\s?[Mm]\.?)?(?![\d:])|(?<![\p{L}\d:.,])(\d{1,2})\s?([AaPp])\.?\s?[Mm]\.?(?![\p{L}])"#)
    private static let numberPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d.,])\d{1,3}(?:[,.\u00A0\u202F]\d{3})+(?![\d])(?![.,]\d)|(?<![\p{L}\d.,])\d+(?:[.,]\d+)?"#)
    private static let listMarker = try! NSRegularExpression(pattern: #"(?m)^\s*\d{1,2}[.)]\s"#)

    static func tokens(in text: String) -> [Token] {
        var masked = text as NSString
        // Mask list markers and clock times first so their digits are not read again as plain numbers.
        for m in listMarker.matches(in: text, range: NSRange(location: 0, length: masked.length)).reversed() {
            masked = masked.replacingCharacters(in: m.range, with: String(repeating: " ", count: m.range.length)) as NSString
        }
        var out: [(Int, Token)] = []
        let times = timePattern.matches(in: masked as String, range: NSRange(location: 0, length: masked.length))
        for m in times {
            let raw = masked.substring(with: m.range)
            if let minute = minuteOfDay(m, in: masked) {
                out.append((m.range.location, Token(raw: raw, minuteOfDay: minute, value: Double(minute), decimals: 0)))
            }
        }
        for m in times.reversed() {
            masked = masked.replacingCharacters(in: m.range, with: String(repeating: " ", count: m.range.length)) as NSString
        }
        for m in numberPattern.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)) {
            let raw = masked.substring(with: m.range)
            if let t = number(raw) { out.append((m.range.location, t)) }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func minuteOfDay(_ m: NSTextCheckingResult, in s: NSString) -> Int? {
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : s.substring(with: r)
        }
        let hour: Int, minute: Int, meridiem: String?
        if let h = group(1).flatMap(Int.init), let mm = group(2).flatMap(Int.init) {
            hour = h; minute = mm; meridiem = group(3)
        } else if let h = group(4).flatMap(Int.init) {
            hour = h; minute = 0; meridiem = group(5)
        } else { return nil }
        guard minute < 60 else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            let pm = meridiem.lowercased() == "p"
            return ((hour % 12) + (pm ? 12 : 0)) * 60 + minute
        }
        guard hour < 24 else { return nil }
        return hour * 60 + minute
    }

    /// A number with its decimals. A separator followed by exactly three digits is digit grouping
    /// ("10,432" steps); the app never prints three decimals, so this cannot eat a real fraction.
    private static func number(_ raw: String) -> Token? {
        let seps: Set<Character> = [",", ".", "\u{00A0}", "\u{202F}"]
        let parts = raw.split(whereSeparator: { seps.contains($0) }).map(String.init)
        if parts.count > 1, parts[0].count <= 3, parts.dropFirst().allSatisfy({ $0.count == 3 }) {
            guard let v = Double(parts.joined()) else { return nil }
            return Token(raw: raw, minuteOfDay: nil, value: v, decimals: 0)
        }
        if parts.count == 2, let v = Double(parts[0] + "." + parts[1]) {
            return Token(raw: raw, minuteOfDay: nil, value: v, decimals: parts[1].count)
        }
        guard parts.count == 1, let v = Double(parts[0]) else { return nil }
        return Token(raw: raw, minuteOfDay: nil, value: v, decimals: 0)
    }
}
