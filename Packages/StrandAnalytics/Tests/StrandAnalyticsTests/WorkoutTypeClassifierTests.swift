import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Synthetic-fixture tests for the coarse `WorkoutTypeClassifier` (and its `WorkoutClassFeatures`
/// scoring directly). Per the CLAUDE.md derived-signal validation rule, each class is exercised with
/// MULTIPLE distinct injected patterns rather than one lucky example, plus an ambiguous window that
/// must NOT get a confident specific label.
///
/// Real-world validation against labeled workouts (Oura-import `workout.sport` ground truth) is an
/// explicit, separate follow-up — these fixtures only prove the heuristic recovers the shapes it was
/// designed around.
final class WorkoutTypeClassifierTests: XCTestCase {

    // MARK: - Feature-vector builder (keeps test cases terse and readable)

    private func features(durationMin: Double = 30,
                          meanHR: Double, peakHR: Int, meanHRRPct: Double?, hrCV: Double,
                          stillFraction: Double = 0, walkFraction: Double = 0, runFraction: Double = 0,
                          tickCoverage: Double = 0,
                          gaitStreakSec: Double = 0, gaitCadencePerSec: Double? = nil,
                          motionVariance: Double, motionCV: Double = 0.5,
                          kcalPerMin: Double?) -> WorkoutClassFeatures {
        WorkoutClassFeatures(
            durationSec: durationMin * 60, meanHR: meanHR, peakHR: peakHR, meanHRRPct: meanHRRPct,
            hrCV: hrCV, stillFraction: stillFraction, walkFraction: walkFraction, runFraction: runFraction,
            tickCoverage: tickCoverage, gaitStreakSec: gaitStreakSec,
            gaitCadencePerSec: gaitCadencePerSec,
            motionVariance: motionVariance, motionCV: motionCV,
            kcalPerMin: kcalPerMin)
    }

    // MARK: - RUN: two distinct injected patterns

    func testRunShapedWindow_dominantRunTicks_isClassifiedRun() {
        // Dominant run-classified ticks sustained in one streak, elevated %HRR, higher-impact
        // motion, smooth (low-CV) HR, and a counter cadence in the running band.
        let f = features(meanHR: 155, peakHR: 168, meanHRRPct: 70, hrCV: 0.04,
                         stillFraction: 0.05, walkFraction: 0.1, runFraction: 0.8, tickCoverage: 0.9,
                         gaitStreakSec: 900, gaitCadencePerSec: 3.0,
                         motionVariance: 0.20, kcalPerMin: 11)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .run, "scores: \(out.scores)")
        XCTAssertGreaterThan(out.confidence, 0.4)
    }

    func testRunShapedWindow_noTicks_fallsBackToHRAndMotion() {
        // No activity-class ticks at all (e.g. a WHOOP 4.0 capture) — must still read RUN from the
        // HR+motion fallback alone (high %HRR, smooth HR, high-impact motion).
        let f = features(meanHR: 160, peakHR: 172, meanHRRPct: 72, hrCV: 0.03,
                         tickCoverage: 0, motionVariance: 0.25, kcalPerMin: 12)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .run, "scores: \(out.scores)")
    }

    // MARK: - WALK: two distinct injected patterns, incl. the "low-HR walk" from the brief

    func testLowHRWalk_isClassifiedWalk() {
        // The brief's canonical case: a low-HR walk. Dominant walk ticks sustained in one streak,
        // LOW %HRR, modest motion, counter cadence in the walking band.
        let f = features(meanHR: 96, peakHR: 104, meanHRRPct: 22, hrCV: 0.05,
                         stillFraction: 0.1, walkFraction: 0.85, runFraction: 0.05, tickCoverage: 0.9,
                         gaitStreakSec: 1500, gaitCadencePerSec: 1.8,
                         motionVariance: 0.03, kcalPerMin: 3.5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .walk, "scores: \(out.scores)")
        XCTAssertGreaterThan(out.confidence, 0.4)
    }

    func testBriskWalk_higherHR_stillClassifiedWalk() {
        // A brisker walk: higher (but not run-level) %HRR, still dominant walk ticks and streak.
        let f = features(meanHR: 118, peakHR: 128, meanHRRPct: 38, hrCV: 0.04,
                         stillFraction: 0.05, walkFraction: 0.9, runFraction: 0.05, tickCoverage: 0.85,
                         gaitStreakSec: 1400, gaitCadencePerSec: 2.0,
                         motionVariance: 0.05, kcalPerMin: 5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .walk, "scores: \(out.scores)")
    }

    func testInterruptedWalk_partialTickFraction_stillClassifiedWalk() {
        // The reported 2026-09-22 ~18:08 shape: a 47-min walk where pauses (shops, crossings)
        // split the gait ticks — only 44% walk / 56% still — but the longest contiguous gait
        // streak and the counter cadence still read as a real walk, not gym between-sets movement.
        let f = features(durationMin: 47, meanHR: 104, peakHR: 128, meanHRRPct: 22, hrCV: 0.10,
                         stillFraction: 0.56, walkFraction: 0.44, runFraction: 0, tickCoverage: 0.9,
                         gaitStreakSec: 900, gaitCadencePerSec: 1.75,
                         motionVariance: 0.05, kcalPerMin: 3.5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .walk, "scores: \(out.scores)")
    }

    func testGymWalkTicksWithoutStreak_isNotClassifiedWalk() {
        // The failure mode the streak feature exists for: a lifting session whose between-sets
        // wandering reads as ~45% walk ticks but never sustains a contiguous gait streak and moves
        // at shuffle cadence. Walk-fraction alone would call this a walk; the streak must kill it.
        let f = features(durationMin: 50, meanHR: 128, peakHR: 160, meanHRRPct: 45, hrCV: 0.15,
                         stillFraction: 0.55, walkFraction: 0.45, runFraction: 0, tickCoverage: 0.9,
                         gaitStreakSec: 60, gaitCadencePerSec: 1.35,
                         motionVariance: 0.28, kcalPerMin: 5.5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertNotEqual(out.predictedClass, .walk, "scores: \(out.scores)")
        XCTAssertEqual(out.predictedClass, .strength, "scores: \(out.scores)")
    }

    // MARK: - STRENGTH: two distinct injected patterns, incl. the "high-HR low-cadence" case

    func testHighHRLowCadenceWindow_isClassifiedStrength() {
        // The brief's canonical case: high HR, no walk/run gait ("low cadence"), bursty sets-then-rest
        // HR pattern, HIGH wrist-motion variance (explosive reps — field data: lifting reads
        // ~0.25-0.36 where walks read 0.05-0.15), lower sustained burn rate than continuous cardio.
        let f = features(meanHR: 140, peakHR: 172, meanHRRPct: 65, hrCV: 0.18,
                         stillFraction: 0.85, walkFraction: 0.05, runFraction: 0.05, tickCoverage: 0.9,
                         gaitStreakSec: 45, motionVariance: 0.30, kcalPerMin: 5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .strength, "scores: \(out.scores)")
        XCTAssertGreaterThan(out.confidence, 0.3)
    }

    func testModerateHRBurstySets_isClassifiedStrength() {
        // A gentler lifting session: moderate %HRR (not a cardio spike), still bursty HR, short
        // incidental gait streaks only, moderate motion variance.
        let f = features(meanHR: 110, peakHR: 145, meanHRRPct: 42, hrCV: 0.14,
                         stillFraction: 0.8, walkFraction: 0.1, runFraction: 0.1, tickCoverage: 0.7,
                         gaitStreakSec: 90, motionVariance: 0.15, kcalPerMin: 4)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .strength, "scores: \(out.scores)")
    }

    // MARK: - CYCLE: two distinct injected patterns

    func testSteadyCycle_isClassifiedCycle() {
        // No gait ticks or streak, smooth (low-CV) sustained elevated HR, low motion variance
        // (stable torso).
        let f = features(meanHR: 145, peakHR: 158, meanHRRPct: 60, hrCV: 0.03,
                         stillFraction: 0.9, walkFraction: 0.05, runFraction: 0.05, tickCoverage: 0.9,
                         gaitStreakSec: 30, motionVariance: 0.015, kcalPerMin: 9)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .cycle, "scores: \(out.scores)")
        XCTAssertGreaterThan(out.confidence, 0.3)
    }

    func testEasySpin_noTicksAtAll_isClassifiedCycle() {
        // No activity-class data whatsoever (tickCoverage 0) — must not be penalized as if "no gait"
        // were disproven; HR+motion alone should still read CYCLE (smooth, stable, moderate HR).
        let f = features(meanHR: 120, peakHR: 132, meanHRRPct: 40, hrCV: 0.04,
                         tickCoverage: 0, motionVariance: 0.01, kcalPerMin: 6)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .cycle, "scores: \(out.scores)")
    }

    // MARK: - SKI: two distinct injected patterns

    func testDownhillSkiSession_isClassifiedSki() {
        // A multi-HOUR session (ski days run long — the key separator from a gym session), almost
        // no gait ticks, lift-ride stillness interleaved with runs, high posture/motion variance
        // (turns/terrain), wide intermittent HR, cardio-level burn.
        let f = features(durationMin: 120, meanHR: 128, peakHR: 165, meanHRRPct: 55, hrCV: 0.16,
                         stillFraction: 0.55, walkFraction: 0.08, runFraction: 0.02, tickCoverage: 0.6,
                         gaitStreakSec: 20, motionVariance: 0.30, kcalPerMin: 8)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .ski, "scores: \(out.scores)")
    }

    func testSkiSession_lighterDay_isClassifiedSki() {
        // A gentler ski day: lower average HRR (more time on lifts / easy runs) but the same
        // long-duration, high-variance, intermittent signature.
        let f = features(durationMin: 150, meanHR: 108, peakHR: 150, meanHRRPct: 42, hrCV: 0.17,
                         stillFraction: 0.60, walkFraction: 0.08, runFraction: 0.02, tickCoverage: 0.5,
                         gaitStreakSec: 30, motionVariance: 0.25, kcalPerMin: 6.5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(out.predictedClass, .ski, "scores: \(out.scores)")
    }

    // MARK: - Ambiguous → low confidence / other

    func testAmbiguousWindow_isOtherOrLowConfidence() {
        // Deliberately doesn't match any prototype well: mid-band %HRR (too hot for walk, too cool
        // for run), near-motionless, no ticks. The closest shape is a cycle (smooth, stable, elevated)
        // but nothing should reach a confident verdict.
        let f = features(meanHR: 118, peakHR: 135, meanHRRPct: 55, hrCV: 0.06,
                         tickCoverage: 0, motionVariance: 0.01, kcalPerMin: 5.2)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertTrue(out.predictedClass == .other || out.confidence < 0.4,
                      "expected .other or low confidence, got \(out.predictedClass) @ \(out.confidence), scores: \(out.scores)")
    }

    func testVeryThinData_lowConfidence() {
        // Minimal window, no ticks, no resolvable %HRR (nil) — whatever the guess, confidence must be
        // damped by the missing inputs, never reading as fully confident.
        let f = features(meanHR: 100, peakHR: 110, meanHRRPct: nil, hrCV: 0.05,
                         tickCoverage: 0, motionVariance: 0.02, kcalPerMin: nil)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertLessThan(out.confidence, 0.7, "confidence should be damped by missing HRR/tick data")
    }

    // MARK: - Confidence sanity: a clean signature should outrank an ambiguous one

    func testCleanSignatureIsMoreConfidentThanAmbiguous() {
        let clean = features(meanHR: 96, peakHR: 104, meanHRRPct: 22, hrCV: 0.05,
                             stillFraction: 0.1, walkFraction: 0.85, runFraction: 0.05, tickCoverage: 0.9,
                             gaitStreakSec: 1500, gaitCadencePerSec: 1.8,
                             motionVariance: 0.03, kcalPerMin: 3.5)
        let ambiguous = features(meanHR: 118, peakHR: 135, meanHRRPct: 55, hrCV: 0.06,
                                 tickCoverage: 0, motionVariance: 0.01, kcalPerMin: 5.2)
        let cleanOut = WorkoutTypeClassifier.classify(clean)
        let ambiguousOut = WorkoutTypeClassifier.classify(ambiguous)
        XCTAssertGreaterThan(cleanOut.confidence, ambiguousOut.confidence)
    }

    // MARK: - `scores` always covers all five concrete classes, never `.other`

    func testScoresCoverAllConcreteClassesNeverOther() {
        let f = features(meanHR: 120, peakHR: 140, meanHRRPct: 40, hrCV: 0.06, motionVariance: 0.05,
                         kcalPerMin: 5)
        let out = WorkoutTypeClassifier.classify(f)
        XCTAssertEqual(Set(out.scores.keys), Set([.walk, .run, .strength, .cycle, .ski]))
        XCTAssertNil(out.scores[.other])
        for (_, v) in out.scores {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: - HeuristicWorkoutClassifier (protocol seam) matches the static namespace

    func testHeuristicWorkoutClassifierMatchesStaticClassify() {
        let f = features(meanHR: 96, peakHR: 104, meanHRRPct: 22, hrCV: 0.05,
                         stillFraction: 0.1, walkFraction: 0.85, runFraction: 0.05, tickCoverage: 0.9,
                         motionVariance: 0.03, kcalPerMin: 3.5)
        let viaProtocol: any WorkoutTypeClassifying = HeuristicWorkoutClassifier()
        XCTAssertEqual(viaProtocol.classify(f), WorkoutTypeClassifier.classify(f))
    }
}

/// Tests for `WorkoutTypeFeatureExtractor` — building a `WorkoutClassFeatures` from raw decoded
/// streams (`HRSample`, `GravitySample`, `StepSample`), the same stores `WorkoutDetector` reads.
final class WorkoutTypeFeatureExtractorTests: XCTestCase {

    private func hrBlock(_ start: Int, _ durS: Int, _ bpm: Int) -> [HRSample] {
        (0..<durS).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    private func gravityBlock(_ start: Int, _ durS: Int, deltaMag: Double) -> [GravitySample] {
        // Alternate x between 0 and deltaMag each second so activitySeries' L2 delta ≈ deltaMag per step.
        (0..<durS).map { i in
            GravitySample(ts: start + i, x: (i % 2 == 0) ? 0 : deltaMag, y: 0, z: 1)
        }
    }

    private func stepBlock(_ start: Int, _ durS: Int, activityClass: Int) -> [StepSample] {
        (0..<durS).map { StepSample(ts: start + $0, counter: $0, activityClass: activityClass) }
    }

    func testExtractRunWindow_recoversRunDominantComposition() {
        let start = 1_000_000, dur = 20 * 60
        let hr = hrBlock(start, dur, 160)
        let gravity = gravityBlock(start, dur, deltaMag: 0.4)
        let steps = stepBlock(start, dur, activityClass: 2)  // 2 = run
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: gravity, steps: steps,
                                                     start: start, end: start + dur,
                                                     restingHR: 60, maxHR: 190, caloriesKcal: 240)
        XCTAssertNotNil(f)
        guard let f else { return }
        XCTAssertEqual(f.runFraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(f.tickCoverage, 1.0, accuracy: 0.05)
        // Every tick is gait-classified and the counter increments by 1 each tick: full-window
        // streak, cadence 1.0.
        XCTAssertEqual(f.gaitStreakSec, Double(dur), accuracy: 1)
        XCTAssertEqual(f.gaitCadencePerSec ?? 0, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(f.meanHRRPct ?? 0, 50)
        XCTAssertGreaterThan(f.motionVariance, 0)
        XCTAssertEqual(f.kcalPerMin ?? 0, 12.0, accuracy: 0.01)
        // Round-trips into a RUN classification end-to-end.
        XCTAssertEqual(WorkoutTypeClassifier.classify(f).predictedClass, .run, "scores: \(WorkoutTypeClassifier.classify(f).scores)")
    }

    func testExtractWalkWindow_recoversWalkDominantComposition() {
        let start = 2_000_000, dur = 30 * 60
        let hr = hrBlock(start, dur, 95)
        let gravity = gravityBlock(start, dur, deltaMag: 0.05)
        let steps = stepBlock(start, dur, activityClass: 1)  // 1 = walk
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: gravity, steps: steps,
                                                     start: start, end: start + dur,
                                                     restingHR: 60, maxHR: 180, caloriesKcal: 105)
        XCTAssertNotNil(f)
        guard let f else { return }
        XCTAssertEqual(f.walkFraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(WorkoutTypeClassifier.classify(f).predictedClass, .walk, "scores: \(WorkoutTypeClassifier.classify(f).scores)")
    }

    func testExtractWithNoStepData_tickCoverageIsZero() {
        // No StepSample rows at all in the window (pre-#316 firmware / WHOOP 4.0) — tickCoverage must
        // read 0, not crash or divide-by-zero, and the fractions must be 0 (not NaN).
        let start = 3_000_000, dur = 15 * 60
        let hr = hrBlock(start, dur, 150)
        let gravity = gravityBlock(start, dur, deltaMag: 0.3)
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: gravity, steps: [],
                                                     start: start, end: start + dur)
        XCTAssertNotNil(f)
        guard let f else { return }
        XCTAssertEqual(f.tickCoverage, 0)
        XCTAssertEqual(f.stillFraction, 0)
        XCTAssertEqual(f.walkFraction, 0)
        XCTAssertEqual(f.runFraction, 0)
        XCTAssertEqual(f.gaitStreakSec, 0)
        XCTAssertNil(f.gaitCadencePerSec)
        XCTAssertFalse(f.hrCV.isNaN)
        XCTAssertFalse(f.motionVariance.isNaN)
    }

    func testExtractMixedTicks_gaitStreakIsLongestContiguousRun() {
        // still/walk/still/walk blocks — the streak must be the LONGEST gait run (the second walk
        // block), not the total walk tick count. This is the feature that separates a real walk
        // from a gym session's between-sets wandering.
        let start = 3_500_000, dur = 30 * 60
        let hr = hrBlock(start, dur, 100)
        var steps: [StepSample] = []
        for i in 0..<dur {
            let cls: Int
            switch i {
            case 0..<300: cls = 0            // 5 min still
            case 300..<600: cls = 1          // 5 min walk  (streak 300)
            case 600..<900: cls = 0          // 5 min still
            default: cls = 1                 // 15 min walk (streak 900)
            }
            steps.append(StepSample(ts: start + i, counter: i, activityClass: cls))
        }
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: [], steps: steps,
                                                     start: start, end: start + dur,
                                                     restingHR: 60, maxHR: 190)
        XCTAssertNotNil(f)
        guard let f else { return }
        XCTAssertEqual(f.gaitStreakSec, 900, accuracy: 1)
        XCTAssertEqual(f.walkFraction, 1200.0 / 1800.0, accuracy: 0.001)
        XCTAssertEqual(f.stillFraction, 600.0 / 1800.0, accuracy: 0.001)
        // Counter delta is 1 per tick everywhere → cadence 1.0 across the gait ticks.
        XCTAssertEqual(f.gaitCadencePerSec ?? 0, 1.0, accuracy: 0.001)
    }

    func testExtractGaitCadence_ignoresCounterResetsAndLongGaps() {
        // A >2 s gap between gait ticks is a counter jump across unclassified time, not cadence;
        // a >8 wrap delta is a reset artifact. Both must be excluded from the mean.
        let start = 3_800_000, dur = 600
        let hr = hrBlock(start, dur, 100)
        var steps: [StepSample] = []
        var counter = 100
        for i in 0..<dur {
            let cls = (i < 300 || i >= 400) ? 1 : 0
            if i == 150 { counter += 40 }            // reset-ish jump mid-gait — must be dropped
            // Samples 350..<360 missing entirely: the gap makes the counter delta across it a
            // jump over unclassified time, not cadence — must be dropped by the ≤ 2 s guard.
            if i >= 350 && i < 360 { counter += 1; continue }
            steps.append(StepSample(ts: start + i, counter: counter, activityClass: cls))
            counter += 1
        }
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: [], steps: steps,
                                                     start: start, end: start + dur,
                                                     restingHR: 60, maxHR: 190)
        XCTAssertNotNil(f)
        guard let f else { return }
        // Deltas are 1/tick except the single +40 jump, which the >8 cap drops.
        XCTAssertEqual(f.gaitCadencePerSec ?? 0, 1.0, accuracy: 0.001)
    }

    func testExtractWithNoHRInWindow_returnsNil() {
        let start = 4_000_000
        XCTAssertNil(WorkoutTypeFeatureExtractor.extract(hr: [], gravity: [], steps: [],
                                                         start: start, end: start + 600))
    }

    func testExtractDegenerateWindow_returnsNil() {
        let hr = hrBlock(5_000_000, 10, 100)
        XCTAssertNil(WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: [], steps: [],
                                                         start: 5_000_000, end: 5_000_000))
        XCTAssertNil(WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: [], steps: [],
                                                         start: 5_000_100, end: 5_000_000))
    }

    func testExtractWithNoCaloriesInput_kcalPerMinIsNil() {
        let start = 6_000_000, dur = 600
        let hr = hrBlock(start, dur, 130)
        let f = WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: [], steps: [],
                                                     start: start, end: start + dur)
        XCTAssertNotNil(f)
        XCTAssertNil(f?.kcalPerMin)
    }
}
