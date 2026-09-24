import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// `AppModel.tonightPlanInputs`: the planner reads the Sleep tab's own need and debt, the last 14
/// nights' efficiency, and local bedtimes.
final class TonightPlanInputsTests: XCTestCase {

    private func day(_ d: Int, sleepMin: Double, eff: Double) -> DailyMetric {
        DailyMetric(day: String(format: "2026-09-%02d", d), totalSleepMin: sleepMin, efficiency: eff,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }

    func testInputsFollowTheSleepTabLedger() {
        let days = (1...20).map { day($0, sleepMin: 420, eff: 0.9) }        // 7 h a night
        let utc = TimeZone(identifier: "UTC")!
        // Bed at 23:30 UTC on each of 3 nights.
        let base = 1_790_000_000 - (1_790_000_000 % 86_400)
        let sleeps = (0..<3).map { i in
            CachedSleepSession(startTs: base + i * 86_400 + 23 * 3600 + 1800, endTs: base + (i + 1) * 86_400 + 7 * 3600,
                               efficiency: 0.9, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        }
        let inputs = AppModel.tonightPlanInputs(days: days, mainSleeps: sleeps, napSleepMinByDay: ["2026-09-20": 30],
                                                today: "2026-09-20", wakeMinute: 420, timeZone: utc)
        let ledger = SleepModel.debtLedger(days: days, napSleepMinByDay: ["2026-09-20": 30])
        XCTAssertEqual(inputs.baseNeedHours, ledger.needMin / 60)
        XCTAssertEqual(inputs.debtMin, ledger.isDebt ? ledger.magnitudeMin : 0)
        XCTAssertEqual(inputs.napMin, 30)
        XCTAssertEqual(inputs.efficiencies.count, 14)
        XCTAssertEqual(inputs.recentBedMinutes, [23 * 60 + 30, 23 * 60 + 30, 23 * 60 + 30])
        XCTAssertEqual(inputs.wakeMinute, 420)
    }
}
