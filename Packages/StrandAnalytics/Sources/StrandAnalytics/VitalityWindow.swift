import Foundation

// VitalityWindow.swift — Healthspan v2 windows, gate, weekly cadence and Pace of Aging.
//
// White paper (rev. Sep 2025) rules implemented here:
//   • Broop Age (WHOOP Age) averages the last 6 months (180 days ending on the update day).
//   • Unlock / keep updating only with ≥ 21 scored recoveries (Charge days) in the last 31 days.
//   • Updates weekly on SUNDAY: the value is computed as of that Sunday and stored under its date.
//   • Pace of Aging: project Broop Age six months ahead assuming the last 30 days' averages hold for the
//     next six months, i.e. the 180-day window at +0.5 y consists entirely of that behaviour, evaluated at
//     age + 0.5. pace = (projected − current) / 0.5 = 1 + 2 · (Δprojected − Δcurrent), clamped −1…3.
//     A factor the last 30 days did not measure keeps its 6-month value.
//
// Pure and deterministic. iOS-only fork change: the Kotlin twin (`VitalityWindow.kt`) is intentionally
// not updated.
public extension VitalityEngine {

    /// One local day of inputs. Zone and strength minutes are that day's totals (0 when none);
    /// `vo2max` only on days that carry a VO₂max point; `sleepConsistency` is the Sleep screen's value
    /// for that night (see `SleepConsistency.resolve`); `hasRecovery` marks a scored Charge day.
    struct Day: Equatable, Sendable {
        public var day: String            // yyyy-MM-dd, local
        public var restingHR: Double?
        public var sleepHours: Double?
        public var sleepConsistency: Double?
        public var steps: Double?
        public var vo2max: Double?
        public var zone13Min: Double
        public var zone45Min: Double
        public var strengthMin: Double
        public var hasRecovery: Bool
        public init(day: String, restingHR: Double? = nil, sleepHours: Double? = nil,
                    sleepConsistency: Double? = nil, steps: Double? = nil, vo2max: Double? = nil,
                    zone13Min: Double = 0, zone45Min: Double = 0, strengthMin: Double = 0,
                    hasRecovery: Bool = false) {
            self.day = day; self.restingHR = restingHR; self.sleepHours = sleepHours
            self.sleepConsistency = sleepConsistency; self.steps = steps; self.vo2max = vo2max
            self.zone13Min = zone13Min; self.zone45Min = zone45Min; self.strengthMin = strengthMin
            self.hasRecovery = hasRecovery
        }
        /// A worn / measured day (VO₂max alone does not count: it is weekly).
        var covered: Bool {
            restingHR != nil || sleepHours != nil || steps != nil || hasRecovery
                || zone13Min > 0 || zone45Min > 0 || strengthMin > 0
        }
    }

    /// A dated lean-body-mass reading (percent of body weight).
    struct LeanMassPoint: Equatable, Sendable {
        public var day: String
        public var pct: Double
        public init(day: String, pct: Double) { self.day = day; self.pct = pct }
    }

    struct Healthspan: Equatable, Sendable {
        public let asOf: String
        /// Broop Age over the 180-day window, with its nine impacts.
        public let current: Result
        /// The same model on the last-30-day averages at age + 0.5 (the projection).
        public let projected: Result
        public let paceOfAging: Double
        /// Window-averaged inputs, for the UI's "6 Month avg." / "30 Day avg." markers.
        public let longInputs: Inputs
        public let recentInputs: Inputs
        public let recoveriesLast31: Int
    }

    static let longWindowDays = 180
    static let recentWindowDays = 30
    static let gateWindowDays = 31
    static let gateMinRecoveries = 21
    /// A lean-mass reading older than the window still counts for this long (body composition is
    /// measured rarely).
    static let leanMassCarryDays = 365
    /// Weekly rates need at least a week of span.
    static let minRateSpanDays = 7
    static let minPace = -1.0, maxPace = 3.0
    static let projectionYears = 0.5

    /// Days since 1970-01-01 for a "yyyy-MM-dd" string (proleptic Gregorian, Hinnant's days_from_civil).
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

    /// The Sunday on or before `day` ("yyyy-MM-dd"), or nil for a malformed day. 1970-01-01 was a Thursday,
    /// so (epochDay + 4) mod 7 is the weekday with Sunday = 0.
    static func sundayKey(onOrBefore day: String) -> String? {
        guard let e = epochDay(day) else { return nil }
        let back = ((e + 4) % 7 + 7) % 7
        return HRVStatus.dayString(e - back)
    }

    /// Every Sunday from the first Sunday on/after `from` through the last on/before `to`, ascending.
    static func sundays(from: String, to: String) -> [String] {
        guard let a = epochDay(from), let lastSun = sundayKey(onOrBefore: to), let b = epochDay(lastSun) else { return [] }
        let first = a + ((7 - ((a + 4) % 7 + 7) % 7) % 7)
        guard first <= b else { return [] }
        return stride(from: first, through: b, by: 7).map { HRVStatus.dayString($0) }
    }

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Aggregate a window into model inputs. Daily values are means over the days that carry them; zone and
    /// strength time are weekly totals averaged over the window's span, from the first covered day (so a
    /// new user is not diluted by days before they had a strap) to the window end. `days` must be sorted.
    static func inputs(days: [(epoch: Int, day: Day)], windowEnd: Int, chronoAge: Double, sex: String,
                       leanMass: Double?) -> Inputs {
        let d = days.map(\.day)
        var z13: Double? = nil, z45: Double? = nil, str: Double? = nil
        if let first = days.first(where: { $0.day.covered })?.epoch {
            let span = windowEnd - first + 1
            if span >= minRateSpanDays {
                let perWeek = 7 / Double(span)
                z13 = d.reduce(0) { $0 + max(0, $1.zone13Min) } * perWeek
                z45 = d.reduce(0) { $0 + max(0, $1.zone45Min) } * perWeek
                str = d.reduce(0) { $0 + max(0, $1.strengthMin) } * perWeek
            }
        }
        return Inputs(
            chronoAge: chronoAge, sex: sex,
            sleepHours: mean(d.compactMap { $0.sleepHours }.filter { $0 > 0 }),
            sleepConsistency: mean(d.compactMap { $0.sleepConsistency }.filter { $0 >= 0 }),
            zone13MinPerWeek: z13, zone45MinPerWeek: z45, strengthMinPerWeek: str,
            steps: mean(d.compactMap { $0.steps }.filter { $0 > 0 }),
            vo2max: mean(d.compactMap { $0.vo2max }.filter { $0 > 0 }),
            restingHR: mean(d.compactMap { $0.restingHR }.filter { $0 > 0 }),
            leanMassPct: leanMass)
    }

