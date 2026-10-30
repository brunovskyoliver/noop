import XCTest
@testable import StrandAnalytics

/// Healthspan v2 (Broop Age / WHOOP-Age method). The Android twins use this same model;
/// the shared curve oracle below and HealthspanV2ParityTest pin both implementations.
final class HealthspanV2Tests: XCTestCase {

    typealias VE = VitalityEngine
    private let ln = { (x: Double) in Foundation.log(x) }

    /// Every input exactly at its recommendation.
    private func atTarget(age: Double, sex: String) -> VE.Inputs {
        var i = VE.Inputs(chronoAge: age, sex: sex)
        for f in VE.Factor.allCases { i.set(f, VE.target(f, age: age, sex: sex)) }
        return i
    }

    // MARK: Targets and the referent

    func testEveryFactorAtTargetAddsZero() {
        for sex in ["male", "female", ""] {
            for age in [22.0, 30, 47.5, 63, 80] {
                let r = VE.compute(atTarget(age: age, sex: sex))!
                XCTAssertEqual(r.factorsUsed, 9)
                for i in r.impacts { XCTAssertEqual(i.years, 0, accuracy: 1e-12, "\(i.factor) \(sex) \(age)") }
                XCTAssertEqual(r.bodyAge, age, accuracy: 1e-12)
                XCTAssertEqual(r.vitality, 50, accuracy: 1e-12)
            }
        }
    }

    func testTargetsFollowWhitePaper() {
        XCTAssertEqual(VE.expectedVO2max(age: 20, sex: "male"), 46)
        XCTAssertEqual(VE.expectedVO2max(age: 30, sex: "female"), 38)
        XCTAssertEqual(VE.expectedVO2max(age: 47.5, sex: "male"), 36.5, accuracy: 1e-12)
        XCTAssertEqual(VE.expectedVO2max(age: 15, sex: "male"), 46)
        XCTAssertEqual(VE.expectedVO2max(age: 110, sex: "female"), 18)
        XCTAssertEqual(VE.expectedVO2max(age: 30, sex: "nonbinary"), 41)
        XCTAssertEqual(VE.target(.zone13, age: 25, sex: "male"), 100)
        XCTAssertEqual(VE.target(.zone13, age: 50, sex: "male"), 85, accuracy: 1e-12)
        XCTAssertEqual(VE.target(.zone45, age: 70, sex: "male"), 7, accuracy: 1e-12)
        XCTAssertEqual(VE.target(.steps, age: 30, sex: "female"), 8000)
        XCTAssertEqual(VE.target(.steps, age: 50, sex: "female"), 6800, accuracy: 1e-9)
        XCTAssertEqual(VE.target(.steps, age: 65, sex: "female"), 5600)
        XCTAssertEqual(VE.target(.rhr, age: 30, sex: "male"), 60)
        XCTAssertEqual(VE.target(.rhr, age: 30, sex: "female"), 64)
        XCTAssertEqual(VE.target(.rhr, age: 30, sex: "other"), 62)
        XCTAssertEqual(VE.target(.leanMass, age: 30, sex: "male"), 80)
        XCTAssertEqual(VE.target(.leanMass, age: 50, sex: "female"), 65, accuracy: 1e-12)
    }

    // MARK: Known deltas (one factor at a time, so no overlap applies)

    private func years(_ f: VE.Factor, _ v: Double, age: Double = 30, sex: String = "male") -> Double {
        var i = atTarget(age: age, sex: sex)
        i.set(f, v)
        let r = VE.compute(i)!
        XCTAssertEqual(r.ageDelta, r.impact(f)!.years, accuracy: 1e-12)   // everything else at target
        return r.impact(f)!.years
    }

