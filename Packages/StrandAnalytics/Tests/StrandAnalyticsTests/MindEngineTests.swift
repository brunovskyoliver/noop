import XCTest
@testable import StrandAnalytics

final class MindEngineTests: XCTestCase {

    /// `n` consecutive days ending at `end`, built by `make(offsetFromEnd)`.
    private func days(_ n: Int, ending end: String = "2026-09-28",
                      _ make: (Int) -> MindDay) -> [MindDay] {
        (0..<n).reversed().map { back in
            var d = make(back)
            d.day = MindEngine.shift(end, by: -back)!
            return d
        }
    }

    private func steady(high: Double, low: Double, scored: Double = 600, rest: Double? = nil,
                        charge: Double? = nil, sleepStress: Double? = nil) -> (Int) -> MindDay {
        { _ in MindDay(day: "", highStressMin: high, lowStressMin: low, scoredMin: scored,
                       sleepStressPct: sleepStress, rest: rest, charge: charge) }
    }

    // MARK: Calendar helpers

    func testShiftRoundTripsAcrossMonthsAndLeapYears() {
        XCTAssertEqual(MindEngine.shift("2026-03-01", by: -1), "2026-02-28")
        XCTAssertEqual(MindEngine.shift("2024-03-01", by: -1), "2024-02-29")
        XCTAssertEqual(MindEngine.shift("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(MindEngine.shift("2026-09-28", by: 0), "2026-09-28")
        XCTAssertNil(MindEngine.shift("not-a-day", by: 1))
        for off in [-400, -31, -1, 1, 45, 1000] {
            let d = MindEngine.shift("2026-09-28", by: off)!
            XCTAssertEqual(MindEngine.epoch(d)! - MindEngine.epoch("2026-09-28")!, off)
        }
    }

    // MARK: Resilience

    func testResilienceColdStartNeedsSevenStressDays() {
        let six = days(6, steady(high: 60, low: 300, rest: 80, charge: 70))
        XCTAssertNil(ResilienceEngine.compute(days: six, asOf: "2026-09-28"))
        let seven = days(7, steady(high: 60, low: 300, rest: 80, charge: 70))
        XCTAssertNotNil(ResilienceEngine.compute(days: seven, asOf: "2026-09-28"))
        // Days with under two scored hours don't count toward the gate.
        let thin = days(14, steady(high: 10, low: 50, scored: 100))
        XCTAssertNil(ResilienceEngine.compute(days: thin, asOf: "2026-09-28"))
        XCTAssertNil(ResilienceEngine.compute(days: [], asOf: "2026-09-28"))
    }

    /// Known component values recover a known score. high 10 % → load 1 − 0.10/0.35; low 30 % → 0.6;
    /// nights (rest 80, charge 60 → 0.70) → (0.70 − 0.30)/0.55.
    func testResilienceRecoversKnownScore() {
        let input = days(14, steady(high: 60, low: 180, scored: 600, rest: 80, charge: 60))
        let r = ResilienceEngine.compute(days: input, asOf: "2026-09-28")!
        let load = 1 - 0.10 / 0.35, daytime = 0.30 / 0.50, night = 0.40 / 0.55
        let expected = 100 * (0.30 * load + 0.30 * daytime + 0.40 * night)
        XCTAssertEqual(r.score, expected, accuracy: 1e-9)
        XCTAssertEqual(r.highShare, 0.10, accuracy: 1e-12)
        XCTAssertEqual(r.lowShare, 0.30, accuracy: 1e-12)
        XCTAssertEqual(r.nightRecovery!, 0.70, accuracy: 1e-12)
        XCTAssertEqual(r.stressDays, 14)
        XCTAssertEqual(r.nights, 14)
        XCTAssertEqual(r.level, ResilienceEngine.level(for: expected))
    }

    /// Several synthetic people land on the five levels in order.
    func testResilienceLevelsSpanAllFive() {
        let people: [(Double, Double, Double, Double, ResilienceEngine.Level)] = [
            // high, low, rest, charge, expected level
            (240, 30, 40, 20, .limited),
            (150, 120, 60, 45, .adequate),
            (110, 180, 65, 50, .solid),
            (80, 220, 75, 60, .strong),
            (20, 330, 95, 90, .exceptional),
        ]
        var last: Double = -1
        for (high, low, rest, charge, want) in people {
            let r = ResilienceEngine.compute(days: days(14, steady(high: high, low: low, rest: rest, charge: charge)),
                                             asOf: "2026-09-28")!
            XCTAssertEqual(r.level, want, "score \(r.score)")
            XCTAssertGreaterThan(r.score, last)
            last = r.score
        }
    }

    func testResilienceWithoutNightsRenormalisesDaytimeOnly() {
        let r = ResilienceEngine.compute(days: days(10, steady(high: 0, low: 300)), asOf: "2026-09-28")!
        XCTAssertNil(r.nightComponent)
        XCTAssertEqual(r.score, 100, accuracy: 1e-9)   // no high stress, half the day calm → full daytime credit
        XCTAssertEqual(r.level, .exceptional)
    }

    func testResilienceIgnoresDaysOutsideWindow() {
        // 14 good days, then 30 terrible days before the window: the window must only see the good ones.
        let old = days(30, ending: "2026-09-14", steady(high: 400, low: 0, rest: 10, charge: 5))
        let recent = days(14, steady(high: 30, low: 300, rest: 90, charge: 85))
        let a = ResilienceEngine.compute(days: recent, asOf: "2026-09-28")!
        let b = ResilienceEngine.compute(days: old + recent, asOf: "2026-09-28")!
        XCTAssertEqual(a.score, b.score, accuracy: 1e-12)
    }

    func testResilienceTrend() {
        // Three bad weeks followed by one calm week: the score rises over the last seven days.
        let bad = days(21, ending: "2026-09-21", steady(high: 200, low: 60, rest: 50, charge: 30))
        let good = days(7, steady(high: 20, low: 330, rest: 90, charge: 85))
        let r = ResilienceEngine.compute(days: bad + good, asOf: "2026-09-28")!
        XCTAssertEqual(r.trend, .improving)
        let flat = ResilienceEngine.compute(days: days(28, steady(high: 60, low: 200, rest: 80, charge: 60)),
                                            asOf: "2026-09-28")!
        XCTAssertEqual(flat.trend, .steady)
        // No value a week earlier → no trend.
        let short = ResilienceEngine.compute(days: days(8, steady(high: 60, low: 200)), asOf: "2026-09-28")!
        XCTAssertNil(short.trend)
    }

    func testResilienceHistorySkipsColdStart() {
        let h = ResilienceEngine.history(days: days(10, steady(high: 60, low: 200)), asOf: "2026-09-28", span: 10)
        XCTAssertEqual(h.count, 4)   // days 7…10 of the data are past the 7-day gate
        XCTAssertEqual(h.last?.day, "2026-09-28")
        XCTAssertEqual(h.first?.day, "2026-09-25")
    }

    // MARK: Cumulative Stress

    func testCumulativeColdStartNeeds21Days() {
        XCTAssertNil(CumulativeStressEngine.compute(days: days(20, steady(high: 60, low: 200)), asOf: "2026-09-28"))
        XCTAssertNotNil(CumulativeStressEngine.compute(days: days(21, steady(high: 60, low: 200)), asOf: "2026-09-28"))
        // Charge alone is not a stress day.
        let chargeOnly = days(31) { _ in MindDay(day: "", charge: 20) }
        XCTAssertNil(CumulativeStressEngine.compute(days: chargeOnly, asOf: "2026-09-28"))
    }

    /// daytime 12 % high → 0.30 load; sleep stress 10 % → 0.25; Charge 45 → (70 − 45)/50 = 0.5.
    func testCumulativeRecoversKnownScore() {
        let input = days(31, steady(high: 72, low: 200, scored: 600, charge: 45, sleepStress: 10))
        let r = CumulativeStressEngine.compute(days: input, asOf: "2026-09-28")!
        let expected = 100 * (0.50 * 0.30 + 0.25 * 0.25 + 0.25 * 0.5)
        XCTAssertEqual(r.score, expected, accuracy: 1e-9)
        XCTAssertEqual(r.daytimeLoad!, 0.30, accuracy: 1e-12)
        XCTAssertEqual(r.sleepLoad!, 0.25, accuracy: 1e-12)
        XCTAssertEqual(r.recoveryLoad!, 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.days, 31)
        XCTAssertEqual(r.level, .moderate)
    }

    func testCumulativeLevelsAndMonotonicity() {
        let cases: [(Double, Double, Double, CumulativeStressEngine.Level)] = [
            (6, 2, 90, .low), (60, 10, 60, .moderate), (150, 20, 40, .elevated), (260, 35, 15, .high),
        ]
        var last = -1.0
        for (high, sleep, charge, want) in cases {
            let r = CumulativeStressEngine.compute(
                days: days(31, steady(high: high, low: 100, charge: charge, sleepStress: sleep)), asOf: "2026-09-28")!
            XCTAssertEqual(r.level, want, "score \(r.score)")
            XCTAssertGreaterThan(r.score, last)
            last = r.score
        }
    }

    func testCumulativeMissingSignalsRenormalise() {
        // Sleep stress only: the day load is exactly the sleep load.
        let r = CumulativeStressEngine.compute(days: days(25) { _ in MindDay(day: "", sleepStressPct: 20) },
                                               asOf: "2026-09-28")!
        XCTAssertEqual(r.score, 50, accuracy: 1e-9)
        XCTAssertNil(r.daytimeLoad)
        XCTAssertNil(r.recoveryLoad)
    }

    func testCumulativeTrendRisingLoadIsWorsening() {
        let calm = days(31, ending: "2026-09-21", steady(high: 20, low: 300, charge: 80, sleepStress: 3))
        let tense = days(7, steady(high: 240, low: 30, charge: 25, sleepStress: 30))
        let r = CumulativeStressEngine.compute(days: calm + tense, asOf: "2026-09-28")!
        XCTAssertEqual(r.trend, .worsening)
        let easing = CumulativeStressEngine.compute(
            days: days(31, ending: "2026-09-21", steady(high: 240, low: 30, charge: 25, sleepStress: 30))
                + days(7, steady(high: 20, low: 300, charge: 80, sleepStress: 3)),
            asOf: "2026-09-28")!
        XCTAssertEqual(easing.trend, .improving)
    }

    // MARK: Check-in

    func testCheckInScoring() {
        // PSS-4: items 2 and 3 are reverse-scored (4 − answer).
        XCTAssertEqual(MindCheckIn.score(.pss4, answers: [0, 4, 4, 0]), 0)
        XCTAssertEqual(MindCheckIn.score(.pss4, answers: [4, 0, 0, 4]), 16)
        XCTAssertEqual(MindCheckIn.score(.pss4, answers: [2, 2, 2, 2]), 8)
        XCTAssertEqual(MindCheckIn.score(.pss4, answers: [3, 1, 2, 1]), 3 + 3 + 2 + 1)
        XCTAssertEqual(MindCheckIn.score(.gad2, answers: [1, 2]), 3)
        XCTAssertEqual(MindCheckIn.score(.phq2, answers: [3, 3]), 6)
        // Incomplete or out-of-range answers are not scored.
        XCTAssertNil(MindCheckIn.score(.gad2, answers: [1]))
        XCTAssertNil(MindCheckIn.score(.phq2, answers: [1, 4]))
        XCTAssertNil(MindCheckIn.score(.pss4, answers: [0, 0, 0, -1]))
    }

    func testScreeningCutoff() {
        XCTAssertFalse(MindCheckIn.atOrAboveCutoff(.phq2, score: 2))
        XCTAssertTrue(MindCheckIn.atOrAboveCutoff(.phq2, score: 3))
        XCTAssertTrue(MindCheckIn.atOrAboveCutoff(.gad2, score: 6))
        XCTAssertFalse(MindCheckIn.atOrAboveCutoff(.pss4, score: 16))   // PSS has no cutoff
    }

    func testCheckInDue() {
        XCTAssertTrue(MindCheckIn.isDue(lastCheckInDay: nil, today: "2026-09-28"))
        XCTAssertFalse(MindCheckIn.isDue(lastCheckInDay: "2026-09-01", today: "2026-09-28"))
        XCTAssertTrue(MindCheckIn.isDue(lastCheckInDay: "2026-08-31", today: "2026-09-28"))
    }

    /// Scores built as an exact linear function of the window mean give r = −1; fewer than five check-ins
    /// give nothing.
    func testCorrelationPairsEachCheckInWithItsWindow() {
        var signal: [(day: String, value: Double)] = []
        var scores: [(day: String, value: Double)] = []
        for month in 0..<6 {
            let checkIn = MindEngine.shift("2026-03-01", by: month * 30)!
            let level = 40.0 + Double(month) * 5
            for back in 0..<14 { signal.append((MindEngine.shift(checkIn, by: -back)!, level)) }
            scores.append((checkIn, 10 - (level - 40) / 5))
        }
        let c = MindCheckIn.correlate(scores: scores, signal: signal, windowDays: 14)!
        XCTAssertEqual(c.r, -1, accuracy: 1e-9)
        XCTAssertEqual(c.n, 6)
        XCTAssertNil(MindCheckIn.correlate(scores: Array(scores.prefix(4)), signal: signal, windowDays: 14))
        // A check-in with no signal in its window is dropped, not paired with zero.
        XCTAssertNil(MindCheckIn.correlate(scores: scores, signal: [], windowDays: 14))
    }
    func testDuplicateDaysCannotSatisfyColdStart() {
        let one = MindDay(day: "2026-09-28", highStressMin: 60, lowStressMin: 300, scoredMin: 600)
        XCTAssertNil(ResilienceEngine.compute(days: Array(repeating: one, count: 21), asOf: one.day))
        XCTAssertNil(CumulativeStressEngine.compute(days: Array(repeating: one, count: 21), asOf: one.day))
    }

    func testMissingBandsAndNonFiniteValuesDoNotBecomeCalmDays() {
        let missing = MindDay(day: "2026-09-28", scoredMin: 600, sleepStressPct: .nan, rest: .infinity)
        XCTAssertFalse(missing.hasDaytimeStress)
        XCTAssertNil(CumulativeStressEngine.dayLoad(missing))
        let impossible = MindDay(day: "2026-09-28", highStressMin: 500, lowStressMin: 300, scoredMin: 600)
        XCTAssertFalse(impossible.hasDaytimeStress)
        let healthy = days(14, steady(high: 60, low: 300, rest: .nan, charge: 70))
        XCTAssertTrue(ResilienceEngine.compute(days: healthy, asOf: "2026-09-28")!.score.isFinite)
    }

    func testDuplicateCheckInsDoNotInflateCorrelation() {
        let scores = Array(repeating: (day: "2026-09-28", value: 2.0), count: 6)
        XCTAssertNil(MindCheckIn.correlate(scores: scores,
                                         signal: [(day: "2026-09-28", value: 80)], windowDays: 14))
    }

}
