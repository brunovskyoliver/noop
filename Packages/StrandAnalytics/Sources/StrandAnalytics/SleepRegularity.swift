import Foundation

// SleepRegularity.swift — the Sleep Regularity Index (Phillips et al. 2017, Sci Rep 7:3216,
// doi:10.1038/s41598-017-03171-4) and every consistency value NOOP derives from it.
//
// SRI = 200 · P(same sleep/wake state at t and t + 24 h) − 100, over every 24 h-separated pair of
// epochs where BOTH states are known. 100 = identical days, 0 = no more alike than chance, −100 = exactly
// inverted. It is computed on ONE epoch vector:
//   • 60 s epochs. An epoch is ASLEEP when its midpoint falls in a recorded sleep session (main sleep OR a
//     nap) and not in one of that session's wake segments (wake after sleep onset counts as wake);
//     otherwise WAKE.
//   • Unknown epochs. The strap reports sleep, not wear, so capture is judged per day window: a window
//     (local 18:00 the evening before to 18:00 on the day) with under `minCapturedSleepSeconds` of recorded
//     sleep is treated as not captured and every epoch in it is UNKNOWN. A pair with either side unknown is
//     excluded, never counted as wake. Limitation: inside a captured window, time off the wrist reads as
//     wake, so an unrecorded daytime nap looks like wakefulness.
//
// Two readouts use it, labelled differently so they are not two readouts of one fact:
//   • "Sleep regularity, 7 days" (Sleep screen, Healthspan): consecutive-day pairs over the 7 windows
//     ending on the day; valid with at least `minPairedSeconds` (120 h) of known pairs. That is the
//     validity rule of Windred et al. 2024 (Sleep 47(1):zsad253, doi:10.1093/sleep/zsad253), who used 7 days
//     of UK Biobank actigraphy and required ≥ 120 h of 24 h-separated epoch pairs after non-wear removal
//     (5 of the 6 possible day pairs).
//   • Rest's "Consistency" (WHOOP's shape, "last 24 h vs the previous 4 days"): tonight's window paired
//     with each of the previous `restPriorDays` windows at a lag of k × 24 h, each pair's agreement A
//     mapped 2A − 1 (the SRI transform) and clamped to 0…1, then averaged; needs `minRestPriorDays` valid
//     prior days (each with ≥ 12 h of known pairs).
// Pairs use an absolute 24 h lag, so a DST change reads as a one-hour shift for one pair.
public enum SleepRegularity {

    public static let epochSeconds = 60
    static let epochsPerDay = 86_400 / epochSeconds
    /// Days in the SRI window (Windred 2024 used 7-day recordings).
    public static let windowDays = 7
    /// Known 24 h-separated pairs needed for a valid SRI (Windred 2024: at least 120 h).
    public static let minPairedSeconds = 120 * 3600
    /// Recorded sleep a day window needs before it counts as captured.
    public static let minCapturedSleepSeconds = 2 * 3600
    /// Rest's consistency: previous days compared, how many must be valid, and the known-pair minimum each.
    public static let restPriorDays = 4
    public static let minRestPriorDays = 2
    public static let minRestPairSeconds = 12 * 3600
    /// Local clock hour each day window starts at (the evening before the day).
    public static let windowStartHour = 18

    /// One recorded sleep period and its wake segments (wake after sleep onset).
    public struct Session: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let wake: [Range<Int>]
        public init(start: Int, end: Int, wake: [Range<Int>] = []) {
            self.start = start; self.end = end; self.wake = wake
        }

