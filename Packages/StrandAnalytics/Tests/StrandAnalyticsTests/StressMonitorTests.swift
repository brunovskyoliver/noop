import XCTest
@testable import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Stress Monitor v2 (StressMonitor.swift): the waking and sleeping level maps, the 14-day references and
/// their cold start, motion masking, the day summary (band minutes, coverage) and Sleep Stress, and the live
/// window. Synthetic inputs recover several injected values each, not one.
final class StressMonitorTests: XCTestCase {

    private let day0 = 1_700_000_000 - (1_700_000_000 % 86_400)   // a UTC midnight

    /// 1 Hz HR over [from, to) at a constant bpm.
    private func hr(_ from: Int, _ to: Int, bpm: Int) -> [HRSample] {
        stride(from: from, to: to, by: 1).map { HRSample(ts: $0, bpm: bpm) }
    }

    /// R-R over [from, to) with a given mean and alternating jitter (RMSSD ≈ 2·jitter).
    private func rr(_ from: Int, _ to: Int, rrMs: Int, jitter: Int) -> [RRInterval] {
        var out: [RRInterval] = []
        var t = from, i = 0
        while t < to {
            out.append(RRInterval(ts: t, rrMs: rrMs + (i % 2 == 0 ? jitter : -jitter)))
            t += max(1, rrMs / 1000); i += 1
        }
        return out
    }

    private func input(hr: [HRSample], rr: [RRInterval] = [], gravity: [GravitySample] = [],
                       sleep: [StressMonitor.Interval] = [], main: StressMonitor.Interval? = nil,
                       workouts: [StressMonitor.Interval] = [], dayEnd: Int? = nil) -> StressMonitor.DayInput {
        StressMonitor.DayInput(day: "2023-11-14", dayStart: day0, dayEnd: dayEnd ?? day0 + 86_400,
                               tzOffsetSeconds: 0, hr: hr, rr: rr, gravity: gravity,
                               sleepWindows: sleep, mainSleep: main, activityWindows: workouts)
    }

    func testSparseNightDoesNotPretendToRepresentWholeSleep() {
        let main = StressMonitor.Interval(start: day0, end: day0 + 8 * 3600)
        let result = StressMonitor.analyzeDay(input(hr: hr(day0, day0 + 3600, bpm: 70),
                                                   sleep: [main], main: main),
                                               priorFloors: [], priorNights: [])
        XCTAssertNil(result.summary.sleepStressPct)
    }

    func testAllExerciseCannotEstablishCalmBaseline() {
        let workout = StressMonitor.Interval(start: day0 + 8 * 3600, end: day0 + 18 * 3600)
        let result = StressMonitor.analyzeDay(input(hr: hr(workout.start, workout.end, bpm: 130),
                                                   workouts: [workout]), priorFloors: [], priorNights: [])
        XCTAssertNil(result.wakeFloorAggregate)
        XCTAssertNil(result.wake)
        XCTAssertFalse(result.summary.hasWaking)
    }

    // MARK: - Level maps

    func testWakeLevelAnchors() {
        XCTAssertEqual(StressMonitor.wakeLevel(meanHR: 60, floorHR: 60), 1.0, accuracy: 1e-9)
        XCTAssertEqual(StressMonitor.wakeLevel(meanHR: 67.5, floorHR: 60), 1.5, accuracy: 1e-9)
        XCTAssertEqual(StressMonitor.wakeLevel(meanHR: 75, floorHR: 60), 2.0, accuracy: 1e-9)
        XCTAssertLessThan(StressMonitor.wakeLevel(meanHR: 50, floorHR: 60), 0.5)
        XCTAssertGreaterThan(StressMonitor.wakeLevel(meanHR: 100, floorHR: 60), 2.8)
    }

    func testWakeLevelRecoversSeveralElevationsMonotonically() {
        let deltas: [Double] = [-10, -5, 0, 5, 10, 15, 20, 30]
        let levels = deltas.map { StressMonitor.wakeLevel(meanHR: 62 + $0, floorHR: 62) }
        for (a, b) in zip(levels, levels.dropFirst()) { XCTAssertLessThan(a, b) }
        // The same elevation reads the same on a different floor: the map is personal, not absolute.
        for d in deltas {
            XCTAssertEqual(StressMonitor.wakeLevel(meanHR: 50 + d, floorHR: 50),
                           StressMonitor.wakeLevel(meanHR: 72 + d, floorHR: 72), accuracy: 1e-12)
        }
    }

