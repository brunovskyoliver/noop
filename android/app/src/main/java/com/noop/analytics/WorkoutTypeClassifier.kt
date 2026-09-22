package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import com.noop.data.StepSample
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/*
 * WorkoutTypeClassifier.kt — COARSE workout-type classifier over ALREADY-CAPTURED signals.
 *
 * Faithful Kotlin twin of StrandAnalytics/WorkoutTypeClassifier.swift (#414) — same constants, same
 * ramp/plateau memberships, same per-class weights, byte-identical scores for the same feature vector.
 *
 * Given a detected workout window (from [WorkoutDetector] / [AutoWorkoutDetector]), this predicts a
 * BROAD activity class — walk / run / strength / cycle / ski / other — plus a confidence, from four
 * signal families that are already decoded and stored, no raw IMU:
 *   1. HR profile over the window (mean/peak/%HRR, HR variability shape) — [HrSample].
 *   2. Activity-class tick composition — [StepSample.activityClass] (0 still / 1 walk / 2 run,
 *      community finding #316) — the on-device per-tick gait classifier, rolled up to a window.
 *   3. Gravity-derived posture/motion variance — the SAME per-record L2 gravity-delta intensity
 *      [WorkoutDetector.activitySeries] already computes for detection, re-used here as a shape
 *      signal rather than a threshold gate.
 *   4. Duration and calories.
 *
 * BROAD ONLY. This deliberately does NOT attempt fine-grained sport discrimination (e.g. basketball
 * vs tennis) — that needs raw high-rate IMU (type-43, ~100 Hz) this app does not capture. `gravity`/
 * `steps` here are the DECODED, already-stored ~1 Hz streams; nothing in this file reads raw motion
 * buffers.
 *
 * NOT a spectral/autocorrelation estimate. The gravity stream this classifier reads is ~1 Hz, well
 * below the Nyquist rate a real gait/pedal cadence would need (~1.5–3 Hz for walk/run strides). Per
 * the CLAUDE.md derived-signal rule (and the withdrawn PPG→HR estimate, #194), autocorrelation or
 * spectral analysis on a fixed low sample rate can manufacture a peak at the RECORD period that looks
 * physiological but isn't — so this file never does that. `motionCV` is a coefficient-of-variation
 * burstiness/regularity statistic, NOT a frequency estimate. Treat it as "how steady vs. bursty is
 * the motion", nothing more.
 *
 * SHIP STATUS: first-pass HEURISTIC (documented, clamped ramp thresholds below), validated so far
 * ONLY against synthetic fixtures that each recover a distinct injected pattern (see
 * WorkoutTypeClassifierTest). This is advisory instrumentation — a caller may use it to LABEL or
 * SUGGEST a class on a detected workout, but it must never override a user's own sport selection and
 * must never gate a downstream score. Real-world accuracy against labeled workouts (e.g. Oura-import
 * `workout.sport` ground truth) is an explicit follow-up, not done here. The `scores` field on
 * [WorkoutClassPrediction] reports every candidate class's raw match score precisely so a later pass
 * can compute accuracy / top-k / confusion against real labels without re-deriving anything.
 *
 * Pure, database-free, no I/O — classifies from a feature vector. [WorkoutTypeFeatureExtractor]
 * builds that vector from the raw decoded streams; a future ML model (or one fed real IMU-derived
 * features) can implement [WorkoutTypeClassifying] and slot in behind the same call sites.
 */

/**
 * A BROAD workout activity class. Deliberately coarse — see file header for why finer-grained sport
 * discrimination (e.g. individual court/ball sports) is out of scope without raw IMU. [raw] preserves
 * the exact lowercase wire string the Swift twin's `rawValue` uses.
 */
enum class CoarseWorkoutClass(val raw: String) {
    WALK("walk"),
    RUN("run"),
    STRENGTH("strength"),
    CYCLE("cycle"),
    SKI("ski"),

    /**
     * No candidate class cleared the plausibility/margin bar — genuinely unclear, or a shape (e.g.
     * swim, row, court sport) this MVP doesn't model. Never a wrong specific guess dressed up.
     */
    OTHER("other"),
}