        /// From a stored session: its onset/wake times plus the wake segments of an on-device
        /// `[{start,end,stage}]` stage array. The imported minute-dict shape carries no timing, so an
        /// imported night is asleep from onset to wake.
        public init(start: Int, end: Int, stagesJSON: String?) {
            var wake: [Range<Int>] = []
            if let data = stagesJSON?.data(using: .utf8),
               let segs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for seg in segs {
                    guard let name = seg["stage"] as? String, SleepStageVocabulary.isWake(name),
                          let s = (seg["start"] as? NSNumber)?.intValue,
                          let e = (seg["end"] as? NSNumber)?.intValue,
                          min(e, end) > max(s, start) else { continue }
                    wake.append(max(s, start)..<min(e, end))
                }
            }
            self.init(start: start, end: end, wake: wake)
        }
    }

    /// The epoch vector over a run of consecutive day windows: 1 asleep, 0 awake, −1 unknown.
    struct Timeline {
        let days: [String]
        /// Epoch index at which each day's window starts (plus one past the last window).
        let bounds: [Int]
        let state: [Int8]
    }

    /// Start of `day`'s window (local `windowStartHour` on the previous calendar day).
    public static func windowStart(day: String, timeZone: TimeZone) -> Int? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2] - 1,
                                                       hour: windowStartHour)) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    static func dayKey(_ day: String, offset: Int) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2] + offset)) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Build the epoch vector for `first…last` (inclusive day keys).
    static func timeline(first: String, last: String, sessions: [Session], timeZone: TimeZone) -> Timeline? {
        var days: [String] = []
        var d = first
        while d <= last, days.count < 20_000 {
            days.append(d)
            guard let n = dayKey(d, offset: 1) else { return nil }
            d = n
        }
        guard let next = dayKey(last, offset: 1) else { return nil }
        let starts = (days + [next]).compactMap { windowStart(day: $0, timeZone: timeZone) }
        guard starts.count == days.count + 1, let origin = starts.first else { return nil }
        let bounds = starts.map { ($0 - origin) / epochSeconds }
        let n = bounds.last!
        guard n > 0 else { return nil }
        // Asleep mask first, then wake segments, so an overlapping duplicate cannot hide recorded WASO.
        var asleep = [Bool](repeating: false, count: n)
        func mark(_ a: Int, _ b: Int, _ v: Bool) {
            // Epoch e is covered when its midpoint lies in [a, b).
            let lo = max(0, Int(((Double(a - origin) - Double(epochSeconds) / 2) / Double(epochSeconds)).rounded(.up)))
            let hi = min(n, Int(((Double(b - origin) - Double(epochSeconds) / 2) / Double(epochSeconds)).rounded(.up)))
            if lo < hi { for e in lo..<hi { asleep[e] = v } }
        }
        for s in sessions where s.end > s.start { mark(s.start, s.end, true) }
        for s in sessions { for w in s.wake { mark(w.lowerBound, w.upperBound, false) } }
        var state = [Int8](repeating: -1, count: n)
        for i in days.indices {
            let lo = bounds[i], hi = bounds[i + 1]
            var slept = 0
            for e in lo..<hi where asleep[e] { slept += 1 }
            guard slept * epochSeconds >= minCapturedSleepSeconds else { continue }
            for e in lo..<hi { state[e] = asleep[e] ? 1 : 0 }
        }
        return Timeline(days: days, bounds: bounds, state: state)
    }

    /// Agreement over epochs `lo..<hi` against the same epochs `lag` earlier: (same, known pairs).
    static func agreement(_ state: [Int8], _ lo: Int, _ hi: Int, lag: Int) -> (same: Int, known: Int) {
        var same = 0, known = 0
        for e in max(lo, lag)..<max(max(lo, lag), hi) {
            let a = state[e], b = state[e - lag]
            guard a >= 0, b >= 0 else { continue }
            known += 1
            if a == b { same += 1 }
        }
        return (same, known)
    }

    /// The 7-day SRI (−100…100) for every day in `days` that has one. `sessions` should cover the six days
    /// before the first requested day too; days without enough known pairs are absent.
    public static func sri(days: [String], sessions: [Session], timeZone: TimeZone = .current) -> [String: Double] {
        guard let first = days.min(), let last = days.max(),
              let lead = dayKey(first, offset: -(windowDays - 1)),
              let t = timeline(first: lead, last: last, sessions: sessions, timeZone: timeZone) else { return [:] }
        let wanted = Set(days)
        var out: [String: Double] = [:]
        for j in (windowDays - 1)..<t.days.count where wanted.contains(t.days[j]) {
            // Pairs (e − 24 h, e) with both epochs inside the 7 windows ending on day j.
            let r = agreement(t.state, t.bounds[j - windowDays + 1] + epochsPerDay, t.bounds[j + 1], lag: epochsPerDay)
            guard r.known * epochSeconds >= minPairedSeconds else { continue }
            out[t.days[j]] = 200 * Double(r.same) / Double(r.known) - 100
        }
        return out
    }

    /// Rest's consistency credit (0…1) for every day in `days` that has one: tonight's window against
    /// each of the previous `restPriorDays` windows.
    public static func restConsistency(days: [String], sessions: [Session],
                                       timeZone: TimeZone = .current) -> [String: Double] {
        guard let first = days.min(), let last = days.max(),
              let lead = dayKey(first, offset: -restPriorDays),
              let t = timeline(first: lead, last: last, sessions: sessions, timeZone: timeZone) else { return [:] }
        let wanted = Set(days)
        var out: [String: Double] = [:]
        for j in restPriorDays..<t.days.count where wanted.contains(t.days[j]) {
            var credits: [Double] = []
            for k in 1...restPriorDays {
                let r = agreement(t.state, t.bounds[j], t.bounds[j + 1], lag: k * epochsPerDay)
                guard r.known * epochSeconds >= minRestPairSeconds else { continue }
                credits.append(min(1, max(0, 2 * Double(r.same) / Double(r.known) - 1)))
            }
            guard credits.count >= minRestPriorDays else { continue }
            out[t.days[j]] = credits.reduce(0, +) / Double(credits.count)
        }
        return out
    }

    /// THE mapping from SRI to the 0–100 % consistency the Sleep screen and Healthspan show: the SRI
    /// itself, clamped to 0…100. SRI's regular range is already 0 (chance) to 100 (identical days); only an
    /// inverted schedule goes negative, and it is shown as 0. No rescaling was chosen because WHOOP places
    /// its own consistency "a little below" the SRI (longer baseline) and puts its Healthspan break-even at
    /// 70 %, which on the SRI sits at the least-regular quintile boundary of Windred 2024 (71.6); an
    /// identity map keeps that break-even meaningful. It is still an SRI, not WHOOP's consistency scale.
    public static func consistencyPercent(sri: Double) -> Double {
        min(100, max(0, sri))
    }

    /// The consistency % series the Sleep screen and Healthspan read, keyed by day, oldest first. Imported
    /// `sleep_consistency` wins when it covers the newest day (WHOOP's own figure); otherwise the 7-day SRI
    /// through `consistencyPercent`.
    public static func resolve(dayKeys: [String], importedPct: [String: Double],
                               sriByDay: [String: Double]) -> [(day: String, pct: Double)] {
        if let last = dayKeys.last, importedPct[last] != nil {
            return dayKeys.compactMap { d in importedPct[d].map { (day: d, pct: $0) } }
        }
        return sriByDay.keys.sorted().map { (day: $0, pct: consistencyPercent(sri: sriByDay[$0]!)) }
    }
}
