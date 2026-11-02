import XCTest
@testable import StrandAnalytics
import WhoopStore

/// RD1 — the readiness HRV signal is z-scored in the LOG domain (lnRMSSD), not raw ms. RMSSD is
/// right-skewed, so a symmetric z on raw ms over-weights the long upper tail; lnRMSSD is closer to
/// normal (Plews/Altini; the app's own HRVReadiness works this way). Observable consequence: the
/// baseline the signal reports is the GEOMETRIC mean (a typical night), not an arithmetic mean that
/// a few big-recovery nights inflate. RHR stays linear (it is ~normal).
final class RD1LogDomainTests: XCTestCase {
    private func d(_ i: Int, hrv: Double?, rhr: Int?) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: nil, strain: 10, exerciseCount: nil,
                    spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
    }

    func testHrvBaselineIsGeometricNotArithmetic() {
        // 17 nights at 42 ms + 7 big-recovery nights at 85 ms: arithmetic mean ≈ 54.5, geometric ≈ 52.
        var days: [DailyMetric] = []
        for i in 1...17 { days.append(d(i, hrv: 42, rhr: i % 2 == 0 ? 53 : 51)) }
        for i in 18...24 { days.append(d(i, hrv: 85, rhr: i % 2 == 0 ? 53 : 51)) }
        for i in 25...31 { days.append(d(i, hrv: 50, rhr: 52)) }   // a typical week, ending today

        let hrv = ReadinessEngine.evaluate(days: days).signals.first { $0.key == "hrv" }
        // Log domain baselines against a GEOMETRIC center below the arithmetic mean a raw-ms z would
        // report. The window holds the nights before the 7-day reading.
        XCTAssertEqual(hrv?.evidence, "50 vs 52 ms")
        // 50 sits near the typical night → neutral, read against a representative (not tail-inflated) baseline.
        XCTAssertEqual(hrv?.flag, .neutral)
    }
}