/**
 * The feature vector a classifier scores. Built once per detected workout window so real labeled
 * workouts (e.g. an Oura-import `workout` row) can be scored later WITHOUT re-deriving anything from
 * raw streams — construct this class directly from a labeled workout's own summary stats to validate,
 * or run [WorkoutTypeFeatureExtractor] over its stored streams. Mirrors Swift `WorkoutClassFeatures`.
 */
data class WorkoutClassFeatures(
    /** Window length (`end - start`), seconds. */
    val durationSec: Double,

    // --- HR profile ---
    val meanHR: Double,
    val peakHR: Int,
    /** Mean Karvonen %HRR over the window, 0..100, or null when resting/max HR couldn't be resolved. */
    val meanHRRPct: Double?,
    /**
     * Coefficient of variation (stdev/mean) of the window's HR samples. Low = steady sustained
     * effort (run/walk/cycle); high = saw-tooth (sets-then-rest strength, or intermittent ski runs).
     */
    val hrCV: Double,

    // --- Activity-class tick composition (StepSample.activityClass: 0 still / 1 walk / 2 run) ---
    /**
     * Fraction of ticks WITH a decoded activity class that read "still", "walk", "run" respectively
     * (sum to ~1 when [tickCoverage] > 0; all 0 when no tick in the window carried a class).
     */
    val stillFraction: Double,
    val walkFraction: Double,
    val runFraction: Double,
    /**
     * How much of the window is actually backed by a decoded activity-class tick, clamped [0, 1]
     * (classified ticks per second of window). Low/zero on a WHOOP 4.0 or any capture predating the
     * @63 decode — the classifier falls back to HR+motion-only scoring below
     * [WorkoutTypeClassifier.minTickCoverage].
     */
    val tickCoverage: Double,
    /**
     * Longest CONTIGUOUS run of gait-classified ticks (walk or run), in seconds. The feature that
     * separates a real walk/run — minutes of unbroken gait — from a strength session's incidental
     * between-sets walking: field data shows genuine walks sustain ≥ ~5 min of contiguous gait ticks
     * while lifting sessions never exceed ~2-3 min even though their walk-fraction is similar.
     * 0 when no ticks decode (pre-@63 capture / WHOOP 4.0) or no gait tick occurred.
     */
    val gaitStreakSec: Double = 0.0,
    /**
     * Mean step-counter delta per gait tick (ticks/second while the strap reports walk/run), or null
     * when no gait tick carried a usable counter delta. A real second-scale cadence proxy: genuine
     * walking reads ~1.5-2.0 (≈90-120 steps/min at stepTicksPerStep≈1), gym between-sets shuffling
     * reads lower (~1.3-1.5), running higher. Wrap-aware (u16) and capped so counter resets/gaps
     * can't inject outliers.
     */
    val gaitCadencePerSec: Double? = null,

    // --- Gravity-derived posture / motion shape ---
    /**
     * Variance of the per-record L2 gravity-delta intensity series over the window (the same series
     * [WorkoutDetector.activitySeries] computes) — a coarse posture/impact-variability proxy.
     */
    val motionVariance: Double,
    /**
     * Coefficient of variation of that same intensity series — burstiness/regularity, NOT a cadence
     * estimate (see file header). Low = smooth continuous motion (cycle); high = stop-start bursts
     * (strength sets, or ski runs broken up by lift rides).
     */
    val motionCV: Double,

    // --- Energy ---
    /**
     * Estimated kcal / minute over the window (`caloriesKcal / (durationSec/60)`), or null when no
     * calorie estimate was available.
     */
    val kcalPerMin: Double?,

    // --- High-rate IMU (2026-09-21; already-captured session files only) ---
    /**
     * Dominant gait-band cadence (Hz) from `ImuFeatureExtractor` over a captured 100 Hz session
     * overlapping this window; null on WHOOP 4.0, no capture, or no rhythmic peak (the trust gate —
     * the blend below only engages when a real peak was found). Multiply ×60 for steps/min.
     */
    val imuCadenceHz: Double? = null,
    /** Normalized strength (0..1) of that cadence peak. */
    val imuCadenceStrength: Double = 0.0,
    /** Mean gyroscope magnitude deg/s over the captured window (rotational intensity); null = no capture. */
    val imuGyroEnergyDps: Double? = null,
    /** RMS accel first-difference g/sample (impact/explosiveness); null = no capture. */
    val imuJerkRms: Double? = null,
)

