import XCTest
@testable import StrandAnalytics

/// HRVReadiness (Plews/Altini SWC) — the OPT-IN experimental HRV-readiness tier readout. The oracle for the
/// Android HRVReadinessTest; keep the two in lockstep (same fixtures, same assertions). Pins each tier on a
/// fixture series and the < minNights calibrating/nil edge (including that physiologically implausible
/// nights are dropped BEFORE the gate). Read-only variant: it feeds no downstream gate, so there is nothing
/// else to assert.
final class HRVReadinessTests: XCTestCase {

    /// `values` as consecutive nights, the last one on the `asOf` day.
    private static func evaluate(_ values: [Double?]) -> HRVReadinessResult? {
        let keys = values.indices.map { Baselines.cutoffKey(todayKey: "2028-01-01", carryDays: values.count - 1 - $0) }
        return HRVReadiness.evaluate(nights: zip(keys, values).map { (day: $0, value: $1) }, asOf: "2028-01-01")
    }

    // A high-then-primed history: 53 nights at 50 ms, the last 7 at 75 ms — the 7-night baseline sits
    // well above the personal normal band, so the tier reads .primed.
    private let primedHistory: [Double?] =
        Array(repeating: 50.0, count: 53) + Array(repeating: 75.0, count: 7)

    // The mirror: 53 nights at 50 ms, the last 7 at 38 ms — the 7-night baseline sits below the band, .suppressed.
    private let suppressedHistory: [Double?] =
        Array(repeating: 50.0, count: 53) + Array(repeating: 38.0, count: 7)

    // A perfectly flat history: baseline7 == longMean exactly, so the band collapses to the mean → .normal.
    private let flatHistory: [Double?] = Array(repeating: 60.0, count: 60)

    // MARK: - Tier

    func testPrimedFixtureTier() {
        let r = Self.evaluate(primedHistory)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.tier, .primed)
        // The 7-night baseline is the last-7 mean, exp back to ms: exp(ln 75) = 75.
        XCTAssertEqual(r!.baseline7Ms, 75.0, accuracy: 1e-6)
        // Baseline above the long mean → the overreaching (falling-CV-while-below-mean) watch cannot fire.
        XCTAssertFalse(r!.overreachingWatch)
    }

    func testSuppressedFixtureTier() {
        let r = Self.evaluate(suppressedHistory)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.tier, .suppressed)
        XCTAssertEqual(r!.baseline7Ms, 38.0, accuracy: 1e-6)
    }

    func testFlatHistoryIsNormalAndBandCollapsesToMean() {
        let r = Self.evaluate(flatHistory)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.tier, .normal)
        // baseline7 == longMean and longSD == 0 → the band collapses to the mean, all reading back to 60 ms.
        XCTAssertEqual(r!.baseline7Ms, 60.0, accuracy: 1e-6)
        XCTAssertEqual(r!.normalLowMs, 60.0, accuracy: 1e-6)
        XCTAssertEqual(r!.normalHighMs, 60.0, accuracy: 1e-6)
    }

    // MARK: - Calibrating / nil edge (< minNights valid nights)

    func testBelowMinNightsIsNil() {
        // The long window excludes the week, so the gate counts nights before it.
        let week = HRVReadiness.rollWindow
        XCTAssertNil(Self.evaluate(Array(repeating: 60.0, count: HRVReadiness.minNights - 1 + week)))
        XCTAssertNotNil(Self.evaluate(Array(repeating: 60.0, count: HRVReadiness.minNights + week)))
    }

    func testOutOfRangeNightsAreDroppedBeforeGate() {
        // 13 in-range long-window nights + 5 implausible (300 ms > hrvCfg.maxVal) → still calibrating (nil).
        let week: [Double?] = Array(repeating: 60.0, count: HRVReadiness.rollWindow)
        let mixed: [Double?] = Array(repeating: 60.0, count: 13) + Array(repeating: 300.0, count: 5) + week
        XCTAssertNil(Self.evaluate(mixed))
        // Add one more in-range night → a reading appears (the implausible nights never count).
        let ok: [Double?] = Array(repeating: 60.0, count: 14) + Array(repeating: 300.0, count: 5) + week
        XCTAssertNotNil(Self.evaluate(ok))
    }

    func testTheWeekIsACalendarWeekSoAGapCannotPassForIt() {
        // A month of nights, then 20 days off the strap: the "7 nights" would be three weeks old.
        let old: [Double?] = Array(repeating: 60.0, count: 40)
        let gap: [Double?] = Array(repeating: nil, count: 20)
        XCTAssertNil(Self.evaluate(old + gap))
    }

    func testTheLongWindowExcludesTheWeek() {
        // Long normal is exactly 50 ms; a week at 75 ms must not pull it up.
        let r = Self.evaluate(Array(repeating: 50.0, count: 30) + Array(repeating: 75.0, count: 7))
        XCTAssertEqual(r!.normalLowMs, 50.0, accuracy: 1e-6)
        XCTAssertEqual(r!.normalHighMs, 50.0, accuracy: 1e-6)
    }

    func testOverreachingWatchStaysQuietOnNoise() {
        var state: UInt64 = 11
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
        var fired = 0, belowMean = 0
        for _ in 0..<500 {
            let values: [Double?] = (0..<67).map { _ in
                60 * exp(0.12 * (-2 * log(max(next(), 1e-12))).squareRoot() * cos(2 * .pi * next()))
            }
            guard let r = Self.evaluate(values) else { continue }
            if r.overreachingWatch { fired += 1 }
            if r.baseline7Ms < (r.normalLowMs * r.normalHighMs).squareRoot() { belowMean += 1 }
        }
        // Slope alone would fire on about half of the below-mean histories.
        XCTAssertLessThan(Double(fired) / Double(belowMean), 0.40)
    }

    func testOverreachingWatchFiresOnASustainedFallBelowTheMean() {
        // Night-to-night swing shrinking steadily while the level sits below normal.
        let long: [Double?] = (0..<45).map { 60 * exp($0 % 2 == 0 ? 0.20 : -0.20) }
        let late: [Double?] = (0..<22).map { i in
            let amp = 0.20 * (1 - Double(i) / 22)
            return 50 * exp(i % 2 == 0 ? amp : -amp)
        }
        XCTAssertEqual(Self.evaluate(long + late)?.overreachingWatch, true)
    }
}