    func testKnownDeltas() {
        XCTAssertEqual(years(.sleepHours, 6), 10 * ln(1.12), accuracy: 1e-9)             // +1.133
        XCTAssertEqual(years(.sleepHours, 8), 0, accuracy: 1e-9)
        // SRI knots (Windred 2024 quintiles): 60 → +10·(10/5.1)·−ln 0.80, quintile midpoints → their HRs.
        XCTAssertEqual(years(.sleepConsistency, 60), -10 * ln(0.80) * 10 / 5.1, accuracy: 1e-9) // +4.375
        XCTAssertEqual(years(.sleepConsistency, 75.1), 10 * ln(0.80), accuracy: 1e-9)   // −2.231
        XCTAssertEqual(years(.sleepConsistency, 80.9), 10 * ln(0.75), accuracy: 1e-9)   // −2.877
        XCTAssertEqual(years(.sleepConsistency, 90), 10 * ln(0.70), accuracy: 1e-9)     // −3.567
        XCTAssertEqual(years(.zone45, 0), -10 * ln(0.82) * 10 / 15, accuracy: 1e-9)      // +1.323
        XCTAssertEqual(years(.zone13, 150), 10 * ln(0.80) / 3, accuracy: 1e-9)           // −0.744
        XCTAssertEqual(years(.strength, 0), -10 * ln(0.88), accuracy: 1e-9)              // +1.278
        XCTAssertEqual(years(.vo2max, 44 - 7), 20 * -ln(0.87), accuracy: 1e-9)          // 2 MET below: +2.785
        XCTAssertEqual(years(.rhr, 70), 10 * ln(1.09), accuracy: 1e-9)                   // +0.862
        XCTAssertEqual(years(.leanMass, 70), 10 * ln(1.11), accuracy: 1e-9)              // +1.044
        XCTAssertEqual(years(.leanMass, 90), -0.5 * 10 * ln(1.11), accuracy: 1e-9)       // −0.522
        XCTAssertEqual(years(.leanMass, 70, age: 65), 10 * ln(1.11) * 0.5 * (76.5 - 70) / 10, accuracy: 1e-9)
        // Steps: Paluch knot at 7,842 vs the 8,000 target (interpolated toward 10,901).
        let c8000 = ln(0.55) + (ln(0.47) - ln(0.55)) * (8000 - 7842) / (10_901 - 7842)
        XCTAssertEqual(years(.steps, 5801), 10 * (ln(0.60) - c8000), accuracy: 1e-9)
    }

    // MARK: Caps

    func testCaps() {
        XCTAssertEqual(years(.sleepHours, 9.5), 0, accuracy: 1e-12)           // > 9 h: no effect
        XCTAssertEqual(years(.sleepHours, 11), 0, accuracy: 1e-12)
        XCTAssertEqual(years(.sleepHours, 2), years(.sleepHours, 4), accuracy: 1e-12)
        XCTAssertEqual(years(.strength, 300), years(.strength, 120), accuracy: 1e-12)   // no benefit past 2 h
        XCTAssertLessThan(years(.strength, 120), years(.strength, 60))
        XCTAssertEqual(years(.sleepConsistency, 10), years(.sleepConsistency, 60), accuracy: 1e-12)
        XCTAssertEqual(years(.sleepConsistency, 100), years(.sleepConsistency, 90), accuracy: 1e-12)
        XCTAssertEqual(years(.zone13, 2000), years(.zone13, 600), accuracy: 1e-12)
        XCTAssertEqual(years(.zone45, 200), years(.zone45, 53.6), accuracy: 1e-12)
        XCTAssertEqual(years(.vo2max, 100), years(.vo2max, 44 + 14), accuracy: 1e-12)  // ±4 MET
        XCTAssertEqual(years(.leanMass, 99), years(.leanMass, 90), accuracy: 1e-12)
        // Older adults plateau at 8,000 steps.
        XCTAssertEqual(years(.steps, 12_000, age: 65), years(.steps, 8_000, age: 65), accuracy: 1e-12)
        XCTAssertLessThan(years(.steps, 10_901, age: 30), years(.steps, 8_000, age: 30))
    }

    // MARK: Overlap

