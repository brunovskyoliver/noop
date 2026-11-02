import XCTest
import WhoopProtocol
import WhoopStore
@testable import StrandAnalytics

/// Regressions for the 2026-11 activity and load audit. Synthetic streams only.
final class ActivityLoadAuditTests: XCTestCase {
    private let t0 = 1_800_000_000
    private let profile = UserProfile(weightKg: 66, heightCm: 170, age: 19, sex: "male")

    private func hr(_ from: Int, _ to: Int, _ bpm: Int, step: Int = 1) -> [HRSample] {
        stride(from: from, to: to, by: step).map { HRSample(ts: $0, bpm: bpm) }
    }
    /// Alternating orientation that clears the motion gate.
    private func moving(_ from: Int, _ to: Int) -> [GravitySample] {
        stride(from: from, to: to, by: 1).map { ts in
            ts % 2 == 0 ? GravitySample(ts: ts, x: 0, y: 0, z: 1) : GravitySample(ts: ts, x: 1, y: 0, z: 0)
        }
    }
    private func still(_ from: Int, _ to: Int) -> [GravitySample] {
        stride(from: from, to: to, by: 1).map { GravitySample(ts: $0, x: 0, y: 0, z: 1) }
    }
    private func gait(_ from: Int, _ to: Int) -> [StepSample] {
        stride(from: from, to: to, by: 1).map { StepSample(ts: $0, counter: $0 - from, activityClass: 1) }
    }
    private func idleSteps(_ from: Int, _ to: Int) -> [StepSample] {
        stride(from: from, to: to, by: 1).map { StepSample(ts: $0, counter: 0, activityClass: 0) }
    }
    private func detect(_ h: [HRSample], _ g: [GravitySample], _ s: [StepSample]?) -> [ExerciseSession] {
        WorkoutDetector.detect(hr: h, gravity: g, restingHR: 50, maxHR: 195, age: 19, profile: profile, steps: s)
    }

    // MARK: Stitching

    private func lift(gapMin: Int, gapHR: [HRSample]? = nil, gapSteps: [StepSample]? = nil) -> [ExerciseSession] {
        let aEnd = t0 + 30 * 60, bStart = aEnd + gapMin * 60, bEnd = bStart + 25 * 60
        let h = hr(t0, aEnd, 130) + (gapHR ?? hr(aEnd, bStart, 80)) + hr(bStart, bEnd, 130)
        let g = moving(t0, aEnd) + still(aEnd, bStart) + moving(bStart, bEnd)
        let s = idleSteps(t0, aEnd) + (gapSteps ?? idleSteps(aEnd, bStart)) + idleSteps(bStart, bEnd)
        return detect(h, g, s)
    }

    func testRestInsideASessionIsStitchedAndStatsCoverTheWhole() throws {
        let sessions = lift(gapMin: 13)
        let w = try XCTUnwrap(sessions.first)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(w.end - w.start, (30 + 13 + 25) * 60 - 1, accuracy: 15)
        // 55 min at 130 and 13 min at 80.
        XCTAssertEqual(w.avgHR, (55 * 130 + 13 * 80) / 68.0, accuracy: 1)
        XCTAssertGreaterThan(w.zoneTimePct[0] ?? 0, 10, "the rest counts in the zones")
        let alone = try XCTUnwrap(lift(gapMin: 25).first?.caloriesKcal)
        XCTAssertGreaterThan(try XCTUnwrap(w.caloriesKcal), alone, "energy covers both pieces")
    }

    func testRestOverTheLimitStaysSplit() {
        XCTAssertEqual(lift(gapMin: 25).count, 2)
    }

    func testSustainedWalkBetweenPiecesStaysSplit() {
        let aEnd = t0 + 30 * 60
        XCTAssertEqual(lift(gapMin: 13, gapSteps: gait(aEnd, aEnd + 13 * 60)).count, 2)
    }

    func testADataGapNeverStitches() {
        // Strap saw nothing during the 13 minutes.
        XCTAssertEqual(lift(gapMin: 13, gapHR: []).count, 2)
    }

