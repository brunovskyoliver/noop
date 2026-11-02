import Foundation

// HRVReadiness.swift — OPT-IN experimental "HRV readiness (Plews/Altini)" tier readout.
//
// The Kotlin twin is android/.../analytics/HRVReadiness.kt. Cross-platform parity is the contract: every
// constant, gate, and formula here must stay byte-identical to that source.
//
// This is a PURE, deterministic, DB-free engine and it does NOT change the default Charge/ring in any way
// — it is only surfaced (read-only) behind the PuffinExperiment `noopHrvReadiness` flag (off by default)
// and feeds NO downstream gate. It reimplements the endurance-science "smallest worthwhile change" (SWC)
// reading of nightly HRV popularised by Plews et al. and Marco Altini: work in the LOG domain (ln RMSSD is
// closer to normal and stabilises variance), compare a short 7-night rolling baseline against a longer
// personal normal band (±0.5 SD), and read the tier off where the short baseline sits relative to that
// band. A single bad night barely moves the 7-night baseline, so the reading is far more robust than a raw
// single-night z.
//
// INPUT: the SAME nightly RMSSD series RecoveryScorer / ReadinessEngine consume — DailyMetric.avgHrv[] in
// ms, oldest -> newest (nils allowed for missing nights). Physiologically implausible nights are dropped
// through the shared Baselines.hrvCfg bounds (5..250 ms) so one decode glitch can't skew it.
//
// OUTPUT (HRVReadinessResult): the tier (primed / normal / suppressed), the 7-night baseline and the
// personal normal band (all back in ms via exp), and an informational overreaching-watch flag. Returns nil
// (the honest ".calibrating" edge) below `minNights` valid nights: never a fabricated number. Mirrors the
// WatchRecovery nil+.calibrating honesty pattern.
//
// This is a rough / early experiment: it is NOT yet validated against varying real data (n=1). Outputs are
// APPROXIMATE wellness estimates, not medical advice.

/// Where tonight's 7-night HRV baseline sits vs the personal normal band. Mirrors Kotlin `ReadinessTier`.
public enum ReadinessTier: String, Equatable, Sendable {
    case primed
    case normal
    case suppressed
}

/// Result of an `HRVReadiness.evaluate` pass. All `*Ms` fields are back in milliseconds (exp of the log
/// domain the engine works in). Mirrors Kotlin `HRVReadinessResult`.
public struct HRVReadinessResult: Equatable, Sendable {
    /// Tier from the SWC comparison of the 7-night baseline against the personal normal band.
    public let tier: ReadinessTier
    /// 7-night rolling HRV baseline (ms) = exp(mean of ln RMSSD over the trailing rollWindow nights).
    public let baseline7Ms: Double
    /// Lower edge of the personal normal band (ms) = exp(longMean − 0.5·longSD).
    public let normalLowMs: Double
    /// Upper edge of the personal normal band (ms) = exp(longMean + 0.5·longSD).
    public let normalHighMs: Double
    /// Informational only (does NOT change the tier): a sustained falling CV trend while the 7-night
    /// baseline sits below the long mean — the classic parasympathetic-overreaching signature.
    public let overreachingWatch: Bool

    public init(tier: ReadinessTier, baseline7Ms: Double, normalLowMs: Double, normalHighMs: Double,
                overreachingWatch: Bool) {
        self.tier = tier
        self.baseline7Ms = baseline7Ms
        self.normalLowMs = normalLowMs
        self.normalHighMs = normalHighMs
        self.overreachingWatch = overreachingWatch
    }
}

/// OPT-IN experimental HRV-readiness (Plews/Altini SWC) engine. Mirrors Kotlin `HRVReadiness`.
public enum HRVReadiness {

    // MARK: - Constants (name them; mirror Kotlin exactly)