    func testOverlapShrinksSmallerOfPair() {
        var i = atTarget(age: 30, sex: "male")
        i.vo2max = 44 - 7     // +2.785 yrs
        i.restingHR = 70      // +0.862 yrs, the smaller → × 0.7
        let r = VE.compute(i)!
        XCTAssertEqual(r.impact(.vo2max)!.adjustment, 1)
        XCTAssertEqual(r.impact(.rhr)!.adjustment, VE.overlapFactor)
        XCTAssertEqual(r.impact(.rhr)!.years, 0.7 * 10 * ln(1.09), accuracy: 1e-9)
        XCTAssertEqual(r.ageDelta, 20 * -ln(0.87) + 0.7 * 10 * ln(1.09), accuracy: 1e-9)
    }

    // MARK: Missing inputs

    func testMissingLeanMassIsNeutral() {
        var i = atTarget(age: 30, sex: "female")
        i.restingHR = 70
        i.leanMassPct = nil
        let r = VE.compute(i)!
        let lm = r.impact(.leanMass)!
        XCTAssertTrue(lm.isMissing)
        XCTAssertEqual(lm.years, 0)
        XCTAssertEqual(r.factorsUsed, 8)
        i.leanMassPct = VE.target(.leanMass, age: 30, sex: "female")
        XCTAssertEqual(VE.compute(i)!.bodyAge, r.bodyAge, accuracy: 1e-12)
    }

    func testMinimumFactorsGate() {
        XCTAssertNil(VE.compute(.init(chronoAge: 40, sleepHours: 7, restingHR: 60)))
        XCTAssertNotNil(VE.compute(.init(chronoAge: 40, sleepHours: 7, steps: 8000, restingHR: 60)))
        XCTAssertNil(VE.compute(.init(chronoAge: 0, sleepHours: 7, steps: 8000, restingHR: 60)))
    }

    func testBodyAgeClamp() {
        var i = atTarget(age: 20, sex: "male")
        i.sleepConsistency = 100; i.zone13MinPerWeek = 600; i.zone45MinPerWeek = 60; i.strengthMinPerWeek = 120
        i.steps = 15_000; i.vo2max = 70; i.restingHR = 40; i.leanMassPct = 95
        XCTAssertEqual(VE.compute(i)!.bodyAge, VE.minBodyAge)
    }

    /// White-paper sanity check: the WHOOP-median 30-year-olds of Table 2 come out at −1.6 years in WHOOP's
    /// model. This model gives −1.47 (male) and −1.92 (female): the same direction and size, the gap is
    /// WHOOP's unpublished overlap factors and its exact curves (the steps curve, Paluch 2022, carries
    /// −1.49 years). Their 67–68 % consistency is WHOOP's scale, read here as if it were an SRI.
    func testWhoopMedianThirtyYearOlds() {
        let m = VE.compute(.init(chronoAge: 30, sex: "male", sleepHours: 7.0, sleepConsistency: 67,
                                 zone13MinPerWeek: 141, zone45MinPerWeek: 6, strengthMinPerWeek: 46,
                                 steps: 10_900, vo2max: 46.8, restingHR: 58, leanMassPct: 81))!
        let f = VE.compute(.init(chronoAge: 30, sex: "female", sleepHours: 7.3, sleepConsistency: 68,
                                 zone13MinPerWeek: 124, zone45MinPerWeek: 7, strengthMinPerWeek: 56,
                                 steps: 11_500, vo2max: 40.0, restingHR: 63, leanMassPct: 73))!
        XCTAssertEqual(m.ageDelta, -1.47, accuracy: 0.01)
        XCTAssertEqual(f.ageDelta, -1.92, accuracy: 0.01)
    }

    func testMeasuredVO2DoesNotRewriteEarlierWindows() {
        var history = days(180, endingOn: "2026-09-27") { _ in
            .init(day: "", restingHR: 60, sleepHours: 7, vo2max: 40, hasRecovery: true)
        }
        let earlier = VE.healthspan(days: history, asOf: "2026-08-30", chronoAge: 40, sex: "male")!
        history[179].measuredVO2max = 50
        let unchanged = VE.healthspan(days: history, asOf: "2026-08-30", chronoAge: 40, sex: "male")!
        XCTAssertEqual(earlier, unchanged)
        let latest = VE.healthspan(days: history, asOf: "2026-09-27", chronoAge: 40, sex: "male")!
        XCTAssertEqual(latest.longInputs.vo2max, 50)
        XCTAssertNil(latest.longInputs.strengthMinPerWeek)
        XCTAssertEqual(latest.current.impact(.strength)?.years, 0)
    }

