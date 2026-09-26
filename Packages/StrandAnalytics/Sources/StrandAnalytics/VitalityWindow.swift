import Foundation

// VitalityWindow.swift — the 6-month Body Age window and Pace of Aging.
//
// Body Age reads the last 180 days, the window the WHOOP Healthspan white paper (rev. Sep 2025) uses for
// WHOOP Age. Pace of Aging follows the same paper: project Body Age six months ahead assuming the last
// 30 days' averages hold, and compare the projected change with the six months of calendar time. With
// the offsets of both windows known, that reduces to
//
//     pace = (Δ30 + 0.5 − Δ180) / 0.5 = 1 + 2 · (BodyAge30 − BodyAge180)
//
// clamped to the paper's −1…3 scale. 1 = aging at the calendar rate, below 1 = slower, above = faster.
// A factor the recent window lacks keeps its 6-month value, so a gap in the last 30 days reads as
// "unchanged" rather than as a sudden gain or loss.
//
// Pure and deterministic; the Kotlin twin (`VitalityWindow.kt`) must return byte-identical values.
public extension VitalityEngine {

    /// One local day of Vitality inputs. `zone13Min`/`zone45Min` are the day's workout minutes in HR
    /// zones 1–3 and 4–5. `vo2max` is set only on days that carry a VO₂max point (weekly estimate or an
    /// imported measurement).
    struct Day: Equatable, Sendable {
        public var day: String            // yyyy-MM-dd, local
        public var restingHR: Double?
        public var sleepHours: Double?
        public var rmssd: Double?
        public var steps: Double?
        public var vo2max: Double?
        public var zone13Min: Double
        public var zone45Min: Double
        public init(day: String, restingHR: Double? = nil, sleepHours: Double? = nil, rmssd: Double? = nil,
                    steps: Double? = nil, vo2max: Double? = nil, zone13Min: Double = 0, zone45Min: Double = 0) {
            self.day = day; self.restingHR = restingHR; self.sleepHours = sleepHours; self.rmssd = rmssd
            self.steps = steps; self.vo2max = vo2max; self.zone13Min = zone13Min; self.zone45Min = zone45Min
        }
        /// A worn day: any strap- or phone-derived daily value. VO₂max alone does not count (it is weekly).
        var covered: Bool {
            restingHR != nil || sleepHours != nil || rmssd != nil || steps != nil || zone13Min > 0 || zone45Min > 0
        }
    }

    struct Healthspan: Equatable, Sendable {
        public let bodyAge: Result              // the 180-day Body Age
        public let recentBodyAge: Result?       // the 30-day projection (nil without a pace)
        public let paceOfAging: Double?         // −1…3, nil until both windows have enough days
        public let coveredDays: Int
        public let recentCoveredDays: Int
    }

    static let longWindowDays = 180
    static let recentWindowDays = 30
    /// Zone minutes are a weekly rate over worn days; below a week of wear the rate is noise.
    static let minZoneDays = 7
    /// Pace compares two windows, so both must be substantially filled.
    static let minPaceDays = 60
    static let minRecentPaceDays = 14
    static let minPace = -1.0, maxPace = 3.0