    func testSleepLevelAnchors() {
        XCTAssertEqual(StressMonitor.sleepLevel(z: 0), 0.4, accuracy: 1e-9)
        XCTAssertEqual(StressMonitor.sleepLevel(z: 3), 2.0, accuracy: 1e-9)
        XCTAssertLessThan(StressMonitor.sleepLevel(z: -2), 0.4)
    }

    func testSleepZUsesHRVWhenBothSidesHaveIt() {
        let ref = StressMonitor.NightAggregate(hr: 52, hrSpread: 2, lnRMSSD: log(60), lnRMSSDSpread: 0.2)
        // HR at reference, RMSSD at reference → 0.
        XCTAssertEqual(StressMonitor.sleepZ(meanHR: 52, rmssd: 60, ref: ref), 0, accuracy: 1e-9)
        // HR +4 (z 2) and RMSSD suppressed by e^-0.4 (z 2) → (2+2)/√2.
        XCTAssertEqual(StressMonitor.sleepZ(meanHR: 56, rmssd: 60 * exp(-0.4), ref: ref),
                       4 / 2.0.squareRoot(), accuracy: 1e-9)
        // No epoch RMSSD → HR only.
        XCTAssertEqual(StressMonitor.sleepZ(meanHR: 56, rmssd: nil, ref: ref), 2, accuracy: 1e-9)
    }

    // MARK: - References

    func testWakeReferenceIsTheMedianOfTheLast14Days() {
        // 16 older days at 80 then 14 recent days at 60: only the recent 14 count.
        let priors: [Double?] = Array(repeating: 80, count: 16) + Array(repeating: 60, count: 14)
        let ref = StressMonitor.wakeReference(priorFloors: priors, todayFloor: 70)
        XCTAssertEqual(ref?.floorHR, 60)
        XCTAssertEqual(ref?.personal, true)
        XCTAssertEqual(ref?.days, 14)
        // A robust median: one wild day does not move it.
        let noisy: [Double?] = [60, 61, 62, 150, 60, 61, nil, 62]
        XCTAssertEqual(StressMonitor.wakeReference(priorFloors: noisy, todayFloor: nil)?.floorHR, 61)
    }

    func testWakeReferenceColdStartFallsBackToTheDaysOwnFloor() {
        let ref = StressMonitor.wakeReference(priorFloors: [60, nil, 62], todayFloor: 70)
        XCTAssertEqual(ref?.floorHR, 70)
        XCTAssertEqual(ref?.personal, false)
        XCTAssertNil(StressMonitor.wakeReference(priorFloors: [60, 62], todayFloor: nil))
    }

    func testSleepReferenceNeedsFourNightsOfHRVForTheHRVHalf() {
        let withHRV = StressMonitor.NightAggregate(hr: 50, hrSpread: 2, lnRMSSD: 4, lnRMSSDSpread: 0.2)
        let hrOnly = StressMonitor.NightAggregate(hr: 54, hrSpread: 3, lnRMSSD: nil, lnRMSSDSpread: nil)
        let ref = StressMonitor.sleepReference(priorNights: [withHRV, withHRV, withHRV, hrOnly, hrOnly], tonight: nil)
        XCTAssertEqual(ref?.personal, true)
        XCTAssertNil(ref?.night.lnRMSSD, "only 3 nights carried R-R → HR-only reference")
        let ref2 = StressMonitor.sleepReference(priorNights: Array(repeating: withHRV, count: 5), tonight: nil)
        XCTAssertEqual(ref2?.night.lnRMSSD, 4)
    }

    // MARK: - Day summary: band minutes recovered exactly