    // MARK: Window, gate, cadence

    private func dayString(_ e: Int) -> String { HRVStatus.dayString(e) }

    private func days(_ n: Int, endingOn end: String, _ make: (Int) -> VE.Day) -> [VE.Day] {
        let e = VE.epochDay(end)!
        return (0..<n).map { i in
            var d = make(i)
            d.day = dayString(e - (n - 1) + i)
            return d
        }
    }

    /// A 30-day-periodic routine so the 30-day averages equal the 180-day ones.
    private func steady(_ i: Int) -> VE.Day {
        .init(day: "", restingHR: 58, sleepHours: i % 2 == 0 ? 7.2 : 7.8, sleepConsistency: 75, steps: 9000,
              vo2max: i % 7 == 0 ? 47 : nil, zone13Min: i % 2 == 0 ? 30 : 0, zone45Min: i % 10 == 0 ? 10 : 0,
              strengthMin: i % 5 == 0 ? 45 : 0, hasRecovery: true)
    }

    func testSundayKeying() {
        XCTAssertEqual(VE.sundayKey(onOrBefore: "2026-09-29"), "2026-09-27")   // Tue → Sun
        XCTAssertEqual(VE.sundayKey(onOrBefore: "2026-09-27"), "2026-09-27")   // Sun → itself
        XCTAssertEqual(VE.sundayKey(onOrBefore: "2026-09-26"), "2026-09-20")   // Sat → previous Sun
        XCTAssertEqual(VE.sundayKey(onOrBefore: "1970-01-01"), "1969-12-28")
        XCTAssertNil(VE.sundayKey(onOrBefore: "garbage"))
        XCTAssertEqual(VE.sundays(from: "2026-09-01", to: "2026-09-29"),
                       ["2026-09-06", "2026-09-13", "2026-09-20", "2026-09-27"])
        XCTAssertEqual(VE.sundays(from: "2026-09-27", to: "2026-09-27"), ["2026-09-27"])
        XCTAssertEqual(VE.sundays(from: "2026-09-28", to: "2026-10-03"), [])
    }

    func testRecoveryGateAndColdStart() {
        // 21 recoveries in the last 31 days unlocks; 20 does not.
        let unlocked = days(31, endingOn: "2026-09-27") { i in var d = self.steady(i); d.hasRecovery = i >= 10; return d }
        XCTAssertNotNil(VE.healthspan(days: unlocked, asOf: "2026-09-27", chronoAge: 30, sex: "male"))
        let locked = days(31, endingOn: "2026-09-27") { i in var d = self.steady(i); d.hasRecovery = i >= 11; return d }
        XCTAssertNil(VE.healthspan(days: locked, asOf: "2026-09-27", chronoAge: 30, sex: "male"))
        // A long history that stopped: recoveries older than 31 days do not count.
        let stale = days(200, endingOn: "2026-08-01", steady)
        XCTAssertNil(VE.healthspan(days: stale, asOf: "2026-09-27", chronoAge: 30, sex: "male"))
    }

    func testWeeklyRatesOverSpan() {
        // 60 zone-1–3 minutes every day for 3 weeks = 420 min/week, not diluted by the empty 180-day window.
        let d = days(21, endingOn: "2026-09-27") { _ in
            .init(day: "", restingHR: 60, sleepHours: 7.5, steps: 8000, zone13Min: 60, strengthMin: 10, hasRecovery: true)
        }
        let h = VE.healthspan(days: d, asOf: "2026-09-27", chronoAge: 30, sex: "male")!
        XCTAssertEqual(h.longInputs.zone13MinPerWeek!, 420, accuracy: 1e-9)
        XCTAssertEqual(h.longInputs.strengthMinPerWeek!, 70, accuracy: 1e-9)
        XCTAssertEqual(h.longInputs.zone45MinPerWeek!, 0, accuracy: 1e-9)
        XCTAssertNil(h.longInputs.vo2max)
        XCTAssertTrue(h.current.impact(.vo2max)!.isMissing)
    }

