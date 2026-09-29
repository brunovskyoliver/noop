import XCTest
@testable import StrandAnalytics

final class EnergyReservoirTests: XCTestCase {
    typealias ER = EnergyReservoir
    typealias SM = StressMonitor
    let heart = ER.HeartProfile(restingHR: 60, maxHR: 190)   // HRR 130: 126 bpm = zone 1, 140 = zone 2
    let t0 = 1_700_000_000
    let perEpochH = Double(SM.epochSeconds) / 3600

    /// (state, level, meanHR, epochs, inMainSleep)
    typealias Seg = (SM.EpochState, Double?, Double?, Int, Bool)

    func day(_ segs: [Seg], personal: Bool = true, day: String = "2026-09-01", start: Int? = nil) -> SM.DayResult {
        var ts = start ?? t0
        var epochs: [SM.Epoch] = []
        for (state, level, hr, n, main) in segs {
            for _ in 0..<n {
                epochs.append(.init(startTs: ts, state: state, level: level, meanHR: hr, rmssd: nil, inMainSleep: main))
                ts += SM.epochSeconds
            }
        }
        let night = SM.NightAggregate(hr: 55, hrSpread: 3, lnRMSSD: 4, lnRMSSDSpread: 0.2)
        return SM.DayResult(day: day, epochs: epochs, wake: .init(floorHR: 62, personal: personal, days: 14),
                            sleep: .init(night: night, personal: personal, nights: 14),
                            summary: .init(day: day, meanLevel: nil, highMin: 0, medMin: 0, lowMin: 0,
                                           scoredMin: 0, sleepStressPct: nil),
                            wakeFloorAggregate: nil, nightAggregate: nil)
    }

    func testCalmNightRecoversInjectedStartsAndQuietDayRecoversInjectedLevels() {
        let n = 96   // 8 h
        for s in [5.0, 20, 40, 65, 90] {
            let r = ER.day(day([(.sleep, 0.3, 55, n, true)]), startLevel: s, heart: heart)!
            let expect = 100 - (100 - s) * pow(1 - ER.kSleepPerHour * perEpochH, Double(n))
            XCTAssertEqual(r.summary.end, expect, accuracy: 1e-9)
            // Invert the night back to its injected start.
            let back = 100 - (100 - r.summary.end) / pow(1 - ER.kSleepPerHour * perEpochH, Double(n))
            XCTAssertEqual(back, s, accuracy: 1e-9)
        }
        // A waking hour at level L costs baseline + stressCost·(L−1); recover each injected L from the drain.
        for l in [1.0, 1.4, 2.0, 2.7] {
            let r = ER.day(day([(.waking, l, 80, 12, false)]), startLevel: 90, heart: heart)!
            let perHour = r.summary.drained
            XCTAssertEqual(1 + (perHour - ER.baselinePerHour) / ER.stressCostPerHour, l, accuracy: 1e-9)
            XCTAssertEqual(r.summary.end, 90 - perHour, accuracy: 1e-9)
        }
        // A restless night (level 1.2 → q = 0.5) charges less than a calm one.
        let calm = ER.day(day([(.sleep, 0.4, 55, n, true)]), startLevel: 40, heart: heart)!.summary.end
        let restless = ER.day(day([(.sleep, 1.2, 60, n, true)]), startLevel: 40, heart: heart)!.summary.end
        XCTAssertGreaterThan(calm, restless + 10)
        XCTAssertEqual(ER.day(day([(.sleep, 2.5, 70, n, true)]), startLevel: 40, heart: heart)!.summary.end, 40)
    }

    func testTypicalDayAndNightRoughlyBalance() {
        let d = ER.day(day([(.waking, 1.0, 70, 108, false), (.waking, 1.5, 80, 36, false), (.waking, 2.3, 90, 6, false),
                            (.activity, nil, 140, 12, false), (.waking, 0.6, 62, 18, false)]),
                       startLevel: 92, heart: heart)!
        XCTAssertEqual(d.summary.drained, 55, accuracy: 3)
        let night = ER.day(day([(.sleep, 0.4, 55, 96, true)]), startLevel: 40, heart: heart)!
        XCTAssertEqual(night.summary.charged, 52, accuracy: 3)
    }

    func testHighStressDrainsFasterThanLow() {
        let low = ER.day(day([(.waking, 1.1, 70, 24, false)]), startLevel: 80, heart: heart)!.summary
        let high = ER.day(day([(.waking, 2.6, 95, 24, false)]), startLevel: 80, heart: heart)!.summary
        XCTAssertGreaterThan(high.drained, low.drained * 2)
        XCTAssertGreaterThan(high.drainStress, 0)
        XCTAssertEqual(low.drainBaseline, high.drainBaseline, accuracy: 1e-9)
    }