    func testNoGaitEvidenceDoesNotStitch() {
        let aEnd = t0 + 30 * 60, bStart = aEnd + 13 * 60, bEnd = bStart + 25 * 60
        let h = hr(t0, aEnd, 130) + hr(aEnd, bStart, 80) + hr(bStart, bEnd, 130)
        let g = moving(t0, aEnd) + still(aEnd, bStart) + moving(bStart, bEnd)
        XCTAssertEqual(detect(h, g, nil).count, 2)
    }

    func testAWalkPieceIsNeverStitchedToALift() {
        // Walking, a short rest with no walking in it, then a lift.
        let wEnd = t0 + 20 * 60, lStart = wEnd + 10 * 60, lEnd = lStart + 30 * 60
        let h = hr(t0, wEnd, 72) + hr(wEnd, lStart, 60) + hr(lStart, lEnd, 130)
        let g = moving(t0, wEnd) + still(wEnd, lStart) + moving(lStart, lEnd)
        let s = gait(t0, wEnd) + idleSteps(wEnd, lEnd)
        XCTAssertFalse(detect(h, g, s).contains { $0.start <= t0 + 60 && $0.end >= lStart })
    }

    // MARK: Stats windows and gates

    func testZonesReportTheBackDatedWindow() throws {
        // 10 min warm-up below the HR floor, 30 min of work: the row is 40 min, so its zones must be too.
        let start = t0 + 10 * 60, end = start + 30 * 60
        let h = hr(t0, start, 55) + hr(start, end, 150)
        let w = try XCTUnwrap(detect(h, moving(t0, end), nil).first)
        XCTAssertEqual(w.start, t0, accuracy: 15)
        XCTAssertEqual(try XCTUnwrap(w.zoneTimePct[0]), 25, accuracy: 2)
    }