    func testLeanMassWindowAndCarry() {
        let d = days(180, endingOn: "2026-09-27", steady)
        let h1 = VE.healthspan(days: d, leanMass: [.init(day: "2026-09-01", pct: 78), .init(day: "2026-07-01", pct: 80)],
                               asOf: "2026-09-27", chronoAge: 30, sex: "male")!
        XCTAssertEqual(h1.longInputs.leanMassPct!, 79, accuracy: 1e-12)
        XCTAssertEqual(h1.recentInputs.leanMassPct!, 78, accuracy: 1e-12)
        // A reading older than the window still counts for a year…
        let h2 = VE.healthspan(days: d, leanMass: [.init(day: "2026-01-10", pct: 75)],
                               asOf: "2026-09-27", chronoAge: 30, sex: "male")!
        XCTAssertEqual(h2.longInputs.leanMassPct!, 75)
        // …but not longer.
        let h3 = VE.healthspan(days: d, leanMass: [.init(day: "2025-06-01", pct: 75)],
                               asOf: "2026-09-27", chronoAge: 30, sex: "male")!
        XCTAssertNil(h3.longInputs.leanMassPct)
        XCTAssertTrue(h3.current.impact(.leanMass)!.isMissing)
    }

    // MARK: Pace of Aging

    /// Same habits for six months → 1.0x exactly. Age 24 keeps every age-dependent target flat over the
    /// half-year projection, so nothing but the habits could move it.
    func testSteadyHabitsPaceOne() {
        let h = VE.healthspan(days: days(180, endingOn: "2026-09-27", steady), asOf: "2026-09-27",
                              chronoAge: 24, sex: "male")!
        XCTAssertEqual(h.paceOfAging, 1, accuracy: 1e-9)
        XCTAssertEqual(h.projected.bodyAge - h.current.bodyAge, 0.5, accuracy: 1e-9)
    }

    /// Pace = (projected − current) / 0.5 with the projection on the last 30 days at age + 0.5.
    func testPaceProjectionAndClamp() {
        func run(_ recentRHR: Double) -> VE.Healthspan {
            let d = days(180, endingOn: "2026-09-27") { i in
                var x = self.steady(i)
                if i >= 150 { x.restingHR = recentRHR }
                return x
            }
            return VE.healthspan(days: d, asOf: "2026-09-27", chronoAge: 24, sex: "male")!
        }
        let worse = run(64)
        let expected = 1 + (worse.projected.ageDelta - worse.current.ageDelta) / 0.5
        XCTAssertEqual(worse.paceOfAging, expected, accuracy: 1e-12)
        XCTAssertGreaterThan(worse.paceOfAging, 1)
        XCTAssertLessThan(run(52).paceOfAging, 1)
        XCTAssertEqual(run(100).paceOfAging, VE.maxPace)     // clamped at 3.0x
        // A 30-day collapse of every habit pushes the projection far enough to clamp at −1 the other way.
        let better = days(180, endingOn: "2026-09-27") { i in
            var x = self.steady(i)
            if i < 150 { x.restingHR = 90; x.steps = 2500; x.sleepHours = 5; x.sleepConsistency = 40 }
            return x
        }
        XCTAssertEqual(VE.healthspan(days: better, asOf: "2026-09-27", chronoAge: 24, sex: "male")!.paceOfAging,
                       VE.minPace)
    }

    func testPaceBands() {
        XCTAssertEqual(VE.paceBand(-0.2), .reversing)
        XCTAssertEqual(VE.paceBand(0), .slowing)
        XCTAssertEqual(VE.paceBand(0.94), .slowing)
        XCTAssertEqual(VE.paceBand(0.95), .steady)
        XCTAssertEqual(VE.paceBand(1.049), .steady)
        XCTAssertEqual(VE.paceBand(1.05), .accelerated)
    }

    // MARK: Inputs helpers

