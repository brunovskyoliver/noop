import XCTest
import WhoopStore
@testable import Strand

final class ConfirmedWakeSelectionTests: XCTestCase {
    func testDisplayHonorsConfirmedWakeAndRetainsUnconfirmedBiphasicSleep() {
        let start = 1_700_000_000
        func first(edited: Bool, adjusted: Int?) -> CachedSleepSession {
            CachedSleepSession(startTs: start, endTs: start+7*3600, efficiency: 1,
                restingHr: nil, avgHrv: nil, stagesJSON: nil, userEdited: edited, startTsAdjusted: adjusted)
        }
        let tail = CachedSleepSession(startTs: start+7*3600+1800, endTs: start+9*3600,
            efficiency: 1, restingHr: nil, avgHrv: nil, stagesJSON: nil)
        XCTAssertEqual(SleepRules.mainNightGroup([first(edited: false, adjusted: nil), tail]).count, 2)
        XCTAssertEqual(SleepRules.mainNightGroup([first(edited: true, adjusted: nil), tail]).count, 2)
        let confirmed = SleepRules.mainNightGroup([first(edited: true, adjusted: start), tail])
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertEqual(confirmed.last?.endTs, start+7*3600)
    }
    func testActiveCaloriesCannotUseLegacyTotalEnergy() async {
        let day = DailyMetric(day: "2026-10-28", totalSleepMin: nil, efficiency: nil, deepMin: nil,
            remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
            recovery: nil, strain: nil, exerciseCount: nil, activeKcalEst: 1200)
        XCTAssertNil(Repository.dailyColumn(key: "active_kcal", day: day))
        XCTAssertEqual(Repository.dailyColumn(key: "energy_kcal", day: day), 1200)
        let candidates = await Repository.sourceCandidates(forKey: "active_kcal", preferredSource: "apple-health", actualWhoopSource: "strap")
        XCTAssertEqual(candidates.map { $0.source + "|" + $0.key },
            ["apple-health|active_kcal", "health-connect|active_kcal", "strap-noop|active_energy_kcal"])
    }

}