    func testExerciseDrainsThroughTrimpOnly() {
        // 1 h in zone 2 (weight 2): 0.1·2·60 activity + 2 baseline; no stress booked.
        let z2 = ER.day(day([(.activity, 2.8, 140, 12, false)]), startLevel: 80, heart: heart)!.summary
        XCTAssertEqual(z2.drainActivity, ER.trimpCost * 2 * 60, accuracy: 1e-9)
        XCTAssertEqual(z2.drainStress, 0)
        XCTAssertEqual(z2.drained, ER.trimpCost * 2 * 60 + ER.baselinePerHour, accuracy: 1e-9)
        // Zone 4 costs twice zone 2; below zone 1 only the baseline.
        let z4 = ER.day(day([(.activity, nil, 166, 12, false)]), startLevel: 80, heart: heart)!.summary
        XCTAssertEqual(z4.drainActivity, 2 * z2.drainActivity, accuracy: 1e-9)
        let easy = ER.day(day([(.activity, nil, 100, 12, false)]), startLevel: 80, heart: heart)!.summary
        XCTAssertEqual(easy.drainActivity, 0); XCTAssertEqual(easy.drained, ER.baselinePerHour, accuracy: 1e-9)
    }

    func testGapsHoldTheLevelFlat() {
        let r = ER.day(day([(.waking, 1.5, 80, 6, false), (.noData, nil, nil, 24, false),
                            (.sleep, nil, nil, 6, true)]), startLevel: 70, heart: heart)!
        let afterAwake = r.points[5].level
        XCTAssertTrue(r.points[6...].allSatisfy { $0.level == afterAwake && $0.kind == .gap })
    }

    func testCarryOverAcrossMidnightAndWakeLevel() {
        let d1 = ER.day(day([(.waking, 1.2, 75, 144, false), (.sleep, 0.4, 55, 24, true)]), startLevel: nil, heart: heart)!
        XCTAssertTrue(d1.summary.seeded)
        XCTAssertEqual(d1.summary.start, ER.seedLevel)
        let d2 = ER.day(day([(.sleep, 0.4, 55, 72, true), (.waking, 1.2, 75, 12, false)], day: "2026-09-02",
                            start: t0 + 168 * SM.epochSeconds), startLevel: d1.summary.end, heart: heart)!
        XCTAssertFalse(d2.summary.seeded)
        XCTAssertEqual(d2.summary.start, d1.summary.end)
        // One continuous 9 h night split at midnight ends where the same night in one piece ends.
        let whole = ER.day(day([(.sleep, 0.4, 55, 96, true)]), startLevel: d1.points[143].level, heart: heart)!
        XCTAssertEqual(d2.points[71].level, whole.summary.end, accuracy: 1e-9)
        XCTAssertEqual(d2.summary.wake!, d2.points[71].level, accuracy: 1e-9)
        XCTAssertNil(ER.day(day([(.waking, 1.2, 75, 12, false)]), startLevel: 50, heart: heart)!.summary.wake)
    }

    func testClampedToZeroAndHundred() {
        let drained = ER.day(day([(.waking, 3.0, 110, 288, false)]), startLevel: 10, heart: heart)!
        XCTAssertEqual(drained.summary.end, 0)
        XCTAssertEqual(drained.summary.drained, 10, accuracy: 1e-9)   // only what was actually spent
        let full = ER.day(day([(.sleep, 0.2, 50, 288, true)]), startLevel: 99, heart: heart)!
        XCTAssertLessThanOrEqual(full.summary.peak, 100)
        XCTAssertTrue(full.points.allSatisfy { (0...100).contains($0.level) })
        XCTAssertEqual(ER.day(day([]), startLevel: 150, heart: heart)!.summary.end, 100)
    }

    func testColdStartIsNil() {
        XCTAssertNil(ER.day(day([(.sleep, 0.4, 55, 12, true)], personal: false), startLevel: 50, heart: heart))
    }

    func testRestRechargeNeedsTenCalmStillMinutes() {
        let one = ER.day(day([(.waking, 0.5, 62, 1, false)]), startLevel: 50, heart: heart)!.summary
        XCTAssertEqual(one.charged, 0)
        let run = ER.day(day([(.waking, 0.5, 62, 6, false)]), startLevel: 50, heart: heart)!.summary
        XCTAssertGreaterThan(run.charged, 0)
        // Interrupted by movement, the run restarts.
        let broken = ER.day(day([(.waking, 0.5, 62, 1, false), (.activity, nil, 90, 1, false),
                                 (.waking, 0.5, 62, 1, false)]), startLevel: 50, heart: heart)!.summary
        XCTAssertEqual(broken.charged, 0)
    }

    func testStoredRoundTripAndLiveProjection() {
        let s = ER.day(day([(.sleep, 0.4, 55, 48, true), (.waking, 1.3, 75, 24, false)]), startLevel: 33, heart: heart)!.summary
        var v: [String: Double] = [:]
        for p in s.storedPairs { v[p.key] = p.value }
        let back = EnergyDaySummary.fromStored(day: s.day, values: v)!
        XCTAssertEqual(back.end, s.end, accuracy: 0.005); XCTAssertEqual(back.wake!, s.wake!, accuracy: 0.005)
        XCTAssertEqual(back.drained, s.drained, accuracy: 0.02)
        XCTAssertNil(EnergyDaySummary.fromStored(day: s.day, values: [:]))
        XCTAssertEqual(ER.projectNow(level: 60, minutesSinceLastEpoch: 3, liveLevel: nil, heart: heart), 60)
        XCTAssertLessThan(ER.projectNow(level: 60, minutesSinceLastEpoch: 3, liveLevel: 2, heart: heart), 60)
    }
}
