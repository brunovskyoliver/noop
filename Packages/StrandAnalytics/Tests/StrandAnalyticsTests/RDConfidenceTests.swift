import XCTest
@testable import StrandAnalytics
import WhoopStore

/// RD-confidence — the readiness read now carries a `ScoreConfidence` from its baseline density, so
/// the card can say calibrating / building / solid instead of a confident number off a 7-night
/// baseline (Charge already does this; readiness didn't).
final class RDConfidenceTests: XCTestCase {

    func testReadinessConfidenceTiers() {
        XCTAssertEqual(ScoreConfidence.readiness(hasRead: false, baselineNights: 40, fullWindow: 30), .calibrating)
        XCTAssertEqual(ScoreConfidence.readiness(hasRead: true, baselineNights: 12, fullWindow: 30), .building)
        XCTAssertEqual(ScoreConfidence.readiness(hasRead: true, baselineNights: 30, fullWindow: 30), .solid)
    }

    private func d(_ i: Int, hrv: Double?, rhr: Int?) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: nil, strain: 10, exerciseCount: nil,
                    spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
    }

    func testEmptyHistoryReadsCalibrating() {
        XCTAssertEqual(ReadinessEngine.evaluate(days: []).confidence, .calibrating)
    }

    func testThinBaselineReadsBuilding() {
        // 10 baseline nights + today: a read exists but baseline < the 30-night window → building.
        var days: [DailyMetric] = []
        for i in 1...10 { days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: 52)) }
        days.append(d(11, hrv: 60, rhr: 52))
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertNotEqual(r.level, .insufficient)
        XCTAssertEqual(r.confidence, .building)
    }

    func testFullBaselineReadsSolid() {
        // The HRV baseline window sits before the 7-day reading: 30 nights + that week.
        let days = (0..<37).map { i in
            DailyMetric(day: Baselines.cutoffKey(todayKey: "2024-03-31", carryDays: 36 - i), totalSleepMin: nil,
                        efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
                        avgHrv: i % 2 == 0 ? 62 : 58, recovery: nil, strain: 10, exerciseCount: nil,
                        spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
        }
        XCTAssertEqual(ReadinessEngine.evaluate(days: days).confidence, .solid)
    }
}