    /// Days since 1970-01-01 for a "yyyy-MM-dd" string (proleptic Gregorian, Hinnant's days_from_civil).
    /// Pure integer math so Swift and Kotlin agree without a calendar or time-zone dependency.
    static func epochDay(_ s: String) -> Int? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y0 = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Aggregate a window of days into model inputs: resting HR and HRV are medians (one bad night must
    /// not move them), sleep, steps and VO₂max are means, zone minutes are a per-week rate over worn days.
    /// `days` must already be sorted by day so the floating-point sums run in the same order on both
    /// platforms.
    static func inputs(days: [Day], chronoAge: Double, sex: String) -> Inputs {
        let nights = days.compactMap { $0.sleepHours }.filter { $0 > 0 }
        let worn = days.filter { $0.covered }
        var z13: Double? = nil, z45: Double? = nil
        if worn.count >= minZoneDays {
            let perWeek = 7 / Double(worn.count)
            z13 = worn.reduce(0) { $0 + max(0, $1.zone13Min) } * perWeek
            z45 = worn.reduce(0) { $0 + max(0, $1.zone45Min) } * perWeek
        }
        let vo2 = mean(days.compactMap { $0.vo2max }.filter { $0 > 0 })
        return Inputs(
            chronoAge: chronoAge,
            restingHR: median(days.compactMap { $0.restingHR }.filter { $0 > 0 }),
            vo2max: vo2,
            expectedVO2max: vo2 == nil ? nil : expectedVO2max(age: chronoAge, sex: sex),
            sleepHours: mean(nights),
            sleepConsistency: sleepConsistency(nightlyHours: nights),
            rmssd: median(days.compactMap { $0.rmssd }.filter { $0 > 0 }),
            rmssdNorm: rmssdNorm(forAge: chronoAge),
            steps: mean(days.compactMap { $0.steps }.filter { $0 >= 0 }),
            zone13MinPerWeek: z13, zone45MinPerWeek: z45)
    }

    /// Recent inputs over long ones: every factor the recent window measured replaces the long value.
    static func overlay(_ recent: Inputs, on long: Inputs) -> Inputs {
        var out = long
        if let v = recent.restingHR { out.restingHR = v }
        if let v = recent.vo2max { out.vo2max = v; out.expectedVO2max = recent.expectedVO2max }
        if let v = recent.sleepHours { out.sleepHours = v }
        if let v = recent.sleepConsistency { out.sleepConsistency = v }
        if let v = recent.rmssd { out.rmssd = v }
        if let v = recent.steps { out.steps = v }
        if let a = recent.zone13MinPerWeek, let b = recent.zone45MinPerWeek {
            out.zone13MinPerWeek = a; out.zone45MinPerWeek = b
        }
        return out
    }

    /// Body Age over the 180 days ending at `asOf` (inclusive) plus Pace of Aging from its last 30 days.
    /// nil when the 180-day window has fewer than `minFactors` inputs.
    static func healthspan(days: [Day], asOf: String, chronoAge: Double, sex: String) -> Healthspan? {
        guard let end = epochDay(asOf) else { return nil }
        let dated = days.compactMap { d -> (Int, Day)? in epochDay(d.day).map { ($0, d) } }
            .filter { $0.0 <= end && $0.0 > end - longWindowDays }
            .sorted { $0.0 < $1.0 }
        let long = dated.map { $0.1 }
        let recent = dated.filter { $0.0 > end - recentWindowDays }.map { $0.1 }
        let longInputs = inputs(days: long, chronoAge: chronoAge, sex: sex)
        guard let bodyAge = compute(longInputs) else { return nil }
        let covered = long.filter { $0.covered }.count
        let recentCovered = recent.filter { $0.covered }.count
        var recentResult: Result? = nil
        var pace: Double? = nil
        if covered >= minPaceDays, recentCovered >= minRecentPaceDays {
            let projected = overlay(inputs(days: recent, chronoAge: chronoAge, sex: sex), on: longInputs)
            if let r = compute(projected) {
                recentResult = r
                pace = clamp(1 + 2 * (r.bodyAge - bodyAge.bodyAge), minPace, maxPace)
            }
        }
        return Healthspan(bodyAge: bodyAge, recentBodyAge: recentResult, paceOfAging: pace,
                          coveredDays: covered, recentCoveredDays: recentCovered)
    }

    /// The white paper's four Pace of Aging readings. The display rounds to one decimal, so "steady" is the
    /// band that prints as 1.0×.
    enum PaceBand: String, Sendable { case reversing, slowing, steady, accelerated }

    static func paceBand(_ pace: Double) -> PaceBand {
        if pace < 0 { return .reversing }
        if pace < 0.95 { return .slowing }
        if pace < 1.05 { return .steady }
        return .accelerated
    }

    /// A workout's zone 1–3 and 4–5 minutes from its stored `zonesJSON` (percent of the workout per zone,
    /// keys "z1"…"z5" as written on Apple platforms or "zone1"…"zone5" as written on Android). nil when
    /// the row carries no usable zones.
    static func zoneMinutes(zonesJSON: String?, durationS: Double?) -> (z13: Double, z45: Double)? {
        guard let json = zonesJSON, let dur = durationS, dur > 0,
              let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var pct = [Double](repeating: 0, count: 5)
        for i in 0..<5 {
            let v = (obj["z\(i + 1)"] ?? obj["zone\(i + 1)"]) as? NSNumber
            pct[i] = max(0, v?.doubleValue ?? 0)
        }
        guard pct.contains(where: { $0 > 0 }) else { return nil }
        let minutes = dur / 60
        return (minutes * (pct[0] + pct[1] + pct[2]) / 100, minutes * (pct[3] + pct[4]) / 100)
    }
}