    /// Recent inputs over long ones: every factor the recent window measured replaces the long value.
    static func overlay(_ recent: Inputs, on long: Inputs) -> Inputs {
        var out = long
        for f in Factor.allCases { if let v = recent.value(f) { out.set(f, v) } }
        return out
    }

    /// Recoveries in the 31 days ending on `asOf` (inclusive).
    static func recoveries(days: [Day], asOf: String) -> Int {
        guard let end = epochDay(asOf) else { return 0 }
        return days.filter { d in
            guard d.hasRecovery, let e = epochDay(d.day) else { return false }
            return e <= end && e > end - gateWindowDays
        }.count
    }

    /// THE resolver: Broop Age + Pace of Aging as of `asOf`. nil when the recovery gate fails
    /// (< 21 recoveries in the last 31 days), the age is unknown, or fewer than `minFactors` inputs exist.
    /// Both the weekly store pass and the screens call this, so they cannot disagree.
    static func healthspan(days: [Day], leanMass: [LeanMassPoint] = [], asOf: String,
                           chronoAge: Double, sex: String) -> Healthspan? {
        guard let end = epochDay(asOf), chronoAge > 0 else { return nil }
        let rec = recoveries(days: days, asOf: asOf)
        guard rec >= gateMinRecoveries else { return nil }
        let dated = days.compactMap { d -> (epoch: Int, day: Day)? in epochDay(d.day).map { ($0, d) } }
            .filter { $0.epoch <= end && $0.epoch > end - longWindowDays }
            .sorted { $0.epoch < $1.epoch }
        let recent = dated.filter { $0.epoch > end - recentWindowDays }
        let lm = leanMass.compactMap { p -> (Int, Double)? in
            guard let e = epochDay(p.day), e <= end, p.pct > 0 else { return nil }
            return (e, p.pct)
        }.sorted { $0.0 < $1.0 }
        let lmLong = mean(lm.filter { $0.0 > end - longWindowDays }.map(\.1))
            ?? lm.last(where: { $0.0 > end - leanMassCarryDays }).map(\.1)
        let lmRecent = mean(lm.filter { $0.0 > end - recentWindowDays }.map(\.1))

        let longIn = inputs(days: dated, windowEnd: end, chronoAge: chronoAge, sex: sex, leanMass: lmLong)
        guard let current = compute(longIn) else { return nil }
        let recentIn = inputs(days: recent, windowEnd: end, chronoAge: chronoAge + projectionYears, sex: sex,
                              leanMass: lmRecent)
        var projIn = overlay(recentIn, on: longIn)
        projIn.chronoAge = chronoAge + projectionYears
        guard let projected = compute(projIn) else { return nil }
        let pace = clamp(1 + (projected.ageDelta - current.ageDelta) / projectionYears, minPace, maxPace)
        return Healthspan(asOf: asOf, current: current, projected: projected, paceOfAging: pace,
                          longInputs: longIn, recentInputs: recentIn, recoveriesLast31: rec)
    }

    /// The white paper's four Pace of Aging readings. The display rounds to one decimal, so "steady" is the
    /// band that prints as 1.0x.
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

    /// Activities that count as strength-activity time: the white paper's list (Strength Trainer,
    /// weightlifting, powerlifting, Barre, Barre3, pilates, yoga, hot yoga, functional fitness, Barry's, F45,
    /// box fitness, HIIT, baby/toddler wearing, rucking, solidcore) mapped onto NOOP's workout catalogue
    /// (`WorkoutCatalog`: "Strength", "Bodybuilding", "Weightlifting", "Powerlifting", "HIIT", "Yoga",
    /// "Pilates", "CrossFit", "Calisthenics", "Boot camp", "Rucking"), the Lift Log / Apple Health lifting
    /// sport "Strength Training", and Apple Health's "Core training". Compared case- and
    /// punctuation-insensitively.
    static let strengthSports: Set<String> = [
        "strength", "strengthtraining", "strengthtrainer", "weightlifting", "powerlifting", "bodybuilding",
        "functionalfitness", "functionalstrengthtraining", "traditionalstrengthtraining", "crossfit",
        "hiit", "highintensityintervaltraining", "pilates", "yoga", "hotyoga", "barre", "barre3",
        "barrys", "f45", "f45training", "boxfitness", "bootcamp", "calisthenics", "coretraining",
        "rucking", "solidcore", "babywearing", "toddlerwearing",
    ]

    static func isStrengthSport(_ sport: String) -> Bool {
        let key = sport.lowercased().filter { $0.isLetter || $0.isNumber }
        return strengthSports.contains(key)
    }
}
