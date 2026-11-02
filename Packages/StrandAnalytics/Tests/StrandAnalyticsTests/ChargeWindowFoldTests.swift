import XCTest
@testable import StrandAnalytics

/// The prior-nights-only window fold behind Charge's baselines: a mean and SD over the 21 calendar days
/// before the scored day, with HRV in ln space. Pins the three defects of the refolded EWMA it replaced:
/// young-phase weighting, the outlier lockout, and self-inclusion with look-ahead.
final class ChargeWindowFoldTests: XCTestCase {

    /// A small seeded generator, so a statistical assertion cannot flake.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func gaussian(_ rng: inout SplitMix) -> Double {
        let u1 = Double.random(in: 1e-12..<1, using: &rng), u2 = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    private func key(_ i: Int) -> String { Baselines.cutoffKey(todayKey: "2028-01-01", carryDays: 2000 - i) }

    private func nights(_ values: [Double?]) -> [(day: String, value: Double?)] {
        values.enumerated().map { (day: key($0.offset), value: $0.element) }
    }

    private func hrvStates(_ values: [Double?]) -> [String: ChargeBaselines.PriorBaseline] {
        ChargeBaselines.priorBaselines(days: values.indices.map(key), imported: [], own: nights(values),
                                       cfg: Baselines.hrvCfg, baselineEpoch: 0, logDomain: true)
    }

    private func zs(_ values: [Double]) -> [Double?] {
        let states = hrvStates(values)
        return values.enumerated().map { i, v in
            guard let s = states[key(i)]?.state, s.usable else { return nil }
            return RecoveryScorer.zScore(v, baseline: RecoveryScorer.DriverBaseline(s))
        }
    }

    func testZIsUnitScaleAtEveryHRVLevel() {
        for mean in [25.0, 50.0, 100.0] {
            var rng = SplitMix(state: 42)
            let values = (0..<1000).map { _ in mean * exp(0.15 * gaussian(&rng)) }
            let z = zs(values).dropFirst(25).compactMap { $0 }
            let m = z.reduce(0, +) / Double(z.count)
            let sd = (z.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(z.count - 1)).squareRoot()
            // A 21-night sample predicts the next night with a t-shaped error, so SD(z) sits a little
            // above 1 (about 1.08 in theory). It must not depend on the HRV level.
            XCTAssertEqual(sd, 1.08, accuracy: 0.1, "mean \(mean)")
            XCTAssertEqual(m, 0, accuracy: 0.1, "mean \(mean)")
        }
    }

    func testAStepAdaptsWithoutALockout() {
        var rng = SplitMix(state: 7)
        let before = (0..<30).map { _ in 90 * exp(0.05 * gaussian(&rng)) }
        let after = (0..<30).map { _ in 50 * exp(0.05 * gaussian(&rng)) }
        let z = zs(before + after).map { $0 ?? .nan }
        let states = hrvStates(before + after)
        // The first night after the step is very low, then the baseline moves every night.
        XCTAssertLessThan(z[30], -3)
        for i in 31..<51 { XCTAssertGreaterThan(z[i], z[30], "night \(i - 30)") }
        // 13 nights in, the old fold was still rejecting the new level as outliers.
        XCTAssertGreaterThan(z[43], -1.5)
        XCTAssertLessThan(states[key(43)]!.state.baseline, 72)
        // A full window after the step the old level has aged out.
        XCTAssertEqual(z[52], 0, accuracy: 1.5)
        XCTAssertEqual(states[key(52)]!.state.baseline, 50, accuracy: 3)
    }

    func testAScoredDayIgnoresItselfAndLaterNights() {
        var rng = SplitMix(state: 3)
        let values = (0..<60).map { _ in 60 * exp(0.1 * gaussian(&rng)) as Double? }
        let day = key(40)
        let upToDay = hrvStates(Array(values[...40]))[day]
        XCTAssertEqual(upToDay, hrvStates(values)[day], "later nights moved a past baseline")
        var changedSelf = values
        changedSelf[40] = 150
        XCTAssertEqual(upToDay, hrvStates(changedSelf)[day], "a night entered its own baseline")
        var changedInput = values
        changedInput[30] = 150
        XCTAssertNotEqual(upToDay, hrvStates(changedInput)[day], "a real input change must move it")
    }

