import XCTest
@testable import StrandAnalytics
import WhoopStore

/// Load models run on TRIMP recovered from the stored Effort, over calendar windows.
final class TrainingLoadTrimpTests: XCTestCase {

    private func day(_ offset: Int, strain: Double?) -> DailyMetric {
        let base = VitalityEngine.epochDay("2026-03-01")!
        let date = Date(timeIntervalSince1970: TimeInterval(base + offset) * 86_400)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return DailyMetric(day: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!),
                           totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                           disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: strain,
                           exerciseCount: nil)
    }

    func testStrainToTrimpInvertsTheLogMap() {
        for trimp in [1.0, 37.5, 159.0, 868.0, 2024.0] {
            let strain = StrainScorer.trimpToStrain(trimp)
            // trimpToStrain rounds to 2 dp, so the round trip is exact to that precision only.
            XCTAssertEqual(StrainScorer.strainToTrimp(strain), trimp, accuracy: trimp * 0.003)
        }
        XCTAssertEqual(StrainScorer.strainToTrimp(0), 0)
        XCTAssertEqual(StrainScorer.strainToTrimp(-5), 0)
        XCTAssertEqual(StrainScorer.strainToTrimp(100), 7200, accuracy: 1e-6)
    }

    /// A week at twice the TRIMP of the three before it reads ACWR ≈ 1.6 (4-week chronic includes the
    /// hard week), and is flagged. On the Effort scale the same history read about 1.1.
    func testDoubledWeekReadsAsARealSpike() {
        let easy = StrainScorer.trimpToStrain(200), hard = StrainScorer.trimpToStrain(400)
        let days = (0..<28).map { i in day(i, strain: i < 21 ? easy : hard) }
        let (acute, chronic) = ReadinessEngine.calendarLoads(days.sorted { $0.day < $1.day }, through: days.last!.day)
        let ratio = (acute.reduce(0, +) / Double(acute.count)) / (chronic.reduce(0, +) / Double(chronic.count))
        XCTAssertEqual(ratio, 1.6, accuracy: 0.01)
        XCTAssertLessThan(hard / easy, 1.15)   // why the Effort scale hid it
    }

    /// Rows before a wear gap stay outside the 7- and 28-day windows.
    func testWearGapDoesNotStretchTheWindow() {
        var days = (0..<20).map { day($0, strain: 60) }          // old block
        days += (50..<55).map { day($0, strain: 40) }            // 5 recent days after a 30-day gap
        let (acute, chronic) = ReadinessEngine.calendarLoads(days, through: days.last!.day)
        XCTAssertEqual(acute.count, 5)
        XCTAssertEqual(chronic.count, 5)
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertNil(r.acwr)                                     // 5 < 14 observed days: no ratio
    }
}