/** A predicted coarse class + confidence for one workout window. Advisory only — see file header. */
data class WorkoutClassPrediction(
    val predictedClass: CoarseWorkoutClass,
    /**
     * 0..1. Reflects BOTH how cleanly the winner beat the runner-up (margin) and how complete the
     * inputs were (tick coverage, %HRR availability) — never higher than the evidence supports.
     */
    val confidence: Double,
    /**
     * Every scored candidate's raw match score (0..1), keyed by class. Always covers
     * WALK/RUN/STRENGTH/CYCLE/SKI — OTHER has no prototype score (see file header) and is never a
     * key here; it is only ever [predictedClass]. Kept so a later validation pass can check
     * top-k / confusion against real labels, not just the single winner.
     */
    val scores: Map<CoarseWorkoutClass, Double>,
)

/**
 * Anything that can turn a feature vector into a prediction. [WorkoutTypeClassifier] (the heuristic
 * below) is the only implementation today; a future ML model — trained on real labels, or fed richer
 * raw-IMU-derived features through a wider [WorkoutClassFeatures] — implements the SAME interface so
 * call sites built against it don't change. Mirrors Swift `WorkoutTypeClassifying`.
 */
interface WorkoutTypeClassifying {
    fun classify(features: WorkoutClassFeatures): WorkoutClassPrediction
}

/**
 * Thin instance adapter over [WorkoutTypeClassifier]'s heuristic, for callers that want the interface
 * seam (dependency injection, swapping in a future model) rather than calling the object directly.
 * Stateless; [WorkoutTypeClassifier.classify] is equally fine to call directly.
 */
class HeuristicWorkoutClassifier : WorkoutTypeClassifying {
    override fun classify(features: WorkoutClassFeatures): WorkoutClassPrediction =
        WorkoutTypeClassifier.classify(features)
}

/** The heuristic. Mirrors Swift `WorkoutTypeClassifier` — same constants, same scores. */
object WorkoutTypeClassifier {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants (first-pass heuristic — see file header; tune against real labels later)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Below this fraction of the window backed by a decoded activity-class tick, walk/run scoring
     * falls back to HR+motion-only (ticks are too sparse/absent — e.g. a WHOOP 4.0 capture — to trust).
     */
    const val minTickCoverage: Double = 0.15

    /** A candidate's top raw score must clear this to be reported as anything other than OTHER. */
    const val minPlausibleScore: Double = 0.40

    /**
     * The winner must beat the runner-up by at least this much (both 0..1 scores) or the call is
     * too close and reports OTHER instead of an arbitrary tie-break.
     */
    const val minMargin: Double = 0.05

    /**
     * 2026-09-21: weight the captured-IMU cadence/energy term gets when a real 100 Hz session overlaps
     * the window — the 1 Hz terms keep `1 − imuBlend`. Absent IMU (4.0 / no capture) → the blend never
     * engages and scores are byte-identical to before. 0.30 is deliberately modest: IMU refines a
     * 1 Hz vote, it does not override one.
     */
    const val imuBlend: Double = 0.30

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Score [features] against every candidate class and return the winner (or OTHER when nothing
     * clears [minPlausibleScore]/[minMargin]) plus a confidence that reflects both the margin and how
     * complete the inputs were.
     */
    fun classify(features: WorkoutClassFeatures): WorkoutClassPrediction {
        val scores = allScores(features)
        val ranked = scores.entries.sortedByDescending { it.value }
        val top = ranked.firstOrNull()
            ?: return WorkoutClassPrediction(CoarseWorkoutClass.OTHER, 0.0, scores)
        val second = if (ranked.size > 1) ranked[1].value else 0.0
        val margin = max(0.0, top.value - second)
        val marginFactor = 0.5 + 0.5 * min(1.0, margin)
        var confidence = top.value * marginFactor

        // Data-completeness dampener: never let a prediction read more confident than the inputs
        // backing it. Neither known → floor at 0.70×; both known → no penalty.
        val hrrKnown = features.meanHRRPct != null
        val ticksKnown = features.tickCoverage >= minTickCoverage
        var completeness = 0.70
        if (hrrKnown) completeness += 0.15
        if (ticksKnown) completeness += 0.15
        confidence = min(1.0, max(0.0, confidence * completeness))

        if (top.value < minPlausibleScore || margin < minMargin) {
            return WorkoutClassPrediction(CoarseWorkoutClass.OTHER, confidence, scores)
        }
        return WorkoutClassPrediction(top.key, confidence, scores)
    }