    func testBandMinutesAndMeanRecoverInjectedStretches() {
        // Floor 60 from 14 prior days. Today: 120 min at 50 bpm (low), 180 min at 65 (medium), 60 min at 80
        // (high), all between 09:00 and 15:00 on the day grid.
        let t = day0 + 9 * 3600
        let samples = hr(t, t + 7200, bpm: 50) + hr(t + 7200, t + 18_000, bpm: 65) + hr(t + 18_000, t + 21_600, bpm: 80)
        let priors: [Double?] = Array(repeating: 60, count: 14)
        let r = StressMonitor.analyzeDay(input(hr: samples), priorFloors: priors, priorNights: [])
        XCTAssertEqual(r.summary.lowMin, 120)
        XCTAssertEqual(r.summary.medMin, 180)
        XCTAssertEqual(r.summary.highMin, 60)
        XCTAssertEqual(r.summary.scoredMin, 360)
        let expected = (24 * StressMonitor.wakeLevel(meanHR: 50, floorHR: 60)
            + 36 * StressMonitor.wakeLevel(meanHR: 65, floorHR: 60)
            + 12 * StressMonitor.wakeLevel(meanHR: 80, floorHR: 60)) / 72
        XCTAssertEqual(r.summary.meanLevel!, expected, accuracy: 1e-9)
        XCTAssertTrue(r.wake!.personal)
        XCTAssertEqual(r.latest?.level ?? 0, StressMonitor.wakeLevel(meanHR: 80, floorHR: 60), accuracy: 1e-9)
    }

    func testTooLittleWakingTimeWritesNoWakingKeys() {
        let t = day0 + 10 * 3600
        let r = StressMonitor.analyzeDay(input(hr: hr(t, t + 20 * 60, bpm: 65)),
                                         priorFloors: Array(repeating: 60, count: 14), priorNights: [])
        XCTAssertNil(r.summary.meanLevel)
        XCTAssertEqual(r.summary.scoredMin, 0)
        XCTAssertTrue(r.summary.storedPairs.isEmpty)
    }

    func testSparseEpochsAreNoData() {
        // 30 samples per 5 minutes (half the gate) → nothing scored.
        let t = day0 + 10 * 3600
        let sparse = stride(from: t, to: t + 7200, by: 10).map { HRSample(ts: $0, bpm: 70) }
        let r = StressMonitor.analyzeDay(input(hr: sparse), priorFloors: Array(repeating: 60, count: 14), priorNights: [])
        XCTAssertEqual(r.summary.scoredMin, 0)
        XCTAssertTrue(r.epochs.allSatisfy { $0.state == .noData })
    }

    // MARK: - Motion

    func testWorkoutAndShadowAreMaskedNotStress() {
        // 10:00–11:00 workout at 140 bpm, then 10 minutes at 110 (shadow), then calm 62 to 13:00.
        let t = day0 + 10 * 3600
        let samples = hr(t, t + 3600, bpm: 140) + hr(t + 3600, t + 4200, bpm: 110) + hr(t + 4200, t + 3 * 3600, bpm: 62)
        let r = StressMonitor.analyzeDay(input(hr: samples, workouts: [.init(start: t, end: t + 3600)]),
                                         priorFloors: Array(repeating: 60, count: 14), priorNights: [])
        let active = r.epochs.filter { $0.state == .activity }.count
        XCTAssertEqual(active, 12 + 2, "the hour of exercise plus two shadow epochs")
        XCTAssertEqual(r.summary.highMin, 0, "exertion never reads as stress")
        XCTAssertEqual(r.summary.scoredMin, 110)
    }

    func testAmbulatoryGravityIsMasked() {
        // One hour of walking-level wrist motion at 1 Hz, HR 95: masked; the next calm hour scores.
        let t = day0 + 14 * 3600
        let grav = stride(from: t, to: t + 3600, by: 1).map { i -> GravitySample in
            GravitySample(ts: i, x: i % 2 == 0 ? 0.0 : 0.5, y: 0, z: 1)
        }
        let samples = hr(t, t + 3600, bpm: 95) + hr(t + 3600 + 1200, t + 7200 + 1200, bpm: 62)
        let r = StressMonitor.analyzeDay(input(hr: samples, gravity: grav),
                                         priorFloors: Array(repeating: 60, count: 14), priorNights: [])
        XCTAssertEqual(r.epochs.filter { $0.state == .activity }.count, 12)
        XCTAssertEqual(r.summary.highMin, 0)
        XCTAssertEqual(r.summary.scoredMin, 60)
    }

    // MARK: - Sleep Stress

