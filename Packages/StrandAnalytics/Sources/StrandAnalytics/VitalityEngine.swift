import Foundation

// VitalityEngine.swift — Healthspan v2: "Broop Age" (Body Age) and its nine age impacts.
//
// An INDEPENDENT reimplementation of the method the WHOOP Healthspan white paper (rev. Sep 2025) describes
// for WHOOP Age. A wellness estimate, not a clinical biological age and not medical advice.
//
//   WHOOP paper: https://assets.ctfassets.net/rbzqg6pelgqa/3ONehqJslbqxI7CQlwGjfT/36429d6f66940e1fd866a772ed5bfc93/WHOOP_2025_White_Paper_Healthspan__6_.pdf
//
// Method (Spiegelhalter 2016 "effective age", BMC Med Inform Decis Mak 16:104,
// doi:10.1186/s12911-016-0342-z, https://pubmed.ncbi.nlm.nih.gov/27496144/):
//
//     Broop Age = chronological age + Σ_i a_i · 10 · ln(HR_i)
//
//   • 10 = 1 / 0.1: the white paper's Gompertz slope, all-cause mortality rising ~10 % per year of age,
//     so one year of age ≈ ln(HR) of 0.1.
//   • HR_i is the all-cause-mortality hazard ratio of the member's value against the HEALTH-OPTIMISED
//     RECOMMENDATION (not the population average): a value exactly at its target has HR = 1 and adds 0.
//     Every curve below is written as C(value) in ln-hazard units and the impact is C(value) − C(target).
//   • a_i are overlap adjustments. WHOOP fits them with an unpublished structural equation model; the
//     values used here are documented in `overlapFactor` / `overlapPairs`.
//
// The nine inputs (white paper Table 1): hours of sleep, sleep consistency, weekly time in HR zones 1–3,
// weekly time in HR zones 4–5, weekly strength-activity time, daily steps, VO₂max, resting HR and lean body
// mass %. HRV is deliberately NOT an input (the white paper does not use it). A missing input contributes 0
// and is reported as missing so the UI can say so instead of showing a value.
//
// iOS-only fork change: the Android twin (`VitalityEngine.kt`) is intentionally NOT updated, so the
// Swift/Kotlin byte-parity oracle for this file no longer applies.
public enum VitalityEngine {

    /// Years of age per unit of ln(hazard): 1 / 0.1 (white paper, Gompertz law).
    public static let yearsPerLnHazard = 10.0
    /// Broop Age is clamped to a sane band (the WHOOP app itself prints "<18.0").
    public static let minBodyAge = 18.0, maxBodyAge = 100.0
    /// The derived 0–100 Vitality number (kept only because the Today / dashboard cards read it): 50 at
    /// "Broop Age = your age", 2.5 points per year younger. Derived from the SAME delta, so it can never
    /// disagree with Broop Age.
    static let vitalityPerYear = 2.5
    /// Honesty gate: at least this many of the nine inputs must be present.
    public static let minFactors = 3

    // MARK: - Factors

    public enum Pillar: String, CaseIterable, Sendable { case sleep, strain, fitness }

    public enum Factor: String, CaseIterable, Sendable {
        case sleepHours, sleepConsistency, zone13, zone45, strength, steps, vo2max, rhr, leanMass

        public var pillar: Pillar {
            switch self {
            case .sleepHours, .sleepConsistency: return .sleep
            case .zone13, .zone45, .strength, .steps: return .strain
            case .vo2max, .rhr, .leanMass: return .fitness
            }
        }
        /// WHOOP's contributor labels.
        public var label: String {
            switch self {
            case .sleepHours: return "Hours of Sleep"
            case .sleepConsistency: return "Sleep Regularity"
            case .zone13: return "Time in HR Zones 1-3 (Weekly)"
            case .zone45: return "Time in HR Zones 4-5 (Weekly)"
            case .strength: return "Strength Activity Time (Weekly)"
            case .steps: return "Steps"
            case .vo2max: return "VO₂ Max"
            case .rhr: return "RHR"
            case .leanMass: return "Lean Body Mass"
            }
        }
        /// Larger value is healthier (false only for resting HR).
        public var higherIsBetter: Bool { self != .rhr }
    }