    func testEveryNightInTheWindowCountsAlike() {
        // The refolded EWMA gave the first eight nights most of the weight. Here it is a plain mean.
        let values: [Double?] = [80, 80, 80, 80, 40, 40, 40, 40, nil]
        let state = hrvStates(values)[key(8)]!.state
        XCTAssertEqual(state.baseline, (80 * 40 as Double).squareRoot(), accuracy: 1e-6)
        XCTAssertEqual(state.nValid, 8)
    }

    func testOnlyDataQualityExcludesANight() {
        let usual: [Double?] = (0..<10).map { _ in 50 }
        // 200 ms is implausibly far from 50 but physiologically possible, so it counts. 400 ms cannot be real.
        XCTAssertEqual(hrvStates(usual + [200, nil])[key(11)]!.state.nValid, 11)
        XCTAssertEqual(hrvStates(usual + [400, nil])[key(11)]!.state.nValid, 10)
    }

    func testTheWindowIsTwentyOneDaysBeforeTheDay() {
        let values: [Double?] = (0..<40).map { $0 == 18 ? 100 : 50 }
        // Day 39 reads days 18...38; day 40 no longer reads day 18.
        XCTAssertEqual(hrvStates(values + [nil])[key(39)]!.history.dayKeys.first, key(18))
        XCTAssertEqual(hrvStates(values + [nil])[key(40)]!.history.dayKeys.first, key(19))
        XCTAssertEqual(hrvStates(values + [nil])[key(40)]!.state.baseline, 50, accuracy: 1e-9)
    }

    func testTheRecalibrationEpochDropsEarlierNights() {
        let values: [Double?] = (0..<12).map { $0 < 8 ? 90 : 50 }
        let epochDay = Double(Baselines.isoEpochDay(key(8))!) * 86_400
        let s = ChargeBaselines.priorBaselines(days: [key(12)], imported: [], own: nights(values),
                                               cfg: Baselines.hrvCfg, baselineEpoch: epochDay, logDomain: true)[key(12)]!
        XCTAssertEqual(s.state.nValid, 4)
        XCTAssertEqual(s.state.baseline, 50, accuracy: 1e-9)
    }

    func testAFlatHistoryHitsTheLogSpaceFloorInsteadOfDividingByZero() {
        let values: [Double?] = (0..<10).map { _ in 50 }
        let s = hrvStates(values + [nil])[key(10)]!.state
        XCTAssertEqual(Baselines.sigma(s), Baselines.readinessHRVLnCfg.floorSpread, accuracy: 1e-9)
    }

    func testChargeScoresHRVInLogSpace() {
        let state = hrvStates((0..<21).map { Double?($0 % 2 == 0 ? 45 : 55) } + [nil])[key(21)]!.state
        let up = RecoveryScorer.zScore(state.baseline * 1.5, baseline: RecoveryScorer.DriverBaseline(state))
        let down = RecoveryScorer.zScore(state.baseline / 1.5, baseline: RecoveryScorer.DriverBaseline(state))
        XCTAssertEqual(up, -down, accuracy: 1e-9, "a ratio up and the same ratio down must be symmetric")
        XCTAssertEqual(Baselines.deviation(state.baseline * 1.5, state: state).z, up, accuracy: 1e-9)
    }

    func testRestCentreIsPersonalOnceUsable() {
        let state = hrvStates(Array(repeating: Double?(50), count: 10) + [nil])[key(10)]!.state
        // A wearer whose Rest is always 0.70 reads neutral at 0.70, not permanently below a fixed 0.85.
        let habitual = RecoveryScorer.recovery(hrv: state.baseline, rhr: 50, resp: nil, hrvBaseline: state,
                                               rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.70, sleepCenter: 0.70)
        let neutral = RecoveryScorer.recovery(hrv: state.baseline, rhr: 50, resp: nil, hrvBaseline: state,
                                              rhrBaseline: nil, respBaseline: nil, sleepPerf: nil)
        XCTAssertEqual(habitual!, neutral!, accuracy: 1e-9)
        let fixed = RecoveryScorer.recovery(hrv: state.baseline, rhr: 50, resp: nil, hrvBaseline: state,
                                            rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.70)
        XCTAssertLessThan(fixed!, habitual!)
        let rows = RecoveryScorer.chargeDrivers(hrv: state.baseline, rhr: 50, resp: nil, hrvBaseline: state,
                                                rhrBaseline: nil, respBaseline: nil, sleepPerf: 0.70, sleepCenter: 0.70)
        XCTAssertEqual(rows.first { $0.label == "Sleep quality" }?.deltaPoints, 0)
    }
}
