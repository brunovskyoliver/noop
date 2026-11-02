import Foundation

// CorrelationEngine.swift — relationships between two daily series.
//
// Pure, deterministic, DB-free. Computes the Pearson product-moment correlation r,
// a simple ordinary-least-squares regression line (slope/intercept of y on x), and
// a two-sided p-value for r.
//
//   r = Σ(x−x̄)(y−ȳ) / sqrt( Σ(x−x̄)² · Σ(y−ȳ)² )         (Pearson)
//   slope     = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²                     (OLS, y on x)
//   intercept = ȳ − slope·x̄
//
// The p-value uses the standard t-statistic for a correlation,
//   t = r · sqrt( (n−2) / (1−r²) ),
// converted to a two-sided tail probability with the Student-t distribution on n−2
// degrees of freedom, through the regularized incomplete beta function. A normal tail
// understates p badly at these sample sizes (r=.8, n=5: 0.021 against a true 0.104).
// The test assumes independent days, which daily health series are not, so the p-value
// is still a best case for autocorrelated data.
//
// `alignByDay` inner-joins two "yyyy-MM-dd"-keyed series on the day key, returning
// (x, y) pairs sorted by day. `lagged` shifts y forward by `lagDays` relative to x
// (x on day D paired with y on day D+lag) and correlates the result, which lets a
// caller probe directional / delayed effects (e.g. today's strain vs tomorrow's
// recovery).

/// The result of correlating two aligned series.
public struct Correlation: Equatable, Sendable {
    /// Pearson correlation coefficient in [-1, 1].
    public let r: Double
    /// Number of paired observations used.
    public let n: Int
    /// Two-sided Student-t p-value for H0: r = 0, assuming independent days.
    public let pApprox: Double
    /// OLS slope of y on x.
    public let slope: Double
    /// OLS intercept of y on x.
    public let intercept: Double

    public init(r: Double, n: Int, pApprox: Double, slope: Double, intercept: Double) {
        self.r = r
        self.n = n
        self.pApprox = pApprox
        self.slope = slope
        self.intercept = intercept
    }
}

public enum CorrelationEngine {

    // MARK: - Pearson + regression