    /// The nine window-averaged inputs. Units: hours/night, consistency 0–100 %, minutes/week, minutes/week,
    /// minutes/week, steps/day, ml/kg/min, bpm, lean mass % of body weight.
    public struct Inputs: Equatable, Sendable {
        public var chronoAge: Double
        public var sex: String
        public var sleepHours: Double?
        public var sleepConsistency: Double?
        public var zone13MinPerWeek: Double?
        public var zone45MinPerWeek: Double?
        public var strengthMinPerWeek: Double?
        public var steps: Double?
        public var vo2max: Double?
        public var restingHR: Double?
        public var leanMassPct: Double?
        public init(chronoAge: Double, sex: String = "", sleepHours: Double? = nil, sleepConsistency: Double? = nil,
                    zone13MinPerWeek: Double? = nil, zone45MinPerWeek: Double? = nil,
                    strengthMinPerWeek: Double? = nil, steps: Double? = nil, vo2max: Double? = nil,
                    restingHR: Double? = nil, leanMassPct: Double? = nil) {
            self.chronoAge = chronoAge; self.sex = sex; self.sleepHours = sleepHours
            self.sleepConsistency = sleepConsistency; self.zone13MinPerWeek = zone13MinPerWeek
            self.zone45MinPerWeek = zone45MinPerWeek; self.strengthMinPerWeek = strengthMinPerWeek
            self.steps = steps; self.vo2max = vo2max; self.restingHR = restingHR; self.leanMassPct = leanMassPct
        }

        public func value(_ f: Factor) -> Double? {
            switch f {
            case .sleepHours: return sleepHours
            case .sleepConsistency: return sleepConsistency
            case .zone13: return zone13MinPerWeek
            case .zone45: return zone45MinPerWeek
            case .strength: return strengthMinPerWeek
            case .steps: return steps
            case .vo2max: return vo2max
            case .rhr: return restingHR
            case .leanMass: return leanMassPct
            }
        }

        mutating func set(_ f: Factor, _ v: Double?) {
            switch f {
            case .sleepHours: sleepHours = v
            case .sleepConsistency: sleepConsistency = v
            case .zone13: zone13MinPerWeek = v
            case .zone45: zone45MinPerWeek = v
            case .strength: strengthMinPerWeek = v
            case .steps: steps = v
            case .vo2max: vo2max = v
            case .rhr: restingHR = v
            case .leanMass: leanMassPct = v
            }
        }
    }

    /// One factor's age impact. `value` nil = the input is missing and the impact is 0.
    public struct Impact: Equatable, Sendable {
        public let factor: Factor
        public let value: Double?
        public let target: Double
        /// ln(HR) against the target, before the overlap adjustment (0 when missing).
        public let lnHazard: Double
        /// Overlap adjustment a_i (1 = counted in full).
        public let adjustment: Double
        /// Years added (+) or taken off (−) Broop Age: 10 · a_i · ln(HR).
        public let years: Double
        public var isMissing: Bool { value == nil }
    }

    public struct Result: Equatable, Sendable {
        public let chronoAge: Double
        /// Broop Age (WHOOP Age), years, clamped to `minBodyAge…maxBodyAge`.
        public let bodyAge: Double
        /// bodyAge − chronoAge: positive = older than the calendar age.
        public let ageDelta: Double
        /// Derived 0–100 (see `vitalityPerYear`).
        public let vitality: Double
        /// All nine factors, in `Factor.allCases` order; missing ones carry 0 years.
        public let impacts: [Impact]
        public let factorsUsed: Int
        public func impact(_ f: Factor) -> Impact? { impacts.first { $0.factor == f } }
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// Piecewise-linear interpolation through (x, y) knots, flat outside the first/last knot.
    static func interp(_ x: Double, _ k: [(Double, Double)]) -> Double {
        if x <= k[0].0 { return k[0].1 }
        for i in 1..<k.count where x <= k[i].0 {
            let (x0, y0) = k[i - 1], (x1, y1) = k[i]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        }
        return k[k.count - 1].1
    }