    func testIntensityGateFailsClosedWithoutUsableHRmax() {
        let h = hr(t0, t0 + 30 * 60, 130)
        let sessions = WorkoutDetector.detect(hr: h, gravity: moving(t0, t0 + 30 * 60), restingHR: 140, maxHR: 120)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testAShortBoutThatQualifiesHasAnEffort() throws {
        let h = hr(t0, t0 + 8 * 60, 150)
        XCTAssertNotNil(try XCTUnwrap(detect(h, moving(t0, t0 + 8 * 60), nil).first).strain)
    }

    // MARK: Auto detector

    func testAutoDetectorClosesTheSpanAcrossASensorGap() {
        // Elevated, then four hours with no samples, then elevated again: 25 Oct 2026.
        let h = (hr(t0, t0 + 20 * 60, 150) + hr(t0 + 4 * 3600, t0 + 4 * 3600 + 20 * 60, 150)).map { (ts: $0.ts, bpm: $0.bpm) }
        let c = AutoWorkoutDetector.detect(hr: h, restingBpm: 50, maxHR: 195)
        XCTAssertFalse(c.contains { $0.endSec - $0.startSec > 3600 })
    }

    // MARK: Backfill

    private func row(zones: String? = nil) -> WorkoutRow {
        WorkoutRow(startTs: t0, endTs: t0 + 3600, sport: "Workout", source: "manual", durationS: 3600,
                   energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: zones,
                   notes: nil, steps: nil)
    }

    func testRowWindowFillAppliesToAFragmentButTotalsStayProtected() {
        let real = row()
        let filled = WorkoutDetector.backfillWorkout(
            real, avgBpm: 130, peakHR: 150, caloriesKcal: 300, strain: 40, zonesJSON: "{\"bout\":1}", steps: 9,
            boutBounds: (t0 + 133)..<(t0 + 3520), rowWindowZonesJSON: "{\"row\":1}", rowWindowSteps: 500)
        XCTAssertEqual(filled.zonesJSON, "{\"row\":1}")
        XCTAssertEqual(filled.steps, 500)
        XCTAssertNil(filled.energyKcal)
        XCTAssertNil(filled.avgHr)
        XCTAssertNil(filled.strain)
    }

    func testRowWindowFillNeedsCoverage() {
        let thin = WorkoutDetector.rowWindowFill(
            startTs: t0, endTs: t0 + 3600, hr: hr(t0, t0 + 600, 130), steps: gait(t0, t0 + 600),
            restingHR: 50, maxHR: 195, ticksPerStep: 1)
        XCTAssertNil(thin.zonesJSON)
        XCTAssertNil(thin.steps)
        let full = WorkoutDetector.rowWindowFill(
            startTs: t0, endTs: t0 + 3600, hr: hr(t0, t0 + 3600, 130), steps: gait(t0, t0 + 3600),
            restingHR: 50, maxHR: 195, ticksPerStep: 2)
        XCTAssertNotNil(full.zonesJSON)
        XCTAssertEqual(full.steps, 1800)
    }

    // MARK: Energy

    private let rest = Calories.restingKcalPerS(Calories.male, weightKg: 66, heightCm: 170, age: 19)

    private func gross(_ bpm: Int) -> Double {
        let vo2 = Calories.vo2maxFor(hrmax: 195, restingHR: 50)
        return Calories.grossKcalPerS(Calories.male, hr: Double(bpm), hrmax: 195, restingHR: 50, restingRate: rest,
                                      weightKg: 66, age: 19, vo2max: vo2)
    }

    func testEnergyCurveIsContinuousAndAnchored() {
        XCTAssertEqual(gross(50), rest, accuracy: 1e-9)
        XCTAssertEqual(gross(40), rest, accuracy: 1e-9)
        let blendEnd = Int(0.60 * 195)   // 117
        XCTAssertLessThan(abs(gross(blendEnd) - gross(blendEnd + 1)), 0.02)
        var previous = gross(50)
        for bpm in 51...195 {
            let g = gross(bpm)
            XCTAssertGreaterThanOrEqual(g, previous)
            XCTAssertLessThan(g - previous, 0.02, "step at \(bpm) bpm")
            previous = g
        }
    }

    func testBMRIsCreditedForTheWholeDayWhateverTheStrapSaw() {
        let oneHour = hr(t0, t0 + 3600, 50)
        let e = Calories.estimateDayEnergy(oneHour, profile: profile, hrmax: 195, restingHR: 50, maxSpanSeconds: 90_000)
        XCTAssertEqual(e.restingKcal, rest * 90_000, accuracy: 0.01, "25 h day")
        XCTAssertEqual(e.observedSeconds, 3600, accuracy: 1, "coverage still reports what was seen")
        let partial = Calories.estimateDayEnergy(oneHour, profile: profile, hrmax: 195, restingHR: 50, creditedSeconds: 7200)
        XCTAssertEqual(partial.restingKcal, rest * 7200, accuracy: 0.01)
    }

    func testAGapCreditsNoActiveEnergy() {
        let h = [HRSample(ts: t0, bpm: 170), HRSample(ts: t0 + 3 * 3600, bpm: 170)]
        // Two readings carry at most one 60 s cadence step each, not three hours.
        XCTAssertLessThan(Calories.estimateDayEnergy(h, profile: profile, hrmax: 195, restingHR: 50).activeKcal, 40)
    }

    func testTiedTimestampsCarryNoTime() {
        let single = hr(t0, t0 + 600, 150)
        let doubled = single.flatMap { [$0, $0] }
        XCTAssertEqual(Calories.estimateBoutCalories(doubled, profile: profile, hrmax: 195, restingHR: 50).0,
                       Calories.estimateBoutCalories(single, profile: profile, hrmax: 195, restingHR: 50).0, accuracy: 0.01)
    }

    func testSexResolverReadsLegacyInitials() {
        XCTAssertEqual(Calories.resolveCoeffs("f").restingAlpha, Calories.female.restingAlpha)
        XCTAssertEqual(Calories.resolveCoeffs("M").restingAlpha, Calories.male.restingAlpha)
        XCTAssertEqual(Calories.resolveCoeffs("").restingAlpha, Calories.nonbinary.restingAlpha)
    }

    // MARK: Zone time

    func testBankedStretchKeepsItsZoneTime() {
        // 60 min at 1 Hz, 30 min banked at 30 s, and a dropout that must not be credited.
        let live = hr(t0, t0 + 3600, 100)
        let banked = hr(t0 + 3600, t0 + 5400, 180, step: 30)
        let later = hr(t0 + 5400 + 3600, t0 + 5400 + 3700, 100)
        let t = HRZones.timeInZone(live + banked + later, zoneSet: HRZones.zones(maxHR: 195))
        XCTAssertEqual(t.seconds[4], 1800, accuracy: 35)
        XCTAssertLessThan(t.seconds.reduce(0, +), 5600)
    }

    // MARK: Training load

    private func metric(_ day: String, _ strain: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: strain,
                    exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil, steps: nil,
                    activeKcalEst: nil)
    }
    private func days(_ n: Int, from start: String = "2026-01-01") -> [String] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        let d = f.date(from: start)!
        return (0..<n).map { f.string(from: d.addingTimeInterval(Double($0) * 86_400)) }
    }

    func testTodayDoesNotCountInTheLoadWindows() throws {
        // Constant load, with today barely started: the comparison must stay level.
        let all = days(40)
        let rows = all.dropLast().map { metric($0, 40) } + [metric(all.last!, 1)]
        let r = ReadinessEngine.evaluate(days: rows)
        XCTAssertEqual(try XCTUnwrap(r.acwr), 1.0, accuracy: 1e-6)
    }

    func testLoadComparisonIsUncoupledAndCarriesNoHeadlineWeight() throws {
        let all = days(40)
        let rows = all.enumerated().map { i, d in metric(d, i >= 32 ? 60 : 20) }
        let r = ReadinessEngine.evaluate(days: rows)
        let signal = try XCTUnwrap(r.signals.first { $0.key == "acwr" })
        XCTAssertEqual(signal.flag, .neutral)
        XCTAssertFalse(signal.detail.lowercased().contains("injury"))
        XCTAssertFalse(signal.detail.lowercased().contains("sweet"))
        XCTAssertNotEqual(r.level, .strained)
        XCTAssertNotEqual(r.level, .rundown)
        let expected = StrainScorer.strainToTrimp(60) / StrainScorer.strainToTrimp(20)
        XCTAssertEqual(try XCTUnwrap(r.acwr), expected, accuracy: 1e-6, "acute week is not inside its baseline")
    }

    func testChronicLoadDecaysThroughAShortGap() throws {
        let all = days(40)
        var loads = all.map { TrainingLoadEngine.DailyLoad(day: $0, load: 100) }
        let unbroken = TrainingLoadEngine.evaluate(days: loads)
        loads.removeSubrange(30..<33)   // three missing days
        let r = TrainingLoadEngine.evaluate(days: loads)
        XCTAssertNotEqual(r.state, .unavailable)
        XCTAssertEqual(r.contiguousDays, 37)
        XCTAssertFalse(r.points.contains { $0.day == all[31] }, "a missing day emits no point")
        let a = try XCTUnwrap(r.points.last), b = try XCTUnwrap(unbroken.points.last)
        XCTAssertLessThan(a.chronicLoad, b.chronicLoad)
        XCTAssertGreaterThan(a.chronicLoad, 80, "history survives the gap")
    }

    func testAGapOfTwoWeeksResetsTheModel() {
        let all = days(50)
        var loads = all.map { TrainingLoadEngine.DailyLoad(day: $0, load: 100) }
        loads.removeSubrange(30..<44)   // 14 missing, 6 left after: under the minimum
        XCTAssertEqual(TrainingLoadEngine.evaluate(days: loads).state, .unavailable)
    }

    func testCardLoadsLeaveTodayOut() {
        let rows = [metric("2026-01-01", 10), metric("2026-01-02", 20)]
        XCTAssertEqual(TrainingLoadEngine.dailyTrimp(rows, before: "2026-01-02").map(\.day), ["2026-01-01"])
    }

    // MARK: Gait streak

    func testGaitStreakSpansTimeAndStopsAtAGap() throws {
        let s = stride(from: t0, to: t0 + 300, by: 2).map { StepSample(ts: $0, counter: 0, activityClass: 1) }
            + stride(from: t0 + 1000, to: t0 + 1100, by: 1).map { StepSample(ts: $0, counter: 0, activityClass: 1) }
        let h = hr(t0, t0 + 1100, 120)
        let f = try XCTUnwrap(WorkoutTypeFeatureExtractor.extract(
            hr: h, gravity: moving(t0, t0 + 1100), steps: s, start: t0, end: t0 + 1100,
            restingHR: 50, maxHR: 195, caloriesKcal: nil, imu: nil))
        XCTAssertEqual(f.gaitStreakSec, 299, accuracy: 2)
    }

    func testAwakeRestingHRIsAPriorMedianThatIgnoresAnImpossibleDay() {
        let floors: [Double?] = [64, 66, nil, 63, 120.7, 65, 64, 113.5, 66]
        XCTAssertEqual(Calories.awakeRestingHR(priorFloors: floors), 65.5)
        XCTAssertNil(Calories.awakeRestingHR(priorFloors: [64, nil]), "too few days: no anchor, not a single day's value")
    }

    func testEnergyAnchorsMoveTheBlendZeroAndVO2OnlyThroughTheProfile() {
        let hr = (0..<3_600).map { HRSample(ts: 1_000 + $0, bpm: 70) }
        let base = UserProfile(weightKg: 66, heightCm: 170, age: 19, sex: "male")
        var anchored = base
        anchored.awakeRestingHR = 70
        func sitting(_ p: UserProfile) -> Double {
            Calories.estimateBoutCalories(hr, profile: p, hrmax: 195, restingHR: 48).0
        }
        XCTAssertGreaterThan(sitting(base), sitting(anchored), "with only the sleeping floor, 70 bpm earns active energy")
        XCTAssertEqual(sitting(anchored), Calories.restingKcalPerS(Calories.resolveCoeffs("male"), weightKg: 66, heightCm: 170, age: 19) * 3_600, accuracy: 0.1,
                       "sitting at the awake resting HR earns BMR only")

        let work = (0..<600).map { HRSample(ts: 1_000 + $0, bpm: 150) }
        var low = base; low.vo2max = 40
        var high = base; high.vo2max = 60
        let kcal = { (p: UserProfile) in Calories.estimateBoutCalories(work, profile: p, hrmax: 195, restingHR: 48).0 }
        // 0.404 kJ/min per ml/kg/min over 20 units for 10 minutes, Keytel's published male coefficient.
        XCTAssertEqual(kcal(high) - kcal(low), 0.404 * 20 / 4.184 * 10, accuracy: 0.2)

        var awakeOnly = base; awakeOnly.awakeRestingHR = 65
        XCTAssertEqual(kcal(awakeOnly), kcal({ var p = base; p.vo2max = 15.3 * 195 / 65; return p }()), accuracy: 0.001,
                       "without a stored VO2max, Uth reads the awake value")
        XCTAssertNotEqual(awakeOnly.cacheKey, base.cacheKey)
    }

    func testDayActiveKeepsTheExerciseGateAndIgnoresTheEnergyAnchors() {
        var p = UserProfile(weightKg: 66, heightCm: 170, age: 19, sex: "male")
        // Gate at 48 + 0.5 * (195 - 48) = 121.5 bpm.
        let walk = (0..<3_600).map { HRSample(ts: 1_000 + $0, bpm: 110) }
        let lift = (0..<3_600).map { HRSample(ts: 1_000 + $0, bpm: 130) }
        func active(_ h: [HRSample]) -> Double {
            Calories.estimateDayEnergy(h, profile: p, hrmax: 195, restingHR: 48).activeKcal
        }
        XCTAssertEqual(active(walk), 0)
        let plain = active(lift)
        XCTAssertGreaterThan(plain, 0)
        p.awakeRestingHR = 64; p.vo2max = 41.86
        XCTAssertEqual(active(lift), plain)
    }
}