    /// Pearson r plus an OLS regression line and Student-t p-value for the pairs.
    /// Returns nil when fewer than 3 pairs, or when either variable has zero
    /// variance (r undefined).
    public static func pearson(_ xy: [(Double, Double)]) -> Correlation? {
        let n = xy.count
        guard n >= 3 else { return nil }
        let nD = Double(n)

        var sumX = 0.0, sumY = 0.0
        for p in xy { sumX += p.0; sumY += p.1 }
        let meanX = sumX / nD
        let meanY = sumY / nD

        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in xy {
            let dx = p.0 - meanX
            let dy = p.1 - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        // Zero variance in either variable → correlation undefined.
        guard sxx > 0 && syy > 0 else { return nil }

        var r = sxy / (sxx.squareRoot() * syy.squareRoot())
        // Clamp tiny floating-point overshoot so |r| ≤ 1 exactly.
        if r > 1.0 { r = 1.0 }
        if r < -1.0 { r = -1.0 }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let p = pValue(r: r, n: n)

        return Correlation(r: r, n: n, pApprox: p, slope: slope, intercept: intercept)
    }

    // MARK: - Day alignment

    /// Inner-join two "yyyy-MM-dd"-keyed series on the day key, returning the (x, y)
    /// value pairs for days present in BOTH, sorted ascending by day. Later entries
    /// for a duplicated day in either series win (last-write).
    public static func alignByDay(_ a: [(day: String, value: Double)],
                                  _ b: [(day: String, value: Double)]) -> [(Double, Double)] {
        var mapA: [String: Double] = [:]
        for row in a { mapA[row.day] = row.value }
        var mapB: [String: Double] = [:]
        for row in b { mapB[row.day] = row.value }

        let commonDays = mapA.keys.filter { mapB[$0] != nil }.sorted()
        return commonDays.map { (mapA[$0]!, mapB[$0]!) }
    }

    // MARK: - Lagged correlation

    /// Correlate x[day] against y[day + lagDays]. A positive lag asks "does x today
    /// predict y `lagDays` later?"; a negative lag looks backward. Days are matched
    /// on the calendar by offsetting x's day key by `lagDays` and joining to y.
    ///
    /// Returns nil when fewer than 3 lag-matched pairs survive or when `pearson`
    /// rejects them (zero variance).
    public static func lagged(x: [(day: String, value: Double)],
                              y: [(day: String, value: Double)],
                              lagDays: Int) -> Correlation? {
        var mapY: [String: Double] = [:]
        for row in y { mapY[row.day] = row.value }

        var pairs: [(Double, Double)] = []
        // Sort x by day for deterministic ordering of the pair list.
        let sortedX = x.sorted { $0.day < $1.day }
        for row in sortedX {
            guard let shifted = shiftDay(row.day, by: lagDays) else { continue }
            if let yv = mapY[shifted] {
                pairs.append((row.value, yv))
            }
        }
        return pearson(pairs)
    }

    // MARK: - p-value

    /// Two-sided p-value for H0: r = 0 via t = r·sqrt((n−2)/(1−r²)) on n−2 degrees of
    /// freedom. n ≤ 2 → 1.0 (no evidence); |r| = 1 → 0.0.
    static func pValue(r: Double, n: Int) -> Double {
        guard n > 2 else { return 1.0 }
        let oneMinusR2 = 1.0 - r * r
        if oneMinusR2 <= 0 { return 0.0 }  // |r| == 1
        let t = r * (Double(n - 2) / oneMinusR2).squareRoot()
        return studentTTwoSidedP(t: t, df: Double(n - 2))
    }

    /// Two-sided Student-t tail P(|T| ≥ |t|) = I_x(df/2, 1/2) with x = df/(df+t²).
    /// df ≤ 0 carries no evidence and returns 1.
    public static func studentTTwoSidedP(t: Double, df: Double) -> Double {
        guard df > 0, !t.isNaN else { return 1.0 }
        guard t.isFinite else { return 0.0 }
        return regularizedIncompleteBeta(x: df / (df + t * t), a: df / 2, b: 0.5)
    }

    /// The t value with `twoSidedP` in both tails, by bisection on the tail above.
    static func studentTQuantile(twoSidedP p: Double, df: Double) -> Double {
        var lo = 0.0, hi = 1e6
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if studentTTwoSidedP(t: mid, df: df) > p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// I_x(a, b) by the Lentz continued fraction (Numerical Recipes `betacf`).
    static func regularizedIncompleteBeta(x: Double, a: Double, b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // The fraction converges fast below this point; above it, use the symmetry.
        return x > (a + 1) / (a + b + 2) ? 1 - betaFraction(x: 1 - x, a: b, b: a) : betaFraction(x: x, a: a, b: b)
    }

    private static func betaFraction(x: Double, a: Double, b: Double) -> Double {
        let front = exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x))
        let tiny = 1e-300
        var c = 1.0
        var d = 1 - (a + b) * x / (a + 1)
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let m1 = Double(m), m2 = 2 * m1
            let even = m1 * (b - m1) * x / ((a + m2 - 1) * (a + m2))
            d = 1 + even * d; if abs(d) < tiny { d = tiny }
            c = 1 + even / c; if abs(c) < tiny { c = tiny }
            d = 1 / d; h *= d * c
            let odd = -(a + m1) * (a + b + m1) * x / ((a + m2) * (a + m2 + 1))
            d = 1 + odd * d; if abs(d) < tiny { d = tiny }
            c = 1 + odd / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let step = d * c
            h *= step
            if abs(step - 1) < 1e-14 { break }
        }
        return front * h / a
    }

    /// Benjamini-Hochberg adjusted p-values, in input order. Reject at FDR q by `adjusted < q`.
    public static func benjaminiHochberg(_ p: [Double]) -> [Double] {
        let order = p.indices.sorted { p[$0] > p[$1] }
        var out = p
        var running = 1.0
        for (i, index) in order.enumerated() {
            let rank = p.count - i
            running = Swift.min(running, p[index] * Double(p.count) / Double(rank))
            out[index] = running
        }
        return out
    }

    /// Correlation after removing each series' own straight-line trend over the pairs' order.
    /// Two series that both drift over a season correlate through the drift alone. `pairs` must
    /// be in day order, which `alignByDay` guarantees; a pair missing days is treated as evenly
    /// spaced. The p-value keeps n−2 degrees of freedom, so it is a slightly generous one.
    public static func detrendedPearson(_ pairs: [(Double, Double)]) -> Correlation? {
        guard pairs.count >= 3 else { return nil }
        func residuals(_ v: [Double]) -> [Double]? {
            let line = pearson(v.enumerated().map { (Double($0.offset), $0.element) })
            guard let line else { return nil }
            return v.enumerated().map { $0.element - (line.intercept + line.slope * Double($0.offset)) }
        }
        guard let x = residuals(pairs.map(\.0)), let y = residuals(pairs.map(\.1)) else { return nil }
        return pearson(Array(zip(x, y)))
    }

    /// Metric keys that feed the Charge score, so a correlation with `recovery` is true by construction.
    public static let chargeInputKeys: Set<String> = ["hrv", "rhr", "sleep_performance"]

    /// True when one key is Charge and the other one of its inputs.
    public static func isCoupled(_ a: String, _ b: String) -> Bool {
        (a == "recovery" && chargeInputKeys.contains(b)) || (b == "recovery" && chargeInputKeys.contains(a))
    }

    /// Detrends each candidate, corrects its p across every candidate tested (Benjamini-Hochberg), and
    /// returns the correlation only where it clears `minN`, `minAbsR` and an adjusted p below 0.05.
    /// `pApprox` in the result is the adjusted value. The output lines up with the input.
    public static func screened(_ candidates: [[(Double, Double)]], minN: Int, minAbsR: Double) -> [Correlation?] {
        let raw = candidates.map { $0.count >= minN ? detrendedPearson($0) : nil }
        let tested = raw.indices.filter { raw[$0] != nil }
        let adjusted = benjaminiHochberg(tested.map { raw[$0]!.pApprox })
        var out = [Correlation?](repeating: nil, count: candidates.count)
        for (i, p) in zip(tested, adjusted) where p < 0.05 && abs(raw[i]!.r) >= minAbsR {
            let c = raw[i]!
            out[i] = Correlation(r: c.r, n: c.n, pApprox: p, slope: c.slope, intercept: c.intercept)
        }
        return out
    }

    // MARK: - Day arithmetic

    /// Shift a "yyyy-MM-dd" day string by `delta` days (can be negative), returning
    /// a normalised "yyyy-MM-dd" string. Uses a fixed UTC calendar so it is
    /// deterministic and timezone-free. Returns nil if the input can't be parsed.
    static func shiftDay(_ day: String, by delta: Int) -> String? {
        if delta == 0 { return day }
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1 else { return nil }

        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let base = cal.date(from: comps),
              let shifted = cal.date(byAdding: .day, value: delta, to: base) else { return nil }
        let out = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let oy = out.year, let om = out.month, let od = out.day else { return nil }
        return String(format: "%04d-%02d-%02d", oy, om, od)
    }
}