    /// A night 23:00 (previous day) → 07:00 at 50 bpm with R-R, where the first `elevatedMin` minutes of
    /// the second half run +`bump` bpm.
    private func night(elevatedMin: Int, bump: Int = 20) -> (hr: [HRSample], rr: [RRInterval], main: StressMonitor.Interval) {
        let s = day0 - 3600, e = day0 + 7 * 3600
        let mid = s + 4 * 3600
        var h = hr(s, mid, bpm: 50) + hr(mid, mid + elevatedMin * 60, bpm: 50 + bump)
        h += hr(mid + elevatedMin * 60, e, bpm: 50)
        // Tiny per-epoch jitter so the robust spread is realistic, not zero.
        h = h.map { HRSample(ts: $0.ts, bpm: $0.bpm + (($0.ts / 300) % 3) - 1) }
        return (h, [], .init(start: s, end: e))
    }

    private func personalNights() -> [StressMonitor.NightAggregate?] {
        Array(repeating: StressMonitor.NightAggregate(hr: 50, hrSpread: 2, lnRMSSD: nil, lnRMSSDSpread: nil), count: 14)
    }

    func testSleepStressRecoversSeveralInjectedShares() {
        // 480-minute nights; 0, 60, 120 and 180 elevated minutes → 0 %, 12.5 %, 25 %, 37.5 %. (The grain is
        // 5 minutes: a stretch that ends mid-epoch rounds up, since a partly elevated epoch still reads high.)
        for (minutes, pct) in [(0, 0.0), (60, 12.5), (120, 25.0), (180, 37.5)] {
            let n = night(elevatedMin: minutes)
            let r = StressMonitor.analyzeDay(input(hr: n.hr, sleep: [n.main], main: n.main),
                                             priorFloors: [], priorNights: personalNights())
            XCTAssertEqual(r.summary.sleepStressPct ?? -1, pct, accuracy: 0.01, "elevated \(minutes) min")
            XCTAssertTrue(r.sleep!.personal)
        }
    }

    func testTypicalSleepSitsBelowHalf() {
        let n = night(elevatedMin: 0)
        let r = StressMonitor.analyzeDay(input(hr: n.hr, sleep: [n.main], main: n.main),
                                         priorFloors: [], priorNights: personalNights())
        let sleepLevels = r.epochs.filter { $0.state == .sleep }.compactMap(\.level)
        XCTAssertFalse(sleepLevels.isEmpty)
        XCTAssertLessThan(sleepLevels.reduce(0, +) / Double(sleepLevels.count), 0.5)
        // Sleep epochs never count as waking minutes.
        XCTAssertEqual(r.summary.scoredMin, 0)
    }

    func testSuppressedNightHRVRaisesSleepStress() {
        // HR flat at the reference; RMSSD normal (≈80 ms) in the first half, crushed (≈10 ms) in the second.
        let s = day0 - 3600, e = day0 + 7 * 3600, mid = s + 4 * 3600
        let h = hr(s, e, bpm: 50)
        let r1 = rr(s, mid, rrMs: 1200, jitter: 40) + rr(mid, e, rrMs: 1200, jitter: 5)
        let ref = StressMonitor.NightAggregate(hr: 50, hrSpread: 2, lnRMSSD: log(80), lnRMSSDSpread: 0.2)
        let main = StressMonitor.Interval(start: s, end: e)
        let r = StressMonitor.analyzeDay(input(hr: h, rr: r1, sleep: [main], main: main),
                                         priorFloors: [], priorNights: Array(repeating: ref, count: 14))
        XCTAssertEqual(r.summary.sleepStressPct ?? 0, 50, accuracy: 3)
        // Same night without R-R reads calm (HR-only).
        let r2 = StressMonitor.analyzeDay(input(hr: h, sleep: [main], main: main),
                                          priorFloors: [], priorNights: Array(repeating: ref, count: 14))
        XCTAssertEqual(r2.summary.sleepStressPct ?? -1, 0, accuracy: 0.01)
    }

    func testNightColdStartScoresAgainstItsOwnAggregate() {
        let n = night(elevatedMin: 60, bump: 25)
        let r = StressMonitor.analyzeDay(input(hr: n.hr, sleep: [n.main], main: n.main),
                                         priorFloors: [], priorNights: [])
        XCTAssertEqual(r.sleep?.personal, false)
        XCTAssertNotNil(r.nightAggregate)
        XCTAssertEqual(r.summary.sleepStressPct ?? -1, 12.5, accuracy: 0.01, "60 of 480 min elevated")
    }