    func testZoneMinutesFromJSON() {
        let a = VE.zoneMinutes(zonesJSON: #"{"z1":10,"z2":20,"z3":30,"z4":30,"z5":10}"#, durationS: 3600)!
        XCTAssertEqual(a.z13, 36, accuracy: 1e-9)
        XCTAssertEqual(a.z45, 24, accuracy: 1e-9)
        let b = VE.zoneMinutes(zonesJSON: #"{"zone1":50,"zone4":50}"#, durationS: 1200)!
        XCTAssertEqual(b.z13, 10, accuracy: 1e-9)
        XCTAssertEqual(b.z45, 10, accuracy: 1e-9)
        XCTAssertNil(VE.zoneMinutes(zonesJSON: nil, durationS: 600))
        XCTAssertNil(VE.zoneMinutes(zonesJSON: #"{"z1":0}"#, durationS: 600))
        XCTAssertNil(VE.zoneMinutes(zonesJSON: "not json", durationS: 600))
    }

    func testStrengthSports() {
        for s in ["Strength", "Strength Training", "Weightlifting", "Powerlifting", "HIIT", "Yoga", "Hot Yoga",
                  "Pilates", "Barre3", "Barry's", "F45 Training", "Functional Fitness", "Rucking", "CrossFit",
                  "Calisthenics", "Boot camp", "Core training", "Bodybuilding"] {
            XCTAssertTrue(VE.isStrengthSport(s), s)
        }
        for s in ["Running", "Cycling", "Walking", "detected", "Other", "Swimming", "Stretching"] {
            XCTAssertFalse(VE.isStrengthSport(s), s)
        }
    }

    func testEpochDay() {
        XCTAssertEqual(VE.epochDay("1970-01-01"), 0)
        XCTAssertEqual(VE.epochDay("2026-09-24"), 20_720)
        XCTAssertNil(VE.epochDay("2026-13-01"))
    }

    /// Shared verbatim with Android's Swift-generated oracle, over all nine curves and their caps.
    func testAndroidSharedCurveOracle() {
        func f(_ x: Double) -> String {
            String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), x == 0 ? 0 : x)
        }
        func digest(_ text: String) -> String {
            var hash: UInt64 = 14695981039346656037
            for unit in text.utf16 { hash = (hash ^ UInt64(unit)) &* 1099511628211 }
            return String(hash, radix: 16)
        }
        let ages: [Double] = [18, 20, 29.5, 30, 40, 55, 60, 72.25, 100]
        let sexes = ["male", "female", "", "nonbinary", "MALE"]
        let samples: [[Double]] = [
            [0,3.9,4,5.5,6.999,7,8,9,10,14],
            [-1,0,59.9,60,65,70,75.1,80.9,85.25,90,100,140],
            [-2,0,7,9.5,10,15,53.6,100,150,300,600,900],
            [-2,0,7,9.5,10,15,53.6,100,150,300,600,900],
            [-2,0,7,9.5,10,15,40,53.6,60,100,120,300],
            [0,1999,2000,3553,5801,7842,8000,10901,15000],
            [0,10,18,35,45,70,100],
            [0,39,40,55,60,64,85,100,110],
            [0,39,40,50,67,70,80,90,97,100]
        ]
        var actual: [String] = []
        for (index, factor) in VE.Factor.allCases.enumerated() {
            var lines: [String] = []
            for age in ages { for sex in sexes { for value in samples[index] {
                lines.append([f(age), sex, f(value), f(VE.target(factor, age: age, sex: sex)),
                              f(VE.lnHazard(factor, value: value, age: age, sex: sex))].joined(separator: "|"))
            } } }
            actual.append("curve|\(factor.rawValue)|\(lines.count)|\(digest(lines.joined(separator: "\n")))")
        }
        XCTAssertEqual(actual.joined(separator: "\n"), """
        curve|sleepHours|450|8c0cb0b78b3ef905
        curve|sleepConsistency|540|e7609bea94ff59a5
        curve|zone13|540|7b7fe0ef2d413a70
        curve|zone45|540|5d4970297867e03d
        curve|strength|540|82c1acf2ff57614c
        curve|steps|405|a04ead91a424fb5a
        curve|vo2max|315|4d188abe1cca49fd
        curve|rhr|405|c8d714f0f0b04e1
        curve|leanMass|450|49fef509adbcd931
        """)
    }
}