    /**
     * Every concrete class's raw [0,1] match score. Exposed (not just the winner) so validation
     * against real labels can check top-k, not only top-1.
     */
    fun allScores(f: WorkoutClassFeatures): Map<CoarseWorkoutClass, Double> = linkedMapOf(
        CoarseWorkoutClass.WALK to walkScore(f),
        CoarseWorkoutClass.RUN to runScore(f),
        CoarseWorkoutClass.STRENGTH to strengthScore(f),
        CoarseWorkoutClass.CYCLE to cycleScore(f),
        CoarseWorkoutClass.SKI to skiScore(f),
    )

    // ─────────────────────────────────────────────────────────────────────────
    // Ramp helpers (fuzzy-membership style, matches the plain documented-threshold style
    // elsewhere in this package rather than an opaque weighted model)
    // ─────────────────────────────────────────────────────────────────────────

    /** 0 at/below [lo], 1 at/above [hi], linear between. `hi <= lo` degenerates to a step at [hi]. */
    internal fun rampUp(x: Double, lo: Double, hi: Double): Double {
        if (hi <= lo) return if (x >= hi) 1.0 else 0.0
        return min(1.0, max(0.0, (x - lo) / (hi - lo)))
    }

    /** Mirror of [rampUp]: 1 at/below [lo], 0 at/above [hi]. */
    internal fun rampDown(x: Double, lo: Double, hi: Double): Double = 1.0 - rampUp(x, lo, hi)

    /**
     * Trapezoid membership: 0 below [a], ramps to 1 over [a,b], flat 1 over [b,c], ramps to 0 over
     * [c,d], 0 above [d]. Requires `a <= b <= c <= d`.
     */
    internal fun plateau(x: Double, a: Double, b: Double, c: Double, d: Double): Double =
        min(rampUp(x, a, b), rampDown(x, c, d))

    /**
     * How strongly the activity-class ticks should be trusted vs. falling back to HR+motion-only.
     * 0 with no/negligible tick coverage, ramping to 1 once coverage reaches [minTickCoverage].
     */
    internal fun tickReliability(f: WorkoutClassFeatures): Double =
        rampUp(f.tickCoverage, minTickCoverage * 0.3, minTickCoverage)

    // ─────────────────────────────────────────────────────────────────────────
    // Captured-IMU term (2026-09-21)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Blend [imu] into a class's 1 Hz score at [imuBlend] weight when a captured high-rate session
     * supplied the feature it needs; returns [base] unchanged otherwise. Gating on the FEATURE's
     * presence (not just "a file existed") keeps a capture with no rhythmic content or the wrong
     * axes from counting as evidence for or against any class.
     */
    internal fun imuBlended(base: Double, imu: Double?): Double =
        if (imu == null) base else base * (1 - imuBlend) + imu * imuBlend