    func testShortNightReportsNoSleepStress() {
        let s = day0 + 3600, main = StressMonitor.Interval(start: s, end: s + 50 * 60)
        let r = StressMonitor.analyzeDay(input(hr: hr(s, s + 50 * 60, bpm: 50), sleep: [main], main: main),
                                         priorFloors: [], priorNights: personalNights())
        XCTAssertNil(r.summary.sleepStressPct)
    }

    // MARK: - Stored contract

    func testStoredPairsRoundTrip() {
        let s = StressDaySummary(day: "2026-01-02", meanLevel: 1.234, highMin: 40, medMin: 300, lowMin: 120,
                                 scoredMin: 460, sleepStressPct: 7.25)
        let pairs = s.storedPairs
        XCTAssertEqual(pairs.map(\.key), StressDaySummary.Key.all)
        let back = StressDaySummary.fromStored(day: s.day, values: Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) }))
        XCTAssertEqual(back?.meanLevel ?? 0, 1.23, accuracy: 1e-9)
        XCTAssertEqual(back?.highMin, 40)
        XCTAssertEqual(back?.scoredMin, 460)
        XCTAssertEqual(back?.sleepStressPct ?? 0, 7.3, accuracy: 1e-9)
        XCTAssertEqual(StressDaySummary.Key.all, ["stress_day", "stress_high_min", "stress_med_min",
                                                  "stress_low_min", "stress_scored_min", "sleep_stress_pct"])
        XCTAssertNil(StressDaySummary.fromStored(day: "x", values: [:]))
    }

    // MARK: - Live

    func testLiveReadingRecoversLevelsAndFlagsActivity() {
        let ref = StressMonitor.WakeReference(floorHR: 60, personal: true, days: 14)
        for (bpm, expected) in [(60.0, 1.0), (67.5, 1.5), (75.0, 2.0)] {
            guard case let .level(l)? = StressMonitor.liveReading(hrWindow: Array(repeating: bpm, count: 120), wake: ref)
            else { return XCTFail("expected a level at \(bpm)") }
            XCTAssertEqual(l, expected, accuracy: 1e-9)
        }
        XCTAssertEqual(StressMonitor.liveReading(hrWindow: Array(repeating: 100, count: 120), wake: ref), .active)
        XCTAssertNil(StressMonitor.liveReading(hrWindow: Array(repeating: 70, count: 30), wake: ref))
        XCTAssertNil(StressMonitor.liveReading(hrWindow: Array(repeating: 0, count: 300), wake: ref),
                     "implausible samples are dropped")
    }
}

/// Rest v2 (RestPerformanceV2.swift).
final class RestV2Tests: XCTestCase {
    typealias R = AnalyticsEngine.RestV2