    /// Linear ramp from `young` at `a0` to `old` at `a1`, flat outside.
    static func byAge(_ age: Double, _ a0: Double, _ young: Double, _ a1: Double, _ old: Double) -> Double {
        interp(age, [(a0, young), (a1, old)])
    }

    static func bySex(_ sex: String, male: Double, female: Double) -> Double {
        switch sex.lowercased() {
        case "male": return male
        case "female": return female
        default: return (male + female) / 2
        }
    }

    // MARK: - Targets (the health-optimised recommendation: meeting it adds 0 years)

    /// WHOOP's minimum-recommended VO₂max (ml/kg/min) by age, ages 20…100 in 5-year steps (white paper
    /// Fig. 4). Linear between anchors, flat outside 20…100. Other sex values read the mean of the rows.
    static let vo2RecFemale: [Double] = [40, 40, 38, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21, 20, 19, 18]
    static let vo2RecMale: [Double] = [46, 46, 44, 42, 40, 37, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21]

    public static func expectedVO2max(age: Double, sex: String) -> Double {
        func row(_ r: [Double]) -> Double {
            let pos = clamp((age - 20) / 5, 0, Double(r.count - 1))
            let i = Int(pos.rounded(.down))
            if i >= r.count - 1 { return r[r.count - 1] }
            return r[i] + (r[i + 1] - r[i]) * (pos - Double(i))
        }
        return bySex(sex, male: row(vo2RecMale), female: row(vo2RecFemale))
    }

    /// The recommendation for `factor` at `age` / `sex`.
    /// The age ramps below are Broop assumptions; WHOOP does not publish their exact functions.
    /// They must not be described as WHOOP's fitted targets:

    ///   • sleep hours 7 h (white paper: below 7 h adds years);
    ///   • sleep consistency 70 % (white paper: 70 % is neutral);
    ///   • zones 1–3: 100 min/week up to age 30, falling linearly to 70 at 70 (white paper: "70–100, lower
    ///     with age");
    ///   • zones 4–5: 10 min/week up to 30, falling to 7 at 70 (white paper: "7–10, lower with age");
    ///   • strength 40 min/week (white paper: above 40 subtracts years);
    ///   • steps 8,000/day up to 40, falling to 5,600 at 60 (white paper; Paluch 2022 found the curve
    ///     flattens earlier in adults ≥ 60);
    ///   • VO₂max from the Fig. 4 table above;
    ///   • resting HR 60 bpm (male) / 64 (female), the mean for other sex values;
    ///   • lean body mass 80 % (male) / 67 % (female) at 30 (white paper). The paper says the target
    ///     "varies with age" without the table; body fat rises ~1 point per decade in healthy adults, so the
    ///     target falls 0.1 point per year after 30.
    public static func target(_ f: Factor, age: Double, sex: String) -> Double {
        switch f {
        case .sleepHours: return 7
        case .sleepConsistency: return 70
        case .zone13: return byAge(age, 30, 100, 70, 70)
        case .zone45: return byAge(age, 30, 10, 70, 7)
        case .strength: return 40
        case .steps: return byAge(age, 40, 8000, 60, 5600)
        case .vo2max: return expectedVO2max(age: age, sex: sex)
        case .rhr: return bySex(sex, male: 60, female: 64)
        case .leanMass:
            return bySex(sex, male: 80, female: 67) - 0.1 * max(0, age - 30)
        }
    }

    // MARK: - Hazard curves C(value) in ln(HR) units

    /// Hours of sleep. Itani et al. 2017, Sleep Med 32:246-256 (doi:10.1016/j.sleep.2016.08.006,
    /// https://pubmed.ncbi.nlm.nih.gov/27743803/): short sleep RR 1.12 for all-cause mortality, with the
    /// meta-regression showing risk rising linearly below ~6 h. Modelled as ln(1.12) per hour below 7 h,
    /// capped at a 3-hour deficit. Seven hours and above are neutral in this fork, following the
    /// requested 7–9-hour neutral range; no long-sleep penalty is applied.
    static func cSleepHours(_ h: Double) -> Double {
        h < 7 ? log(1.12) * (7 - max(h, 4)) : 0
    }

