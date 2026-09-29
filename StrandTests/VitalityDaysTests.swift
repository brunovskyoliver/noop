import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// The Vitality / Body Age / Pace of Aging input reader (`Repository+Healthspan.swift`). Mirrors the
/// Android `VitalityWindow.days` / `vo2Points` contract.
final class VitalityDaysTests: XCTestCase {

    private func workout(_ start: Int, zones: String?, duration: Double? = 3_600) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 3_600, sport: "Running", source: "whoop",
                   durationS: duration, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                   distanceM: nil, zonesJSON: zones, notes: nil, steps: nil,
                   suggestedClass: nil, suggestedClassConfidence: nil)
    }

    private func daily(_ day: String, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: rhr, avgHrv: 42, recovery: nil, strain: nil,
                    exerciseCount: nil, steps: 8_100)
    }

    /// A measured VO₂max anywhere in the window replaces the estimate for the whole window.
    func testMeasuredVO2WinsForWholeWindow() {
        let measured = [(day: "2026-09-01", value: 47.0)]
        let estimated = [(day: "2026-08-30", value: 41.0), (day: "2026-09-06", value: 42.0)]
        XCTAssertEqual(Repository.vitalityVO2Points(measured: measured, estimated: estimated,
                                                    from: "2026-03-29", to: "2026-09-24"),
                       ["2026-09-01": 47.0])
        // Outside the window the measurement does not count, so the estimates are used.
        XCTAssertEqual(Repository.vitalityVO2Points(measured: [(day: "2025-01-01", value: 47.0)],
                                                    estimated: estimated,
                                                    from: "2026-03-29", to: "2026-09-24"),
                       ["2026-08-30": 41.0, "2026-09-06": 42.0])
    }

    /// Workouts add zone minutes to the day they started on; rows without zones add nothing; a day with
    /// only a workout still appears.
    func testZoneMinutesAttributedToStartDay() {
        let dayOf: (Int) -> String = { $0 < 2_000 ? "2026-09-01" : "2026-09-02" }
        let days = Repository.vitalityDays(
            dailies: [daily("2026-09-01", rhr: 58)],
            workouts: [workout(1_000, zones: #"{"z2":50,"z4":50}"#),
                       workout(1_500, zones: #"{"zone3":100}"#, duration: 1_800),
                       workout(3_000, zones: nil),
                       workout(4_000, zones: #"{"z5":100}"#)],
            vo2ByDay: ["2026-09-03": 44],
            dayOf: dayOf)
        XCTAssertEqual(days.map(\.day), ["2026-09-01", "2026-09-02", "2026-09-03"])
        XCTAssertEqual(days[0].restingHR, 58)
        XCTAssertEqual(days[0].sleepHours, 7.5)
        XCTAssertEqual(days[0].zone13Min, 60, accuracy: 1e-9)   // 30 + 30
        XCTAssertEqual(days[0].zone45Min, 30, accuracy: 1e-9)
        XCTAssertEqual(days[1].zone45Min, 60, accuracy: 1e-9)
        XCTAssertNil(days[1].restingHR)
        XCTAssertEqual(days[2].vo2max, 44)
    }

    /// Strength time: strength-sport workouts count; a Lift Log session counts only when no workout row
    /// shares its start and sport (the paired row already counted it).
    func testStrengthMinutesWithoutDoubleCounting() {
        func row(_ start: Int, _ sport: String) -> WorkoutRow {
            WorkoutRow(startTs: start, endTs: start + 1_800, sport: sport, source: "whoop",
                       durationS: 1_800, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: nil, zonesJSON: nil, notes: nil, steps: nil,
                       suggestedClass: nil, suggestedClassConfidence: nil)
        }
        let days = Repository.vitalityDays(
            dailies: [], workouts: [row(1_000, "Strength Training"), row(1_500, "Running")],
            lifts: [.init(startTs: 1_000, endTs: 3_400, sport: "Strength Training"),   // paired → skipped
                    .init(startTs: 1_200, endTs: 2_400, sport: "Strength Training")],  // unpaired → 20 min
            vo2ByDay: [:], dayOf: { _ in "2026-09-01" })
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].strengthMin, 30 + 20, accuracy: 1e-9)
    }

    func testWindowStart() {
        XCTAssertEqual(Repository.vitalityWindowStart(endingOn: "2026-09-24"), "2026-03-29")
    }
}