    /// Short rolling baseline window (nights) — the Plews/Altini 7-night HRV baseline.
    public static let rollWindow: Int = 7
    /// Long personal-normal window: calendar days before the short window, which it never contains.
    public static let longWindow: Int = 60
    /// Valid nights the short window needs (HRVStatus's rule: Plews reads a week from at least three).
    public static let minRollNights: Int = 3
    /// CV fall (percentage points per night) before the overreaching watch can fire. A slope merely below
    /// zero happens about half the time on noise. Unvalidated: set to keep a noise-only history quiet
    /// (see `HRVReadinessTests`), not fitted to any outcome.
    public static let minCVFallPerNight: Double = 0.05
    /// Smallest-worthwhile-change half-width factor: the normal band is longMean ± swcK·longSD.
    public static let swcK: Double = 0.5
    /// Minimum VALID nights in the long window before a reading is offered (else nil + the honest calibrating edge). Its OWN
    /// constant — deliberately NOT aliased to `WatchRecovery.minBaselineNights`: the SWC band needs a longer
    /// warm-up than the watch-recovery gate. It only mirrors WatchRecovery's nil+.calibrating HONESTY
    /// pattern, not its value.
    public static let minNights: Int = 14
    /// Trailing nights over which the CV trend (overreaching watch) is fit.
    public static let cvTrendWindow: Int = 28
    /// Floor on the long-window SD so a flat history yields a deterministic, tiny non-degenerate normal band
    /// instead of an ULP-fragile zero-width one (baseline7 and longMean are both the mean of the same
    /// constant here, but can differ by a float ULP, which a zero-width band would flip to primed/suppressed).
    public static let longSDFloor: Double = 1e-9

    // MARK: - Evaluate

    /// Compute the Plews/Altini HRV-readiness reading. Returns nil (calibrating) below `minNights` valid
    /// nights — never a fabricated value.
    ///
    /// - Parameters:
    ///   - nights: `(yyyy-MM-dd, RMSSD ms)` per night; a nil value is a missing night. Out-of-range nights
    ///     (outside `Baselines.hrvCfg` 5..250 ms) are dropped as decode artefacts.
    ///   - asOf: the day the reading describes. Nights after it are ignored.
    public static func evaluate(nights: [(day: String, value: Double?)], asOf: String) -> HRVReadinessResult? {
        let cfg = Baselines.hrvCfg
        guard let today = Baselines.isoEpochDay(asOf) else { return nil }
        // ln RMSSD by days before `asOf`. Log domain: Plews/Altini. Bounds keep ln well defined.
        var ellByAge: [Int: Double] = [:]
        for night in nights {
            guard let v = night.value, cfg.minVal <= v && v <= cfg.maxVal,
                  let d = Baselines.isoEpochDay(night.day), d <= today else { continue }
            ellByAge[today - d] = log(v)
        }
        func window(_ ages: Range<Int>) -> [Double] { ages.compactMap { ellByAge[$0] } }

        // 7 calendar days ending today, and the long normal before them, which never contains them.
        let shortEll = window(0..<rollWindow)
        let longEll = window(rollWindow..<(rollWindow + longWindow))
        // Honesty gate: too few valid nights in either window and we refuse to score. Never fabricate.
        guard shortEll.count >= minRollNights, longEll.count >= minNights else { return nil }

        let baseline7 = RecoveryForecaster.mean(shortEll)
        let longMean = RecoveryForecaster.mean(longEll)
        // Floored so a flat history gives a deterministic tiny band rather than an ULP-fragile zero-width one.
        let longSD = max(RecoveryForecaster.sampleSD(longEll), longSDFloor)

        // Smallest-worthwhile-change band (±0.5 SD in the log domain).
        let swcHalf = swcK * longSD
        let normalLow = longMean - swcHalf
        let normalHigh = longMean + swcHalf

        // Tier: above the band -> primed; inside (inclusive of the low edge) -> normal; below -> suppressed.
        let tier: ReadinessTier
        if baseline7 > normalHigh {
            tier = .primed
        } else if baseline7 >= normalLow {
            tier = .normal
        } else {
            tier = .suppressed
        }

        // Overreaching watch (INFORMATIONAL — never changes the tier): a sustained FALLING coefficient-of-
        // variation trend while the 7-night baseline sits below the long mean (parasympathetic overreach).
        // Build a rolling CV series (one point per night with a full trailing-7 window) over the last
        // cvTrendWindow nights, then OLS its slope.
        var cvSeries: [Double] = []
        for age in stride(from: cvTrendWindow - 1, through: 0, by: -1) {
            let w = window(age..<(age + rollWindow))
            guard w.count >= minRollNights else { continue }
            let m = RecoveryForecaster.mean(w)
            cvSeries.append(m != 0.0 ? 100.0 * RecoveryForecaster.sampleSD(w) / m : 0.0)
        }
        let cvSlope = ComparisonEngine.leastSquaresSlope(cvSeries)
        let overreachingWatch = cvSlope <= -minCVFallPerNight && baseline7 < longMean

        return HRVReadinessResult(tier: tier,
                                  baseline7Ms: exp(baseline7),
                                  normalLowMs: exp(normalLow),
                                  normalHighMs: exp(normalHigh),
                                  overreachingWatch: overreachingWatch)
    }
}