    /// Sleep consistency %: the 7-day Sleep Regularity Index through `SleepRegularity.consistencyPercent`
    /// (or imported WHOOP consistency). Windred et al. 2024, Sleep 47(1):zsad253 (doi:10.1093/sleep/zsad253),
    /// UK Biobank, n = 60,977, median SRI 81.0 (IQR 73.8–86.3). Fully adjusted all-cause mortality versus the
    /// least regular quintile (SRI < 71.6): HR 0.80 for 71.6–78.6, 0.75 for 78.6–83.2, 0.72 for 83.2–87.3
    /// and 0.70 for 87.3–98.5. Knots sit at each quintile's midpoint (the top one at 90), with HR 1 at
    /// WHOOP's 70 % neutral point, which is the least-regular quintile's upper edge. Windred gives no
    /// gradient inside that bottom quintile, so below 70 the first step's slope (ln 0.80 per 5.1 points) is
    /// extrapolated for 10 points only and held flat under 60 (HR ≈ 1.55 at the floor, close to the
    /// previous cap). Flat above 90.
    static func cConsistency(_ c: Double) -> Double {
        let slope = log(0.80) / 5.1
        return interp(c, [(60, -slope * 10), (70, 0), (75.1, log(0.80)), (80.9, log(0.75)),
                          (85.25, log(0.72)), (90, log(0.70))])
    }

    /// Zones 1–3 min/week (moderate-intensity time). Lee et al. 2022, Circulation 146:523-534
    /// (doi:10.1161/CIRCULATIONAHA.121.058162, https://pubmed.ncbi.nlm.nih.gov/35876019/): long-term
    /// leisure moderate activity at the 150–299 min/week guideline gave 19–25 % lower mortality than none
    /// (HR 0.80 used), 300–599 min/week a further 3–13 % (0.74 used), with the benefit levelling off by
    /// ~600 min/week (0.72). Knots (0, 0), (150, ln 0.80), (300, ln 0.74), (600, ln 0.72), flat beyond, which
    /// is where WHOOP says zone-time benefit stops rising.
    static func cZone13(_ m: Double) -> Double {
        interp(max(0, m), [(0, 0), (150, log(0.80)), (300, log(0.74)), (600, log(0.72))])
    }

    /// Zones 4–5 min/week (vigorous time). Ahmadi et al. 2022, Eur Heart J 43:4801-4814
    /// (doi:10.1093/eurheartj/ehac572, https://pmc.ncbi.nlm.nih.gov/articles/PMC9726449/): the minimum dose,
    /// 15 min/week, HR 0.82 for all-cause mortality; the optimal dose, 53.6 min/week, HR 0.64. Knots (0, 0),
    /// (15, ln 0.82), (53.6, ln 0.64), flat beyond (no evidence of further benefit).
    static func cZone45(_ m: Double) -> Double {
        interp(max(0, m), [(0, 0), (15, log(0.82)), (53.6, log(0.64))])
    }

    /// Strength-activity min/week. Momma et al. 2022, Br J Sports Med 56:755-763
    /// (doi:10.1136/bjsports-2021-105061, https://pubmed.ncbi.nlm.nih.gov/35228201/): J-shaped, maximum
    /// all-cause risk reduction of ~10–20 % at ~30–60 min/week, independent of aerobic activity. Knots
    /// (0, 0), (40, ln 0.88), (60, ln 0.85), (120, ln 0.83). WHOOP caps the curve at 120 min ("no extra
    /// benefit past 2 h") instead of following Momma's upturn, so it is flat beyond 120.
    static func cStrength(_ m: Double) -> Double {
        interp(max(0, m), [(0, 0), (40, log(0.88)), (60, log(0.85)), (120, log(0.83))])
    }

