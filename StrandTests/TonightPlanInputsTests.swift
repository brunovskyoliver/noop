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

    /// A wake-day holding a main night and an afternoon nap: the night's start is the bedtime, never the
    /// nap's. (Nap credit counts decoded asleep minutes, so a stage-less fixture credits 0; that rule is
    /// the Sleep tab's own and is covered by its tests.)
    func testNapIsCreditedAndNotReadAsABedtime() {
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Int {
            Int(cal.date(byAdding: .minute, value: (dayOffset * 24 + h) * 60 + m, to: day)!.timeIntervalSince1970)
        }
        let night = CachedSleepSession(startTs: at(23, 15, dayOffset: -1), endTs: at(6, 45), efficiency: 0.9,
                                       restingHr: nil, avgHrv: nil, stagesJSON: nil)
        let nap = CachedSleepSession(startTs: at(14), endTs: at(14, 40), efficiency: 0.9,
                                     restingHr: nil, avgHrv: nil, stagesJSON: nil)
        let navDays = SleepModel.navDays(navSessions: [night, nap])
        let starts = AppModel.mainNightStarts(navDays: navDays, habitualMidsleepSec: nil)
        XCTAssertEqual(starts.map(\.startTs), [night.startTs])
        let inputs = AppModel.tonightPlanInputs(days: [], mainSleeps: starts,
                                                napSleepMinByDay: [Repository.localDayKey(day): 35],
                                                today: Repository.localDayKey(day), wakeMinute: 420,
                                                timeZone: .current)
        XCTAssertEqual(inputs.recentBedMinutes, [23 * 60 + 15])
        XCTAssertEqual(inputs.napMin, 35)
    }
}
