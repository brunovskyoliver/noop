import XCTest
@testable import StrandAnalytics
import WhoopStore

final class ReadinessEngineTests: XCTestCase {

    private func d(_ i: Int, hrv: Double?, rhr: Int?, strain: Double?, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: nil, strain: strain, exerciseCount: nil,
                    spo2Pct: nil, skinTempDevC: nil, respRateBpm: resp)
    }

    /// 28 baseline days with gentle variation (so SD > 0), then `today` as day 29.
    private func baseline(todayHrv: Double?, todayRhr: Int?, todayStrain: Double?,
                          todayResp: Double? = nil, baseStrain: Double = 10) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...28 {
            days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: i % 2 == 0 ? 54 : 50,
                          strain: baseStrain, resp: i % 2 == 0 ? 14.5 : 13.5))
        }
        days.append(d(29, hrv: todayHrv, rhr: todayRhr, strain: todayStrain, resp: todayResp))
        return days
    }

    /// The same rows with HRV at `hrv` across the last 7 days, the window the label reads.
    private func weekOfHRV(_ hrv: Double, days: [DailyMetric]) -> [DailyMetric] {
        days.enumerated().map { i, m in
            i < days.count - 7 ? m : DailyMetric(day: m.day, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                                 remMin: nil, lightMin: nil, disturbances: nil, restingHr: m.restingHr,
                                                 avgHrv: hrv, recovery: nil, strain: m.strain, exerciseCount: nil,
                                                 spo2Pct: nil, skinTempDevC: nil, respRateBpm: m.respRateBpm)
        }
    }

    func testInsufficientWhenEmpty() {
        XCTAssertEqual(ReadinessEngine.evaluate(days: []).level, .insufficient)
    }

    func testPrimedWhenSignalsAligned() {
        // A week of HRV well above baseline, resting HR below today, load steady.
        let r = ReadinessEngine.evaluate(days: weekOfHRV(72, days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10)))
        XCTAssertEqual(r.level, .primed)
        XCTAssertEqual(r.signals.first { $0.key == "hrv" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "rhr" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .neutral)
        XCTAssertEqual(r.signals.first { $0.key == "hrv" }?.evidence, "72 vs 60 ms")
        XCTAssertEqual(r.signals.first { $0.key == "rhr" }?.evidence, "46 vs 52 bpm")
        // Load evidence is TRIMP recovered from Effort 10: 7201^0.1 − 1 ≈ 1.43.
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.evidence, "7d 1.4 / prior 21d 1.4")
    }

    func testRundownWhenTwoRecoverySignalsDown() {
        // A suppressed HRV week AND resting HR elevated today → two "bad" recovery signals.
        let r = ReadinessEngine.evaluate(days: weekOfHRV(50, days: baseline(todayHrv: 50, todayRhr: 60, todayStrain: 10)))
        XCTAssertEqual(r.level, .rundown)
    }

    func testLoadSpikeIsAPlainComparisonAndSetsNoHeadline() {
        // Recovery signals neutral, this week's load well above the previous three.
        var days: [DailyMetric] = []
        for i in 1...21 { days.append(d(i, hrv: 60, rhr: 52, strain: 5)) }
        for i in 22...28 { days.append(d(i, hrv: 60, rhr: 52, strain: 15)) }
        days.append(d(29, hrv: 60, rhr: 52, strain: 15))
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .neutral)
        XCTAssertEqual(r.level, .balanced)
        XCTAssertNotNil(r.acwr)
        XCTAssertGreaterThan(r.acwr!, 1.5)
    }

    func testRespRateRiseFlags() {
        // Today resp rate well above baseline (~14) → illness-ish watch/bad signal present.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10, todayResp: 18))
        XCTAssertTrue(r.signals.contains { $0.key == "respRate" })
        XCTAssertEqual(r.signals.first { $0.key == "respRate" }?.evidence, "18.0 vs 14.0 rpm")
    }

    func testExplicitTodayWithoutMatchingRowIsInsufficient() {
        // Stale historical import: newest row is 2024-03-29, but the device's real calendar day is later.
        // An explicit `today` with no matching row must read INSUFFICIENT — NOT synthesize off the newest
        // stored (stale) row (issue #23/#24).
        let days = baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10)
        XCTAssertEqual(ReadinessEngine.evaluate(days: days, today: "2026-06-08").level, .insufficient)
        // The day that IS present still computes (no regression for current data).
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days, today: "2024-03-29").level, .insufficient)
        // The legacy no-`today` path is unchanged — still falls back to the most recent row.
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days).level, .insufficient)
    }

    func testStatsHelpers() {
        XCTAssertEqual(ReadinessEngine.mean([2, 4, 6]), 4)
        XCTAssertEqual(ReadinessEngine.sampleSD([2, 4, 6])!, 2.0, accuracy: 0.0001)
        XCTAssertNil(ReadinessEngine.sampleSD([5]))
        XCTAssertNil(ReadinessEngine.mean([]))
    }

    // MARK: - Calendar windows, one rolling HRV label

    /// A row `back` days before 2024-06-30.
    private func row(_ back: Int, hrv: Double?, rhr: Int? = 52, resp: Double? = nil) -> DailyMetric {
        let m = d(1, hrv: hrv, rhr: rhr, strain: 10, resp: resp)
        return DailyMetric(day: Baselines.cutoffKey(todayKey: "2024-06-30", carryDays: back), totalSleepMin: nil,
                           efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                           restingHr: m.restingHr, avgHrv: m.avgHrv, recovery: nil, strain: m.strain,
                           exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: m.respRateBpm)
    }

    func testOneBadNightDoesNotLabelHRV() {
        // Ordinary night-to-night spread (about 15%), one night at half the usual level.
        let days = (1...36).map { row($0, hrv: $0 % 2 == 0 ? 52 : 69) } + [row(0, hrv: 30)]
        let flag = ReadinessEngine.evaluate(days: days).signals.first { $0.key == "hrv" }?.flag
        XCTAssertNotNil(flag)
        XCTAssertNotEqual(flag, .bad)
    }

    func testASuppressedWeekLabelsHRV() {
        var days = (7...36).map { row($0, hrv: $0 % 2 == 0 ? 62 : 58) }
        days += (0...6).map { row($0, hrv: 45) }
        let hrv = ReadinessEngine.evaluate(days: days).signals.first { $0.key == "hrv" }
        XCTAssertEqual(hrv?.flag, .bad)
        XCTAssertEqual(hrv?.evidence, "45 vs 60 ms")
    }

    func testAGapDoesNotPassOldRowsOffAsTheBaseline() {
        // Four months off the strap: everything before the gap is outside the window.
        let old = (120...160).map { row($0, hrv: 60) }
        let r = ReadinessEngine.evaluate(days: old + [row(0, hrv: 60)])
        XCTAssertNil(r.signals.first { $0.key == "hrv" })
        XCTAssertNil(r.signals.first { $0.key == "rhr" })
    }

    func testRespirationZHasASigmaFloor() {
        // An almost flat history must not turn a 0.3 rpm rise into a flag.
        let days = (1...28).map { row($0, hrv: 60, resp: $0 % 2 == 0 ? 14.01 : 14.0) } + [row(0, hrv: 60, resp: 14.3)]
        XCTAssertNil(ReadinessEngine.evaluate(days: days).signals.first { $0.key == "respRate" })
    }

    func testNilRespirationDropsTheTerm() {
        let days = (1...28).map { row($0, hrv: 60, resp: 14) } + [row(0, hrv: 60, resp: nil)]
        XCTAssertNil(ReadinessEngine.evaluate(days: days).signals.first { $0.key == "respRate" })
        let state = Baselines.windowFold((0..<10).map { _ in 60.0 }, dayKeys: (0..<10).map { _ in "" },
                                         cfg: Baselines.hrvCfg, baselineEpoch: 0, logDomain: true)
        let resp = Baselines.windowFold((0..<10).map { _ in 14.0 }, dayKeys: (0..<10).map { _ in "" },
                                        cfg: Baselines.respCfg, baselineEpoch: 0)
        XCTAssertEqual(RecoveryScorer.recovery(hrv: 60, rhr: 50, resp: nil, hrvBaseline: state, rhrBaseline: nil,
                                               respBaseline: resp, sleepPerf: nil),
                       RecoveryScorer.recovery(hrv: 60, rhr: 50, resp: nil, hrvBaseline: state, rhrBaseline: nil,
                                               respBaseline: nil, sleepPerf: nil))
    }
}