    /// Steps/day. Paluch et al. 2022, Lancet Public Health 7:e219-e228
    /// (doi:10.1016/S2468-2667(21)00302-9, https://pubmed.ncbi.nlm.nih.gov/35247352/): quartile medians
    /// 3,553 / 5,801 / 7,842 / 10,901 steps with HR 1 / 0.60 / 0.55 / 0.47. Knots at those medians; below
    /// 3,553 the first segment's slope continues down to a 2,000-step floor. The benefit plateaus at
    /// 10,901 before age 40 and at 8,000 from 60 (Paluch: risk levels off at 8–10k under 60 and 6–8k over
    /// 60), linear in between.
    static func cSteps(_ s: Double, age: Double) -> Double {
        let plateau = byAge(age, 40, 10_901, 60, 8_000)
        let x = min(max(s, 2_000), plateau)
        let slope0 = log(0.60) / (5_801 - 3_553)
        if x < 3_553 { return slope0 * (x - 3_553) }
        return interp(x, [(3_553, 0), (5_801, log(0.60)), (7_842, log(0.55)), (10_901, log(0.47))])
    }

    /// VO₂max, ml/kg/min. Kodama et al. 2009, JAMA 301:2024-2035 (doi:10.1001/jama.2009.681,
    /// https://pubmed.ncbi.nlm.nih.gov/19454641/): RR 0.87 per 1-MET (3.5 ml/kg/min) higher fitness.
    /// Mandsager et al. 2018, JAMA Netw Open 1:e183605 (doi:10.1001/jamanetworkopen.2018.3605,
    /// https://pubmed.ncbi.nlm.nih.gov/30646252/) shows no upper limit of benefit. Log-linear, clamped to
    /// ±4 MET around the target so one noisy estimate cannot dominate.
    static func cVO2(_ v: Double, target: Double) -> Double {
        -log(0.87) * clamp((target - v) / 3.5, -4, 4)
    }

    /// Resting HR, bpm. Zhang et al. 2016, CMAJ 188:E53-E63 (doi:10.1503/cmaj.150535,
    /// https://pubmed.ncbi.nlm.nih.gov/26598376/): RR 1.09 per +10 bpm. Jensen et al. 2013, Heart 99:882-887
    /// (doi:10.1136/heartjnl-2012-303375, https://pubmed.ncbi.nlm.nih.gov/23595657/) showed resting HR stays
    /// predictive after adjusting for VO₂max, which is why both are kept (with the overlap adjustment).
    /// Clamped to 40–100 bpm.
    static func cRHR(_ r: Double, target: Double) -> Double {
        log(1.09) * (clamp(r, 40, 100) - target) / 10
    }

    /// Lean body mass %. Jayedi et al. 2022, Int J Obes 46:1573-1581 (doi:10.1038/s41366-022-01165-5,
    /// https://pubmed.ncbi.nlm.nih.gov/35717418/): HR 1.11 per +10 % body fat in general adult populations
    /// (lean % = 100 − fat %), but 0.92 (not significant) over 60. Below the target: ln(1.11) per 10 points,
    /// halved after 60. Above it WHOOP gives only "a small reduction": half the slope, capped at 10 points.
    static func cLeanMass(_ l: Double, target: Double, age: Double) -> Double {
        let slope = log(1.11) / 10 * (age >= 60 ? 0.5 : 1)
        if l < target { return slope * (target - max(l, 40)) }
        return -slope * 0.5 * min(l - target, 10)
    }

    /// ln(HR) of `value` against the target, before the overlap adjustment.
    public static func lnHazard(_ f: Factor, value v: Double, age: Double, sex: String) -> Double {
        let t = target(f, age: age, sex: sex)
        switch f {
        case .sleepHours: return cSleepHours(v) - cSleepHours(t)
        case .sleepConsistency: return cConsistency(v) - cConsistency(t)
        case .zone13: return cZone13(v) - cZone13(t)
        case .zone45: return cZone45(v) - cZone45(t)
        case .strength: return cStrength(v) - cStrength(t)
        case .steps: return cSteps(v, age: age) - cSteps(t, age: age)
        case .vo2max: return cVO2(v, target: t)
        case .rhr: return cRHR(v, target: t)
        case .leanMass: return cLeanMass(v, target: t, age: age)
        }
    }