    /**
     * "No walk/run gait" evidence for the non-foot classes (strength/cycle/ski). When ticks are too
     * sparse to trust, this returns a NEUTRAL 0.5 rather than penalizing — an absent signal must not
     * read as evidence against a class (a WHOOP 4.0 capture has no @63 activity class at all).
     */
    internal fun gaitAbsenceScore(f: WorkoutClassFeatures): Double {
        if (f.tickCoverage < minTickCoverage) return 0.5
        return rampUp(f.stillFraction, 0.40, 0.75)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Per-class scoring
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * The gait evidence composite shared by walk/run: tick fraction AND sustained gait streak,
     * with the counter cadence folded in when the window carried it. A session needs BOTH some
     * fraction of gait ticks AND a contiguous gait streak — gym sessions score high on fraction
     * (incidental between-sets walking reads as walk ticks) but never sustain a streak, which is
     * exactly what the streak term excludes. [cadenceTerm] is the per-class cadence membership.
     */
    internal fun gaitEvidence(f: WorkoutClassFeatures, fraction: Double, cadenceTerm: Double?): Double {
        val frac = rampUp(fraction, 0.15, 0.55)
        val streak = rampUp(f.gaitStreakSec, 120.0, 300.0)
        if (cadenceTerm != null) return 0.4 * frac + 0.4 * streak + 0.2 * cadenceTerm
        return 0.5 * frac + 0.5 * streak
    }

    /**
     * No sustained gait — the shared streak discriminator for the non-locomotion classes. Neutral
     * 0.5 when ticks are too sparse to trust (same absent-signal rule as [gaitAbsenceScore]).
     */
    internal fun noStreakScore(f: WorkoutClassFeatures): Double {
        if (f.tickCoverage < minTickCoverage) return 0.5
        return rampDown(f.gaitStreakSec, 90.0, 240.0)
    }

    /**
     * RUN: dominant run-classified ticks when available; else a smooth (low-`hrCV`), elevated-%HRR,
     * higher-impact (higher `motionVariance`) fallback signature.
     */
    internal fun runScore(f: WorkoutClassFeatures): Double {
        val tick = gaitEvidence(f, f.runFraction,
                                f.gaitCadencePerSec?.let { rampUp(it, 2.2, 2.8) })
        val hr = rampUp(f.meanHRRPct ?: 55.0, 45.0, 75.0)
        val motion = plateau(f.motionVariance, 0.05, 0.10, 0.35, 0.60)
        val smooth = rampDown(f.hrCV, 0.05, 0.12)
        val tickWeighted = 0.55 * tick + 0.25 * hr + 0.15 * motion + 0.05 * smooth
        val fallback = 0.45 * hr + 0.35 * motion + 0.20 * smooth
        val rel = tickReliability(f)
        val base = tickWeighted * rel + fallback * (1 - rel)
        // Captured-IMU cadence: running is a ~145–200 spm foot rate (2.4–3.3 Hz). Blend only on a real
        // gait-band peak; a capture with no rhythm leaves the 1 Hz verdict alone.
        return imuBlended(base, f.imuCadenceHz?.let { plateau(it, 2.2, 2.6, 3.2, 3.5) })
    }

    /**
     * WALK: dominant walk-classified ticks when available; else a LOW-moderate %HRR band (walking
     * rarely pushes %HRR high) with modest motion variance (rhythmic but low-impact gait).
     */
    internal fun walkScore(f: WorkoutClassFeatures): Double {
        val tick = gaitEvidence(f, f.walkFraction,
                                f.gaitCadencePerSec?.let { plateau(it, 1.1, 1.4, 2.3, 2.8) })
        val hr = plateau(f.meanHRRPct ?: 30.0, 5.0, 15.0, 35.0, 55.0)
        val motion = plateau(f.motionVariance, 0.005, 0.02, 0.10, 0.20)
        val tickWeighted = 0.55 * tick + 0.25 * hr + 0.20 * motion
        val fallback = 0.55 * hr + 0.45 * motion
        val rel = tickReliability(f)
        val base = tickWeighted * rel + fallback * (1 - rel)
        // Captured-IMU cadence: walking is a ~90–120 spm foot rate (1.5–2.0 Hz), distinct from both
        // running (faster) and pedalling (slower + smoother).
        return imuBlended(base, f.imuCadenceHz?.let { plateau(it, 1.2, 1.5, 2.0, 2.4) })
    }

    /**
     * STRENGTH: no SUSTAINED gait (between-sets walking produces walk ticks but never a minutes-long
     * streak), BURSTY HR (sets separated by rest reads as high `hrCV`, unlike a steady cardio
     * effort), HIGH motion variance — explosive reps and racked weight spike the wrist accelerometer
     * far more than rhythmic gait does (field data: lifting bouts read 0.25–0.36 variance where
     * walks read 0.05–0.15) — and typically a lower sustained kcal/min than continuous cardio.
     */
    internal fun strengthScore(f: WorkoutClassFeatures): Double {
        val noGait = gaitAbsenceScore(f)
        val noStreak = noStreakScore(f)
        val bursty = rampUp(f.hrCV, 0.06, 0.16)
        val hr = plateau(f.meanHRRPct ?: 45.0, 15.0, 30.0, 80.0, 100.0)
        val lowBurnRate = rampDown(f.kcalPerMin ?: 6.0, 6.0, 11.0)
        val variableMotion = plateau(f.motionVariance, 0.12, 0.22, 0.55, 0.90)
        // `variableMotion` carries the most weight deliberately: it's the one genuinely distinctive
        // signal here (explosive spiky movement). hr/lowBurnRate are generic enough (moderate HR,
        // moderate burn rate) that other steady-effort classes match them too, so a SMOOTH low-motion
        // window must not still score as strength just by having plausible HR levels.
        var base = 0.25 * variableMotion + 0.20 * noStreak + 0.20 * bursty + 0.15 * noGait +
            0.10 * hr + 0.10 * lowBurnRate
        // Bursty high-variance signatures are shared with skiing; the separator is duration — a
        // lifting session rarely runs past ~90 min while a ski day runs for hours. Damp (floor 0.5)
        // rather than disqualify so a genuine long session can still win when nothing else matches.
        base *= 0.5 + 0.5 * rampDown(f.durationSec / 60.0, 90.0, 180.0)
        // Captured IMU: a sets-and-rest bout shows NO sustained gait-band cadence (the extractor's
        // strength stays low across the whole window) with sporadic high jerk (racked weight, jumps).
        // Engage only when jerk was actually captured — the no-cadence half reads absence-of-rhythm,
        // which only a real capture can evidence.
        return imuBlended(base, f.imuJerkRms?.let { jerk ->
            0.7 * rampDown(f.imuCadenceStrength, 0.25, 0.55) + 0.3 * rampUp(jerk, 0.02, 0.08)
        })
    }

    /**
     * CYCLE: no walk/run gait, SMOOTH sustained elevated HR (low `hrCV`, unlike strength's sets), and
     * low motion variance — the torso/wrist stays comparatively still relative to on-foot gait.
     */
    internal fun cycleScore(f: WorkoutClassFeatures): Double {
        val noGait = gaitAbsenceScore(f)
        val noStreak = noStreakScore(f)
        val smooth = rampDown(f.hrCV, 0.04, 0.10)
        val hr = rampUp(f.meanHRRPct ?: 55.0, 35.0, 65.0)
        val stablePosture = rampDown(f.motionVariance, 0.02, 0.08)
        var base = 0.25 * noGait + 0.25 * smooth + 0.20 * hr + 0.15 * stablePosture + 0.15 * noStreak
        // Cycling is definitionally a SMOOTH, steady-cadence effort — a bursty (sets-then-rest) HR
        // can't be produced by pedalling, so `smooth` gates the whole score, not just one term.
        // Without this gate a gym session's generic noGait/hr/stablePosture matches outscore the
        // strength prototype that actually fits.
        base *= 0.35 + 0.65 * smooth
        // Captured-IMU cadence: pedalling is a ~60–105 rpm crank rate (1.0–1.75 Hz) — inside the gait
        // band but slower than a foot strike, which is exactly what separates it from walking.
        return imuBlended(base, f.imuCadenceHz?.let { plateau(it, 1.0, 1.3, 1.8, 2.1) })
    }

    /**
     * SKI: almost NO gait ticks at all (skiing is not gait — even lift-queue shuffling stays under
     * ~18% of ticks; gym sessions, which otherwise fake this signature, read 40%+), a still-fraction
     * band matching lift rides interleaved with runs (NOT the near-total stillness of a mostly-seated
     * window), HIGHER and more variable posture signal than cycling (turns/terrain, standing rather
     * than seated), and a wide, intermittent HR pattern (runs interspersed with lift-ride rest).
     */
    internal fun skiScore(f: WorkoutClassFeatures): Double {
        val lowGait: Double
        val stillBand: Double
        if (f.tickCoverage >= minTickCoverage) {
            lowGait = rampDown(f.walkFraction + f.runFraction, 0.05, 0.18)
            stillBand = plateau(f.stillFraction, 0.15, 0.30, 0.55, 0.75)
        } else {
            lowGait = 0.5; stillBand = 0.5
        }
        val variablePosture = plateau(f.motionVariance, 0.06, 0.14, 0.45, 0.70)
        val hr = plateau(f.meanHRRPct ?: 45.0, 20.0, 35.0, 85.0, 100.0)
        val intermittent = plateau(f.hrCV, 0.05, 0.09, 0.20, 0.32)
        // A ski day is measured in HOURS (lift queues included) where a lifting session rarely clears
        // ~75 min — duration is a real separator between two signatures that otherwise overlap.
        val longDuration = rampUp(f.durationSec / 60.0, 75.0, 150.0)
        var base = 0.30 * lowGait + 0.25 * variablePosture + 0.15 * stillBand + 0.10 * hr +
            0.10 * intermittent + 0.10 * longDuration
        // Skiing NEEDS terrain/posture variance — without it the neutral tick terms plus generic
        // HR/intermittent matches hand the win to a motionless window. Gate the whole score on it.
        base *= 0.30 + 0.70 * variablePosture
        // Captured IMU: sustained turning carves high gyro energy that no other class here produces.
        return imuBlended(base, f.imuGyroEnergyDps?.let { rampUp(it, 60.0, 180.0) })
    }
}

/**
 * Builds a [WorkoutClassFeatures] vector for a [start, end] window from the SAME decoded streams
 * [WorkoutDetector]/[AutoWorkoutDetector] already read ([HrSample], [GravitySample], [StepSample]) —
 * no new store, no new decode. Pure/deterministic; slices the caller's lists to the window itself so
 * callers can pass a whole day's streams or an already-sliced window interchangeably. Mirrors Swift
 * `WorkoutTypeFeatureExtractor`.
 */
object WorkoutTypeFeatureExtractor {

