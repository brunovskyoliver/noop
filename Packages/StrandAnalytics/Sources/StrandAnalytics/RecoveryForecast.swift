import Foundation

// RecoveryForecast.swift — an evening estimate of TOMORROW-morning Charge.
//
// Pure, deterministic, DB-free. Given the recent Charge (recovery) history, the
// recent Effort (strain) history, today's Effort, and how much sleep is planned /
// banked tonight against the personal sleep need, this projects what tomorrow's
// Charge is LIKELY to wake at — with an honest ± error band.
//
// This is an ESTIMATE, not a measurement. Morning Charge is computed from the NEXT night's
// HRV/RHR/respiration, none of which exist yet at the time this runs.
//
// Model: AR(1) on the trailing window, the simplest forecast that holds up.
//
//   forecast = mean + φ × (last − mean),  φ = lag-1 autocorrelation of the window, clamped to 0…1
//
// It replaced a mean plus strain, sleep and slope nudges with hand-set weights. Replayed over 49
// one-step forecasts from one wearer's stored days, that model had MAE 22.5 and RMSE 27.3, AR(1) 22.4
// and 27.5, persistence 25.1 and 32.2: the nudges earned nothing, and the slope term pushed against
// the trend it claimed to damp. One person's data, and an error this size means a rough guide at best.
//
// Band: the 80th percentile of this model's own absolute one-step errors over the history supplied,
// once there are `minResidualsForBand` of them; before that the window's SD, floored. `coverage` is how
// often such a band actually held, measured walk-forward, so the UI states it rather than implying it.
//
// Gating: returns nil unless there are at least minBaselineNights of recent Charge
// (so a cold-start user never sees a fabricated number). The UI shows the card only
// when this is non-nil.

// MARK: - Result

/// An evening projection of tomorrow-morning Charge (recovery, 0–100). APPROXIMATE.
public struct RecoveryForecast: Equatable, Sendable {
    /// The point estimate of tomorrow-morning Charge, 0–100 (rounded to a whole number).
    public let charge: Double
    /// Symmetric ± error band on `charge`, in Charge points (rounded to a whole number).
    public let band: Double
    /// Recent Charge baseline (mean) this projection is anchored to, 0–100.
    public let baseline: Double
    /// Nights of recent Charge history backing the baseline (drives confidence).
    public let nights: Int
    /// Per-score certainty tier (reuses the Charge/Effort/Rest confidence ladder).
    public let confidence: ScoreConfidence
    /// Share of past days a band built the same way contained the actual Charge, walk-forward;
    /// nil until `coverageDays` reaches `RecoveryForecaster.minCoverageDays`.
    public let coverage: Double?
    public let coverageDays: Int

    public init(charge: Double, band: Double, baseline: Double, nights: Int,
                confidence: ScoreConfidence, coverage: Double? = nil, coverageDays: Int = 0) {
        self.charge = charge
        self.band = band
        self.baseline = baseline
        self.nights = nights
        self.confidence = confidence
        self.coverage = coverage
        self.coverageDays = coverageDays
    }

    /// Low end of the band, clamped to [0, 100].
    public var low: Double { Swift.max(0, charge - band) }
    /// High end of the band, clamped to [0, 100].
    public var high: Double { Swift.min(100, charge + band) }
}

// MARK: - Engine

public enum RecoveryForecaster {

    // MARK: Tunables (documented, deterministic — NOT learned)

    /// Trailing Charge nights used for the mean and φ.
    public static let baselineWindow: Int = 14
    /// Minimum recent Charge nights before a forecast is offered (else nil — honest cold-start).
    public static let minBaselineNights: Int = 5

    /// Floor on the SD fallback band (points) — even a steady sleeper isn't perfectly predictable.
    public static let minBandPoints: Double = 8.0
    /// Extra ± points added while the baseline is below `trustedNights` (thin history).
    public static let thinBandPoints: Double = 6.0
    /// Recent Charge nights at/above which the band is no longer inflated for thinness.
    public static let trustedNights: Int = 10
    /// Past one-step errors needed before the band comes from them.
    public static let minResidualsForBand: Int = 14
    /// Walk-forward days needed before coverage is stated.
    public static let minCoverageDays: Int = 10

    // MARK: - Forecast

    /// Project tomorrow-morning Charge. APPROXIMATE; nil until there are at least
    /// `minBaselineNights` of recent Charge to anchor to.
    ///
    /// - Parameter recentCharge: daily Charge values, OLDEST→NEWEST (0–100). The trailing
    ///   `baselineWindow` set the forecast; anything older only feeds the band and its coverage.
    public static func forecast(recentCharge: [Double]) -> RecoveryForecast? {
        let chargeWindow = Array(recentCharge.suffix(baselineWindow))
        let nights = chargeWindow.count
        guard nights >= minBaselineNights else { return nil }

        let charge = clamp(point(chargeWindow), 0.0, 100.0).rounded()

        // One-step errors of this same model over the history, oldest first.
        var errors: [Double] = []
        if recentCharge.count > baselineWindow {
            for t in baselineWindow..<recentCharge.count {
                errors.append(abs(point(Array(recentCharge[(t - baselineWindow)..<t])) - recentCharge[t]))
            }
        }

        // Walk-forward: each past day judged by a band built only from the errors before it.
        var hits = 0, tested = 0
        if errors.count > minResidualsForBand {
            for t in minResidualsForBand..<errors.count {
                tested += 1
                if errors[t] <= percentile80(Array(errors[..<t])) { hits += 1 }
            }
        }

        var band: Double
        if errors.count >= minResidualsForBand {
            band = percentile80(errors)
        } else {
            band = Swift.max(sampleSD(chargeWindow), minBandPoints)
            if nights < trustedNights { band += thinBandPoints }
        }

        return RecoveryForecast(charge: charge, band: band.rounded(), baseline: mean(chargeWindow), nights: nights,
                                confidence: errors.count >= minResidualsForBand ? .solid : .building,
                                coverage: tested >= minCoverageDays ? Double(hits) / Double(tested) : nil,
                                coverageDays: tested)
    }

    /// The AR(1) point forecast from one window: mean + φ·(last − mean).
    static func point(_ window: [Double]) -> Double {
        let m = mean(window)
        return m + lagOneAutocorrelation(window) * (window[window.count - 1] - m)
    }

    /// Lag-1 autocorrelation clamped to 0…1; a negative value over two weeks is noise, not a rhythm.
    static func lagOneAutocorrelation(_ values: [Double]) -> Double {
        let m = mean(values)
        let denominator = values.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        guard denominator > 0, values.count >= 2 else { return 0 }
        var numerator = 0.0
        for i in 0..<(values.count - 1) { numerator += (values[i] - m) * (values[i + 1] - m) }
        return clamp(numerator / denominator, 0, 1)
    }

    static func percentile80(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[Swift.min(sorted.count - 1, Int(0.8 * Double(sorted.count)))]
    }

    // MARK: - Stats

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (ddof = 1); 0 for fewer than 2 values.
    static func sampleSD(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        let m = mean(values)
        var ss = 0.0
        for v in values { let d = v - m; ss += d * d }
        return (ss / Double(n - 1)).squareRoot()
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        // Inclusive-bound equality is already in range: return x itself so Swift
        // and Kotlin preserve the same IEEE signed-zero bit (#56).
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }
}