    // MARK: - Overlap

    /// Correlated pairs. WHOOP's SEM adjustment factors are unpublished, so NOOP uses a transparent rule:
    /// within each pair the factor with the SMALLER |impact| is counted at `overlapFactor`, the larger in
    /// full, so one underlying signal is not scored twice.
    ///   • VO₂max ↔ resting HR: NOOP's VO₂max estimate is itself built from resting HR (Uth / Nes), and the
    ///     two share cardiorespiratory physiology (Jensen 2013 found RHR's hazard shrinks after adjusting
    ///     for VO₂max but does not vanish).
    ///   • Steps ↔ zones 1–3: both measure moderate movement volume; step intensity stops predicting
    ///     mortality once total steps are adjusted for (Saint-Maurice 2020, JAMA 323:1151-1160,
    ///     doi:10.1001/jama.2020.1382).
    /// Zones 1–3 vs 4–5 stay independent (Lee 2022 adjusted moderate and vigorous time for each other),
    /// as do strength time (Momma 2022 is independent of aerobic activity) and sleep duration vs regularity
    /// (Windred 2024 adjusted for duration).
    static let overlapPairs: [(Factor, Factor)] = [(.vo2max, .rhr), (.steps, .zone13)]
    public static let overlapFactor = 0.7

    // MARK: - Compute

    /// All nine impacts for `inputs`, missing inputs at 0, overlap adjustments applied.
    public static func impacts(_ inputs: Inputs) -> [Impact] {
        let age = inputs.chronoAge, sex = inputs.sex
        var ln: [Factor: Double] = [:]
        for f in Factor.allCases {
            if let v = inputs.value(f) { ln[f] = lnHazard(f, value: v, age: age, sex: sex) }
        }
        var adj: [Factor: Double] = [:]
        for (a, b) in overlapPairs {
            guard let la = ln[a], let lb = ln[b] else { continue }
            // Ties go to the first of the pair counting in full.
            if abs(lb) <= abs(la) { adj[b] = overlapFactor } else { adj[a] = overlapFactor }
        }
        return Factor.allCases.map { f in
            let l = ln[f] ?? 0, a = adj[f] ?? 1
            return Impact(factor: f, value: inputs.value(f), target: target(f, age: age, sex: sex),
                          lnHazard: l, adjustment: a, years: yearsPerLnHazard * a * l)
        }
    }

    /// Broop Age. nil when the age is unknown or fewer than `minFactors` inputs are present.
    public static func compute(_ inputs: Inputs) -> Result? {
        guard inputs.chronoAge > 0 else { return nil }
        let imp = impacts(inputs)
        let used = imp.filter { !$0.isMissing }.count
        guard used >= minFactors else { return nil }
        let sum = imp.reduce(0) { $0 + $1.years }
        let bodyAge = clamp(inputs.chronoAge + sum, minBodyAge, maxBodyAge)
        let delta = bodyAge - inputs.chronoAge
        return Result(chronoAge: inputs.chronoAge, bodyAge: bodyAge, ageDelta: delta,
                      vitality: clamp(50 - delta * vitalityPerYear, 0, 100),
                      impacts: imp, factorsUsed: used)
    }

    // MARK: - Legacy Rest's duration-regularity input (not a Healthspan input)

    /// Legacy Rest (Rest v2 off) duration regularity (0–1): 1 − coefficient of variation of nightly hours,
    /// clamped; nil under 3 nights. Rest v2 and Healthspan read `SleepRegularity` instead.
    public static func sleepConsistency(nightlyHours: [Double]) -> Double? {
        let xs = nightlyHours.filter { $0 > 0 }
        guard xs.count >= 3 else { return nil }
        let mean = xs.reduce(0, +) / Double(xs.count)
        guard mean > 0 else { return nil }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return clamp(1 - variance.squareRoot() / mean, 0, 1)
    }
}