    /**
     * @param hr HR samples covering (at least) the window; required — null result if none fall inside.
     * @param gravity gravity samples covering the window (and a little before, ideally, so the first
     *   in-window delta isn't a false 0 — matches [WorkoutDetector.activitySeries] behavior either way).
     * @param steps step/activity-class samples covering the window; may be empty (pre-#316 firmware or
     *   a WHOOP 4.0) — `tickCoverage` reports 0 and the classifier falls back to HR+motion.
     * @param start / @param end window bounds, unix SECONDS (Long, inclusive), e.g. a detected session's.
     * @param restingHR day resting-HR baseline; null → derived from the window's own HR (10th
     *   percentile), same fallback [WorkoutDetector] uses.
     * @param maxHR HRmax; null → [StrainScorer.estimateHRmax] over the window's HR.
     * @param caloriesKcal the window's estimated calories, if already computed; null → `kcalPerMin`
     *   is null.
     * @param imu 2026-09-21 — features `ImuFeatureExtractor` produced over an ALREADY-CAPTURED 100 Hz
     *   session overlapping this window (looked up by the caller; `analyzeDay` passes its
     *   `imuActivityFeatures` closure's result). null → every `imu*` field is absent and scoring is
     *   byte-identical to the 1 Hz path.
     */
    fun extract(
        hr: List<HrSample>,
        gravity: List<GravitySample>,
        steps: List<StepSample>,
        start: Long,
        end: Long,
        restingHR: Double? = null,
        maxHR: Double? = null,
        caloriesKcal: Double? = null,
        imu: ImuActivityFeatures? = null,
    ): WorkoutClassFeatures? {
        if (end <= start) return null
        val hrWindow = hr.filter { it.ts in start..end }.sortedBy { it.ts }
        if (hrWindow.isEmpty()) return null

        val durationSec = (end - start).toDouble()
        val bpms = hrWindow.map { it.bpm.toDouble() }
        val meanHR = mean(bpms)
        val peakHR = hrWindow.maxOf { it.bpm }
        val hrCV = if (meanHR > 0) stddev(bpms) / meanHR else 0.0

        // %HRR: same fallback ladder as WorkoutDetector.detect — caller-supplied resting/max HR, else
        // derive from the window's own HR.
        val restHR = restingHR ?: WorkoutDetector.deriveRestingHR(hrWindow)
        val effMaxHR = maxHR ?: StrainScorer.estimateHRmax(bpms, null).first.takeIf { it > 0 }
        var meanHRRPct: Double? = null
        if (effMaxHR != null && effMaxHR > restHR) {
            val hrReserve = effMaxHR - restHR
            meanHRRPct = mean(bpms.map { StrainScorer.pctHRR(it, restHR, hrReserve) })
        }

        // Gravity-derived motion shape, via the SAME intensity series WorkoutDetector uses for detection.
        val intensitySeries = WorkoutDetector.activitySeries(gravity)
            .filter { it.ts in start..end }
            .map { it.intensity }
        val motionMean = mean(intensitySeries)
        val motionVariance = variance(intensitySeries)
        val motionCV = if (motionMean > 0) stddev(intensitySeries) / motionMean else 0.0

        // Activity-class tick composition. Iterated in stored order (the streams arrive sorted; a
        // defensive sort keeps a scrambled caller honest — streaks depend on ordering).
        val stepsWindow = steps.filter { it.ts in start..end }.sortedBy { it.ts }
        val validTicks = stepsWindow.mapNotNull { it.activityClass }
        val tickCoverage = min(1.0, validTicks.size.toDouble() / max(1.0, durationSec))
        var stillFraction = 0.0
        var walkFraction = 0.0
        var runFraction = 0.0
        if (validTicks.isNotEmpty()) {
            val n = validTicks.size.toDouble()
            stillFraction = validTicks.count { it == 0 } / n
            walkFraction = validTicks.count { it == 1 } / n
            runFraction = validTicks.count { it == 2 } / n
        }
        // Gait streak: longest contiguous run of walk|run ticks (each tick ≈ 1 s). Cadence: mean
        // wrap-aware u16 counter delta between consecutive gait ticks ≤ 2 s apart — deltas over a
        // longer gap are counter jumps across unclassified time, not cadence, and the ≤ 8 cap drops
        // reset/wrap artifacts (observed: a stray 50+ mean from one outlier delta).
        var gaitStreakSec = 0.0
        var streakCur = 0
        var cadenceSum = 0.0
        var cadenceN = 0
        var prevCounter: Int? = null
        var prevTs: Long? = null
        for (s in stepsWindow) {
            val gait = s.activityClass == 1 || s.activityClass == 2
            streakCur = if (gait) streakCur + 1 else 0
            gaitStreakSec = max(gaitStreakSec, streakCur.toDouble())
            val pc = prevCounter; val pt = prevTs
            if (gait && pc != null && pt != null && s.ts - pt <= 2) {
                val d = (s.counter - pc) and 0xFFFF
                if (d <= 8) { cadenceSum += d.toDouble(); cadenceN += 1 }
            }
            prevCounter = s.counter; prevTs = s.ts
        }
        val gaitCadencePerSec: Double? = if (cadenceN > 0) cadenceSum / cadenceN else null

        val kcalPerMin = caloriesKcal?.let { it / (durationSec / 60.0) }

        return WorkoutClassFeatures(
            durationSec = durationSec, meanHR = meanHR, peakHR = peakHR, meanHRRPct = meanHRRPct,
            hrCV = hrCV, stillFraction = stillFraction, walkFraction = walkFraction,
            runFraction = runFraction, tickCoverage = tickCoverage,
            gaitStreakSec = gaitStreakSec, gaitCadencePerSec = gaitCadencePerSec,
            motionVariance = motionVariance, motionCV = motionCV, kcalPerMin = kcalPerMin,
            imuCadenceHz = imu?.cadenceHz, imuCadenceStrength = imu?.cadenceStrength ?: 0.0,
            imuGyroEnergyDps = imu?.gyroEnergyDps, imuJerkRms = imu?.jerkRms,
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Small stats helpers (population variance/stdev; no external dependency)
    // ─────────────────────────────────────────────────────────────────────────

    internal fun mean(xs: List<Double>): Double =
        if (xs.isEmpty()) 0.0 else xs.sum() / xs.size.toDouble()

    internal fun variance(xs: List<Double>): Double {
        if (xs.size <= 1) return 0.0
        val m = mean(xs)
        return xs.sumOf { (it - m) * (it - m) } / xs.size.toDouble()
    }

    internal fun stddev(xs: List<Double>): Double = sqrt(variance(xs))
}
