import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class WorkoutDetectorTests: XCTestCase {

    // MARK: - Activity series

    func testActivitySeriesFirstIsZero() {
        let grav = [
            GravitySample(ts: 0, x: 0, y: 0, z: 1),
            GravitySample(ts: 1, x: 0.3, y: 0, z: 1),  // Δ = 0.3
            GravitySample(ts: 2, x: 0.3, y: 0, z: 1),  // Δ = 0
        ]
        let series = WorkoutDetector.activitySeries(grav)
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].intensity, 0.0, accuracy: 1e-9)
        XCTAssertEqual(series[1].intensity, 0.3, accuracy: 1e-9)
        XCTAssertEqual(series[2].intensity, 0.0, accuracy: 1e-9)
    }

    func testActivitySeriesEmpty() {
        XCTAssertTrue(WorkoutDetector.activitySeries([]).isEmpty)
    }

    // MARK: - Calories

    func testCaloriesActiveAndRestingMale() {
        // 600 active samples at 150 bpm, male 80 kg 30 y, hrmax 190, RHR 60. With a resting HR known,
        // the Keytel FITNESS-adjusted model runs (Uth VO2max = 15.3·190/60 = 48.45): 58.5503 kJ/min ×
        // 600 s / 251.04 = 139.9386 kcal. (The base fitness-blind model gave 146.972.) MUST match the
        // Kotlin twin Vo2maxCaloriesTest.caloriesActiveAndRestingMale_matchesSwiftGolden.
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, kj) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        XCTAssertEqual(kcal, 139.9386, accuracy: 0.1)
        XCTAssertEqual(kj, kcal * 4.184, accuracy: 1e-6)
    }

    func testCaloriesRestingBelowThreshold() {
        // HR below the 30% HRR active threshold → BMR rate (small per-sample).
        // Threshold = 60 + 0.30*(190-60) = 99. bpm 80 < 99 → resting.
        let hr = (0..<86400).map { HRSample(ts: $0, bpm: 80) }  // a full "day" of resting
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, _) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        // 86400 s at BMR rate ≈ full BMR ≈ 1853.6 kcal/day.
        XCTAssertEqual(kcal, 1853.632, accuracy: 1.0)
    }

    func testCaloriesSexCoefficientsDiffer() {
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let male = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male"),
            hrmax: 190, restingHR: 60).0
        let female = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "female"),
            hrmax: 190, restingHR: 60).0
        XCTAssertNotEqual(male, female, accuracy: 0.0)
    }

    // MARK: - Detection

    /// A workout: high HR + sustained motion for `durationS`, embedded in a rest day.
    private func workoutDay(workoutStart: Int, workoutDur: Int) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = workoutStart - 30 * 60
        let dayEnd = workoutStart + workoutDur + 30 * 60
        for t in dayStart..<dayEnd {
            let inWorkout = t >= workoutStart && t < workoutStart + workoutDur
            // Resting periods: HR 55, still gravity. Workout: HR 165, moving gravity.
            hr.append(HRSample(ts: t, bpm: inWorkout ? 165 : 55))
            if inWorkout {
                let phase = Double((t - workoutStart) % 2) * 0.5  // 0.5 g oscillation → moving
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still
            }
        }
        return (hr, grav)
    }

    func testDetectFindsWorkout() {
        let start = 5_000_000
        let dur = 20 * 60  // 20 min
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        let w = sessions[0]
        XCTAssertEqual(w.avgHR, 165, accuracy: 1.0)
        XCTAssertEqual(w.peakHR, 165)
        XCTAssertGreaterThan(w.durationS, Double(15 * 60))
        // Zone breakdown sums to ~100.
        let total = w.zoneTimePct.values.reduce(0, +)
        XCTAssertEqual(total, 100.0, accuracy: 0.5)
        XCTAssertEqual(w.hrmaxSource, "tanaka")  // age supplied, thin observed history
    }

    func testDetectWithProfileEstimatesCalories() {
        let start = 6_000_000
        let dur = 20 * 60
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30, profile: profile)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].caloriesKcal)
        XCTAssertGreaterThan(sessions[0].caloriesKcal!, 0)
    }

    func testDetectRejectsShortBout() {
        let start = 7_000_000
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: 3 * 60)  // 3 min < 5
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    func testDetectEmptyStreams() {
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: [], age: 30).isEmpty)
        let grav = [GravitySample(ts: 0, x: 0, y: 0, z: 1)]
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: grav, age: 30).isEmpty)
    }

    func testDetectRejectsLowIntensityBlip() {
        // Moving + slightly elevated HR but dominated by zone 0/1 (HR just over floor).
        // resting derived ~55, floor = 70. HR 75 is above floor but at ~15% HRR (zone 0).
        let start = 8_000_000
        let dur = 20 * 60
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = start - 30 * 60
        let dayEnd = start + dur + 30 * 60
        for t in dayStart..<dayEnd {
            let inBout = t >= start && t < start + dur
            hr.append(HRSample(ts: t, bpm: inBout ? 75 : 55))
            if inBout {
                let phase = Double((t - start) % 2) * 0.5
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
            }
        }
        // age 30 → hrmax 187, zone math available → z2+ fraction ≈ 0 < 0.50 → rejected.
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    // MARK: - Sustained-effort fragmentation (#303)

    /// A long endurance bout (e.g. a road bike ride) that dips momentarily every few
    /// minutes — coasting downhill, a junction, a brief sensor gap — so that motion
    /// falls below threshold for a `dipS`-long stretch on a `cadenceS` cadence. HR
    /// stays elevated throughout (you don't actually rest). Helper returns a full day
    /// with the ride embedded in rest, plus the true ride span for assertions.
    private func longRideWithDips(
        rideStart: Int, rideDur: Int, cadenceS: Int, dipS: Int
    ) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = rideStart - 30 * 60
        let dayEnd = rideStart + rideDur + 30 * 60
        for t in dayStart..<dayEnd {
            let inRide = t >= rideStart && t < rideStart + rideDur
            // Coasting dip: the last `dipS` seconds of every `cadenceS`-second cycle.
            let phaseInCycle = (t - rideStart) % cadenceS
            let coasting = inRide && phaseInCycle >= cadenceS - dipS
            // HR stays high the whole ride (a real dip in cadence ≠ a dip in HR).
            hr.append(HRSample(ts: t, bpm: inRide ? 150 : 52))
            if inRide && !coasting {
                let osc = Double((t - rideStart) % 2) * 0.5  // pedalling → moving
                grav.append(GravitySample(ts: t, x: osc, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still / coasting
            }
        }
        return (hr, grav)
    }

    func testLongRideWithBriefDipsIsOneWorkout() {
        // ~4 h ride (matches the issue: 13:00–16:52) with a ~2-min coasting dip every
        // ~8 min. Each dip exceeds the OLD 150 s merge gap, so it used to shatter the
        // ride into ~30 sub-5-min slivers, most of which were then dropped by the
        // minimum-duration filter — surfacing as a handful of tiny "workouts".
        let start = 9_000_000
        let rideDur = 232 * 60      // 3 h 52 m
        let (hr, grav) = longRideWithDips(
            rideStart: start, rideDur: rideDur, cadenceS: 8 * 60, dipS: 180)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)

        // One ride → one workout, spanning ~the whole ride (not a pile of fragments).
        XCTAssertEqual(sessions.count, 1, "sustained ride fragmented into \(sessions.count) workouts")
        let w = sessions[0]
        XCTAssertGreaterThan(w.durationS, Double(rideDur) * 0.9,
                             "merged ride too short: \(Int(w.durationS))s of \(rideDur)s")
        XCTAssertEqual(w.avgHR, 150, accuracy: 2.0)
    }

    func testGenuinelySeparateWorkoutsStaySeparate() {
        // Two real workouts separated by a long genuine rest (HR drops to resting and
        // motion stops for ~25 min) must NOT be merged by the bridge. Guards against
        // the fix over-merging unrelated sessions.
        let startA = 10_000_000
        let durA = 20 * 60
        let restGap = 25 * 60               // 25 min true rest, well beyond the bridge
        let startB = startA + durA + restGap
        let durB = 20 * 60
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = startA - 30 * 60
        let dayEnd = startB + durB + 30 * 60
        for t in dayStart..<dayEnd {
            let inA = t >= startA && t < startA + durA
            let inB = t >= startB && t < startB + durB
            let active = inA || inB
            hr.append(HRSample(ts: t, bpm: active ? 160 : 52))
            if active {
                let osc = Double(t % 2) * 0.5
                grav.append(GravitySample(ts: t, x: osc, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
            }
        }
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 2, "separate workouts were over-merged")
    }

    func testWarmupBeforeHrRisesBackdatesStartToMotionOnset() {
        // #148: motion (walking / cycling) starts, but HR lags ~10 min behind during cardiac
        // warm-up. The HR-AND-motion gate used to clip that warm-up, dropping the first ~10 min
        // (the reporter's "way there not tracked, way back tracked"). Motion is continuous from
        // onset, so a confirmed run's start must back-date to the motion onset, not the HR crossing.
        let motionStart = 12_000_000
        let warmupS = 10 * 60   // moving, HR still ~resting (below the floor) → used to be clipped
        let coreS = 20 * 60     // moving, HR elevated → the HR-gated core
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = motionStart - 30 * 60
        let dayEnd = motionStart + warmupS + coreS + 30 * 60
        for t in dayStart..<dayEnd {
            let inWarm = t >= motionStart && t < motionStart + warmupS
            let inCore = t >= motionStart + warmupS && t < motionStart + warmupS + coreS
            let moving = inWarm || inCore
            hr.append(HRSample(ts: t, bpm: inCore ? 150 : (inWarm ? 60 : 52)))
            let phase = moving ? Double(t % 2) * 0.5 : 0.0
            grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
        }
        // resting 52 → floor 67: warm-up 60 is below it (clipped without the fix), core 150 clears it.
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 52, age: 30)
        XCTAssertEqual(sessions.count, 1)
        let w = sessions[0]
        XCTAssertLessThanOrEqual(w.start, motionStart + 120,
            "start \(w.start) not back-dated to motion onset \(motionStart) (HR crossed ~\(motionStart + warmupS))")
        XCTAssertGreaterThanOrEqual(w.durationS, Double(warmupS + coreS) * 0.9,
            "duration \(Int(w.durationS))s still excludes the warm-up")
    }

    func testBackdateDoesNotCrossPreviousWorkoutContinuousMotion() {
        // #148 guard: you keep walking the whole time (motion never stops), but HR spikes, dips to
        // resting for a few minutes, then spikes again → two separate efforts (bridgeRuns won't merge
        // across an HR-to-resting lull). Back-dating the second effort must NOT walk its start across
        // the still-moving lull into the first one — the two sessions must stay non-overlapping.
        let startA = 13_000_000
        let durA = 15 * 60
        let lull = 6 * 60          // HR at resting, but STILL WALKING
        let durB = 15 * 60
        let moveEnd = startA + durA + lull + durB
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = startA - 30 * 60
        let dayEnd = moveEnd + 30 * 60
        for t in dayStart..<dayEnd {
            let inA = t >= startA && t < startA + durA
            let inB = t >= startA + durA + lull && t < moveEnd
            let moving = t >= startA && t < moveEnd   // continuous through the lull
            hr.append(HRSample(ts: t, bpm: (inA || inB) ? 155 : 52))
            grav.append(GravitySample(ts: t, x: moving ? Double(t % 2) * 0.5 : 0.0, y: 0, z: 1))
        }
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 52, age: 30)
        XCTAssertEqual(sessions.count, 2, "continuous-motion lull did not split into two efforts")
        XCTAssertGreaterThan(sessions[1].start, sessions[0].end,
            "second workout (\(sessions[1].start)) overlaps the first (ends \(sessions[0].end))")
    }

    // MARK: - Elevated cores of a diluted run (2026-09-23)

    /// A day of moving HR segments `(seconds, bpm)` starting at `start`, framed by 10 still minutes at 55
    /// bpm either side. Motion is on for every segment, so the whole stretch forms one bridged run.
    private func movingDay(start: Int, _ segs: [(Int, Int)]) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = [], grav: [GravitySample] = []
        var t = start - 600
        for _ in 0..<600 { hr.append(HRSample(ts: t, bpm: 55)); grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1)); t += 1 }
        for (dur, bpm) in segs {
            for _ in 0..<dur {
                hr.append(HRSample(ts: t, bpm: bpm))
                grav.append(GravitySample(ts: t, x: Double(t % 2) * 0.5, y: 0, z: 1))
                t += 1
            }
        }
        for _ in 0..<600 { hr.append(HRSample(ts: t, bpm: 55)); grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1)); t += 1 }
        return (hr, grav)
    }

    /// Ten sets of 150 s at 125 bpm with 90 s rests at 95 bpm (40 min), the shape of a lifting session.
    private let liftSets: [(Int, Int)] = Array(repeating: [(150, 125), (90, 95)], count: 10).flatMap { $0 }

    /// The field case (2026-09-21): a 40 min lift bridged onto an afternoon of pottering at 90 bpm reads
    /// ~18% above the activity floor as a whole run and used to be dropped outright. Its elevated core
    /// must now qualify on its own, starting at the first set rather than back-dated over the pottering.
    func testLiftDilutedByPotteringIsKeptAsItsElevatedCore() {
        let start = 9_000_000
        let (hr, grav) = movingDay(start: start, [(3000, 90)] + liftSets + [(3000, 90)])
        var f: WorkoutDetector.DetectionFunnel?
        // rest 60, HRmax 190 → activity floor 112, zone-2 floor 138: the sets clear only the first.
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190,
                                              funnel: { f = $0 })
        XCTAssertEqual(sessions.count, 1, "\(String(describing: f))")
        let liftStart = start + 3000
        XCTAssertEqual(sessions[0].start, liftStart, "core must start at the first set, not the pottering")
        XCTAssertEqual(sessions[0].end, liftStart + 2400 - 90 - 1, "core ends with the last set")
        XCTAssertTrue(sessions[0].isActivityTier)
        XCTAssertEqual(f?.splitRuns, 1)
        XCTAssertEqual(f?.splitKept, 1)
        XCTAssertEqual(f?.droppedLowIntensity, 0)
    }

    /// A stretch below the floor longer than `bridgeGapS` ends a core, so two efforts separated by an
    /// eight-minute easy spell come back as two sessions, not one.
    func testLongDipSplitsElevatedCores() {
        let (hr, grav) = movingDay(start: 9_500_000,
                                   [(3600, 90), (1200, 125), (480, 90), (1200, 125), (3600, 90)])
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertGreaterThan(sessions[1].start, sessions[0].end)
    }

    /// A brief elevated blip is no core worth keeping: the run stays dropped as low intensity.
    func testShortElevatedBlipIsStillDroppedAsLowIntensity() {
        let (hr, grav) = movingDay(start: 9_900_000, [(3600, 90), (180, 125), (3600, 90)])
        var f: WorkoutDetector.DetectionFunnel?
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190,
                                              funnel: { f = $0 })
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(f?.droppedLowIntensity, 1)
        XCTAssertEqual(f?.splitRuns, 0)
    }

    // MARK: - Gait tags (2026-09-26)

    /// `movingDay` plus a step stream that tags the listed segment indices as walk (class 1), all
    /// other seconds still.
    private func movingDay(start: Int, _ segs: [(Int, Int)], gait: Set<Int>)
        -> (hr: [HRSample], grav: [GravitySample], steps: [StepSample]) {
        let (hr, grav) = movingDay(start: start, segs)
        var bounds: [(Int, Int)] = []
        var t = start
        for (dur, _) in segs { bounds.append((t, t + dur)); t += dur }
        let steps = grav.map { g in
            StepSample(ts: g.ts, counter: 0,
                       activityClass: bounds.indices.contains { gait.contains($0) && g.ts >= bounds[$0].0 && g.ts < bounds[$0].1 } ? 1 : 0)
        }
        return (hr, grav, steps)
    }

    /// A walk with the arm held still (hands in pockets) leaves the gravity delta flat. The strap's gait
    /// tag alone must carry it through the motion gate.
    func testQuietArmWalkIsDetectedFromGaitTags() {
        let start = 10_000_000
        let hr = (0..<1800).map { HRSample(ts: start + $0, bpm: 120) }
        let grav = (0..<1800).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }
        let steps = (0..<1800).map { StepSample(ts: start + $0, counter: $0, activityClass: 1) }
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190).isEmpty)
        let s = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190, steps: steps)
        XCTAssertEqual(s.count, 1)
        XCTAssertGreaterThan(s[0].durationS, 1700)
    }

    /// The field case (2026-09-26): the walk to the gym bridged onto the lift and the whole bout was
    /// classified walk. The walk is cut off at its end and the lift comes back on its own.
    func testWalkToTheGymIsCutOffTheLift() {
        let start = 11_000_000
        let (hr, grav, steps) = movingDay(start: start, [(900, 118)] + liftSets, gait: [0])
        var f: WorkoutDetector.DetectionFunnel?
        let s = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190,
                                       funnel: { f = $0 }, steps: steps)
        XCTAssertEqual(s.count, 2, "\(String(describing: f))")
        XCTAssertEqual(s[1].start, start + 900, "the lift starts where the walk ends")
        XCTAssertLessThanOrEqual(s[0].end, start + 900)
        XCTAssertEqual(f?.splitRuns, 1)
        XCTAssertEqual(f?.splitKept, 2)
    }

    /// A walk with a three-minute stop is one walk, not two.
    func testWalkWithAStopStaysWhole() {
        let (hr, grav, steps) = movingDay(start: 12_000_000, [(1200, 118), (180, 118), (1200, 118)], gait: [0, 2])
        let s = WorkoutDetector.detect(hr: hr, gravity: grav, restingHR: 60, maxHR: 190, steps: steps)
        XCTAssertEqual(s.count, 1)
        XCTAssertGreaterThan(s[0].durationS, 2500)
    }

    func testGaitPieces() {
        let start = 13_000_000
        // 15 walking minutes, then 20 without gait.
        let walk = Array(start..<(start + 900))
        let pieces = WorkoutDetector.gaitPieces(start: start, end: start + 2099, gaitTs: walk)
        XCTAssertEqual(pieces?.map(\.0), [start, start + 900])
        XCTAssertEqual(pieces?.last?.1, start + 2099)
        // A sprint the strap tagged as walk is part of the session, not a way into it.
        XCTAssertNil(WorkoutDetector.gaitPieces(start: start, end: start + 2099, gaitTs: walk,
                                                isWalkPace: { _, _ in false }))
        // Under ten minutes of anything else beside the walk: nothing to cut.
        XCTAssertNil(WorkoutDetector.gaitPieces(start: start, end: start + 1400, gaitTs: walk))
        // No streak of five walking minutes: nothing to cut.
        XCTAssertNil(WorkoutDetector.gaitPieces(start: start, end: start + 2099, gaitTs: Array(walk.prefix(240))))
    }
}
