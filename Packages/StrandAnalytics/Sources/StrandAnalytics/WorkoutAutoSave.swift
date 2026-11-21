import Foundation
import WhoopProtocol

// WorkoutAutoSave.swift — which detected sessions are saved as workouts without asking.
//
// Since #2220 detection only suggests, and a suggestion nobody opens is lost: on one wearer's month all
// eleven Apple Watch-logged lifts from 10-29 to 11-17 were detected as suggestions and none was saved.
// A session that clears the bar below is saved as a real workout, marked as the detector's own (its
// `suggestedClass` stays on the row), and announced; everything else stays a suggestion.
//
// The bar was set on WorkoutBench replays of that month (2026-10-19 → 11-18, 12 Watch strength sessions
// with strap HR) and is deliberately conservative: a missed save is still a suggestion the wearer can
// keep, while a false save is a workout they must delete.
//
// Kotlin twin: com.noop.analytics.WorkoutAutoSave (same constants, same verdicts; pinned by a Swift
// oracle literal in WorkoutAutoSaveTest). Pure: no clock, no I/O.

public enum WorkoutAutoSave {

    /// Shortest session saved without asking. The lifts measured ran 37–68 min; the detector's own
    /// floor (`WorkoutDetector.activityMinMin`, 10 min) admits a walk to the shop.
    public static let minDurationS = 20 * 60
    /// Share of the session's minutes holding an HR reading. Its avg/max HR, Effort and energy are only
    /// as good as the minutes behind them, and `WorkoutDetector` may now stitch across a grip dropout of
    /// up to 10 min, so a 40 min lift can legitimately read about 75%.
    public static let minHRCoveragePct = 70.0
    /// Mean %HRR the session must average: the detector's own activity floor
    /// (`WorkoutDetector.activityHRRFraction` as a percentage, written out so no float product sits at
    /// the boundary). Under it a session is everyday movement that only qualified as a piece of
    /// something larger.
    public static let minAvgHRRPct = 40.0
    /// Gravity-delta variance that marks lifting. Measured before this bar existed: lifts read
    /// 0.08–0.13 on 2026-09-23 (`docs/research/2026-09-23-strength-detection.md`, finding 4), and all
    /// eleven lifts the detector found in 2026-10/11 read 0.087–0.126. Walks read under it.
    public static let minLiftMotionVariance = 0.08
    /// Classifier confidence a run or ride needs. No labelled run or ride exists in the data the bar was
    /// set on, so this is the cautious end of the confidences seen (lifts 0.26–0.36).
    public static let minCardioConfidence = 0.40

    public enum Verdict: Equatable, Sendable {
        /// Save it. `token` is the class stored as `suggestedClass` ("strength"/"run"/"cycle").
        case save(token: String)
        /// Leave it as a suggestion.
        case suggest
    }

    /// The verdict for one session from `WorkoutDetector.detect`, given what the classifier made of it.
    ///
    /// - A lift: the classifier did not call it a walk (strength, or `other` when nothing cleared its
    ///   plausibility bar), its strength score is plausible (`WorkoutTypeClassifier.minPlausibleScore`),
    ///   and its motion variance is in the lifting band. Two of the eleven lifts came back `other`.
    /// - A run or ride: called so with `minCardioConfidence`, and cleared the detector's zone-2 bar
    ///   rather than only its activity tier.
    /// Both also need `minDurationS`, `minHRCoveragePct` and `minAvgHRRPct`. A detected walk is never
    /// saved here: `WorkoutAutoLog.walkSpans` logs walks from the step counter instead, and
    /// `WorkoutAutoLog.plan` adds the visit merge and the HR swing bar on top of this verdict.
    /// Kotlin twin: `WorkoutAutoSave.verdict`.
    public static func verdict(session s: ExerciseSession, features: WorkoutClassFeatures?,
                               prediction: WorkoutClassPrediction?) -> Verdict {
        guard s.end - s.start >= minDurationS,
              (s.hrCoveragePct ?? 0) >= minHRCoveragePct,
              (s.avgHRRPct ?? 0) >= minAvgHRRPct,
              let f = features, let p = prediction else { return .suggest }
        switch p.predictedClass {
        case .strength, .other:
            guard (p.scores[.strength] ?? 0) >= WorkoutTypeClassifier.minPlausibleScore,
                  f.motionVariance >= minLiftMotionVariance else { return .suggest }
            return .save(token: CoarseWorkoutClass.strength.rawValue)
        case .run, .cycle:
            guard p.confidence >= minCardioConfidence, !s.isActivityTier else { return .suggest }
            return .save(token: p.predictedClass.rawValue)
        case .walk, .ski:
            return .suggest
        }
    }

    /// The classifier's view of one session, over the same streams `detect` was given. Every caller that
    /// classifies a detected session goes through here, so the app and a replay cannot disagree.
    /// Kotlin twin: `WorkoutAutoSave.classify`.
    public static func classify(_ s: ExerciseSession, hr: [HRSample], gravity: [GravitySample],
                                steps: [StepSample], restingHR: Double?)
        -> (features: WorkoutClassFeatures?, prediction: WorkoutClassPrediction?) {
        guard let f = WorkoutTypeFeatureExtractor.extract(
            hr: hr, gravity: gravity, steps: steps, start: s.start, end: s.end,
            restingHR: restingHR, maxHR: s.hrmax, caloriesKcal: s.caloriesKcal) else { return (nil, nil) }
        return (f, WorkoutTypeClassifier.classify(f))
    }
}