    private func dm(day: String, totalSleepMin: Double?, efficiency: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: totalSleepMin, efficiency: efficiency, deepMin: nil,
                               remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                               recovery: nil, strain: nil, exerciseCount: nil)
    }

    func testWeightsSumToOneAndSufficiencyDominates() {
        XCTAssertEqual(R.wSufficiency + R.wConsistency + R.wEfficiency + R.wSleepStress, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(R.wSufficiency, R.wConsistency + R.wEfficiency + R.wSleepStress - 1e-9)
    }

    func testCompositeRecoversKnownValues() {
        // All full → 100; everything half → 50; a specific mix.
        XCTAssertEqual(R.composite(.init(sufficiency: 1, consistency: 1, efficiency: 1, sleepStress: 1)), 100)
        XCTAssertEqual(R.composite(.init(sufficiency: 0.5, consistency: 0.5, efficiency: 0.5, sleepStress: 0.5)), 50)
        XCTAssertEqual(R.composite(.init(sufficiency: 0.8, consistency: 0.6, efficiency: 0.9, sleepStress: 1)),
                       (0.55 * 0.8 + 0.15 * 0.6 + 0.15 * 0.9 + 0.15 * 1) * 100, accuracy: 0.01)
    }

    func testMissingPartsRenormalise() {
        // No sleep stress: (0.55·0.8 + 0.15·0.6 + 0.15·0.9) / 0.85.
        let v = R.composite(.init(sufficiency: 0.8, consistency: 0.6, efficiency: 0.9, sleepStress: nil))
        XCTAssertEqual(v, (0.55 * 0.8 + 0.15 * 0.6 + 0.15 * 0.9) / 0.85 * 100, accuracy: 0.01)
        // Only the required parts: (0.55·0.8 + 0.15·0.9) / 0.70.
        let w = R.composite(.init(sufficiency: 0.8, consistency: nil, efficiency: 0.9, sleepStress: nil))
        XCTAssertEqual(w, (0.55 * 0.8 + 0.15 * 0.9) / 0.70 * 100, accuracy: 0.01)
        // A night whose missing parts would have been perfect never scores lower for being unmeasured than
        // the same night with those parts at the others' average.
        XCTAssertEqual(R.composite(.init(sufficiency: 0.7, consistency: nil, efficiency: 0.7, sleepStress: nil)), 70)
    }

    func testSleepStressCredit() {
        XCTAssertEqual(R.sleepStressCredit(pct: 0), 1)
        XCTAssertEqual(R.sleepStressCredit(pct: 15), 0.5, accuracy: 1e-12)
        XCTAssertEqual(R.sleepStressCredit(pct: 30), 0)
        XCTAssertEqual(R.sleepStressCredit(pct: 80), 0)
    }

    func testDailyGateAndPercentEfficiency() {
        let d = dm(day: "2026-01-01", totalSleepMin: 480, efficiency: 90)   // imported: percent
        let expected: Double = (0.55 + 0.15 * 0.9) / 0.70 * 100
        XCTAssertEqual(R.composite(daily: d, needHours: 8) ?? -1, expected, accuracy: 0.01)
        let f = dm(day: "2026-01-01", totalSleepMin: 480, efficiency: 0.9)  // computed: fraction
        XCTAssertEqual(R.composite(daily: f, needHours: 8), R.composite(daily: d, needHours: 8))
        XCTAssertNil(R.composite(daily: dm(day: "x", totalSleepMin: 0, efficiency: 0.9)))
        XCTAssertNil(R.composite(daily: dm(day: "x", totalSleepMin: 400, efficiency: nil)))
    }

    private func night(_ bed: Int, _ wake: Int, _ daysBefore: Int, base: Int = 1_700_000_000) -> R.Night {
        // bed/wake as minutes relative to base (tonight's midnight), shifted back by daysBefore days.
        R.Night(start: base + bed * 60 - daysBefore * 86_400, end: base + wake * 60 - daysBefore * 86_400,
                daysBefore: daysBefore)
    }

    func testConsistencyRecoversKnownShifts() {
        let tonight = night(-60, 420, 0)                      // 23:00 → 07:00
        let same = (1...4).map { night(-60, 420, $0) }
        XCTAssertEqual(R.consistency(tonight: tonight, previous: same) ?? 0, 1, accuracy: 1e-12)
        // Every previous night 1 h later at both ends: |Δ| = 2 h → A = 22/24 → 2A−1 = 0.8333.
        let late1 = (1...4).map { night(0, 480, $0) }
        XCTAssertEqual(R.consistency(tonight: tonight, previous: late1) ?? 0, 1 - 4.0 / 24, accuracy: 1e-9)
        // 2 h later at both ends → 1 − 8/24.
        let late2 = (1...4).map { night(60, 540, $0) }
        XCTAssertEqual(R.consistency(tonight: tonight, previous: late2) ?? 0, 1 - 8.0 / 24, accuracy: 1e-9)
        // Nights further back than 4 are ignored; fewer than 2 usable → nil.
        XCTAssertNil(R.consistency(tonight: tonight, previous: [night(-60, 420, 1), night(-60, 420, 6)]))
    }

    func testConsistencyFeedsTheScore() {
        let d = dm(day: "x", totalSleepMin: 420, efficiency: 0.9)
        let good = R.composite(daily: d, needHours: 8, consistency: 1, sleepStressPct: 0)!
        let bad = R.composite(daily: d, needHours: 8, consistency: 0.3, sleepStressPct: 25)!
        XCTAssertGreaterThan(good, bad)
        XCTAssertEqual(good - bad, (0.15 * 0.7 + 0.15 * (1 - R.sleepStressCredit(pct: 25))) * 100, accuracy: 0.02)
    }
}
