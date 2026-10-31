import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class AnalyticsAccuracyTests: XCTestCase {
    private let profile = UserProfile(weightKg: 66, heightCm: 170, age: 19, sex: "male")

    func testRestingEnergyNeverBecomesActiveEnergy() {
        let start = AnalyticsEngine.dayStartUtcSeconds("2026-10-28")
        let hr = (0..<3600).map { HRSample(ts: start + $0, bpm: 50) }
        let result = AnalyticsEngine.analyzeDay(day: "2026-10-28", hr: hr, profile: profile)
        XCTAssertEqual(result.activeEnergyKcal, 0)
        XCTAssertGreaterThan(result.daily.activeKcalEst ?? 0, 0)
        XCTAssertEqual(result.daily.activeKcalEst ?? 0,
            Calories.estimateDayCalories(hr, profile: profile, hrmax: 194.7, restingHR: nil), accuracy: 1e-8)
    }

    func testMissingEnergyRemainsUnknown() {
        let result = AnalyticsEngine.analyzeDay(day: "2026-10-28", profile: profile)
        XCTAssertNil(result.activeEnergyKcal)
        XCTAssertNil(result.daily.activeKcalEst)
    }

    func testFallBackDayIncludesBothRepeatedHoursAndExcludesItsNeighbours() throws {
        let clock = LocalDayWindows(timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Copenhagen")))
        let window = try XCTUnwrap(clock.window(of: .init(year: 2026, month: 10, day: 25)))
        let a = Int(window.start.timeIntervalSince1970), b = Int(window.nextStart.timeIntervalSince1970)
        XCTAssertEqual(b-a, 90_000)
        let hr = [HRSample(ts: a-1, bpm: 170)] + (a..<b).map { HRSample(ts: $0, bpm: 50) }
            + [HRSample(ts: b, bpm: 170)]
        let result = AnalyticsEngine.analyzeDay(day: "2026-10-25", dayHr: hr, profile: profile,
            tzOffsetSeconds: 3600, dayBounds: a..<b)
        XCTAssertEqual(result.activeEnergyKcal, 0)
        let expected = Calories.estimateDayEnergy(Array(hr.dropFirst().dropLast()), profile: profile,
            hrmax: 194.7, restingHR: nil, maxSpanSeconds: 90_000)
        XCTAssertEqual(expected.observedSeconds, 90_000)
        XCTAssertEqual(result.daily.activeKcalEst ?? 0, expected.totalKcal, accuracy: 1e-8)
    }

    func testSpringDayHasNoInventedHourOfRestingEnergy() throws {
        let clock = LocalDayWindows(timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/Copenhagen")))
        let window = try XCTUnwrap(clock.window(of: .init(year: 2026, month: 3, day: 29)))
        let a = Int(window.start.timeIntervalSince1970), b = Int(window.nextStart.timeIntervalSince1970)
        XCTAssertEqual(b-a, 82_800)
        let hr = (a..<b).map { HRSample(ts: $0, bpm: 50) }
        let energy = Calories.estimateDayEnergy(hr, profile: profile, hrmax: 194.7,
            restingHR: nil, maxSpanSeconds: Double(b-a))
        XCTAssertEqual(energy.observedSeconds, 82_800)
    }
    func testConfirmedEarlyWakeIsNotExtendedByNearbyDetectedFragment() throws {
        let start = AnalyticsEngine.dayStartUtcSeconds("2026-10-28") - 3 * 3600
        let wake = start + 7 * 3600 // 21:00 to 04:00 UTC.
        let blocks = [SleepStageTotals.NightBlock(start: start, end: wake, boundsConfirmed: true),
                      SleepStageTotals.NightBlock(start: wake + 30 * 60, end: wake + 2 * 3600)]
        XCTAssertEqual(SleepStageTotals.mainNightGroupIndices(blocks, offsetSec: 0), [0])
        let stages = "{\"light\":420}"
        let tail = "{\"light\":90}"
        let aggregate = try XCTUnwrap(SleepStageTotals.dailyAggregateHonoringEdits(
            detected: [(start, stages), (wake + 1800, tail)], edited: [start: stages],
            onsetByStart: [start: start, wake + 1800: wake + 1800], confirmedBounds: [start]))
        XCTAssertEqual(aggregate.sleep.totalSleepMin, 420)
        XCTAssertEqual(SleepStageTotals.mainNightGroupIndices([
            .init(start: start, end: wake), .init(start: wake+1800, end: wake+7200)], offsetSec: 0), [0,1])
    }

    func testOneRecordedHourCannotMakeWholeDayConfidenceSolid() {
        let start = AnalyticsEngine.dayStartUtcSeconds("2026-10-28")
        let hr = (0..<3600).map { HRSample(ts: start+$0, bpm: 120) }
        let result = AnalyticsEngine.analyzeDay(day: "2026-10-28", hr: hr, dayHr: hr,
            profile: profile, dayBounds: start..<(start+86400))
        XCTAssertEqual(result.hrCoverage?.recordedSeconds, 3600)
        XCTAssertEqual(result.hrCoverage?.longestGapSeconds, 82800)
        XCTAssertEqual(result.effortConfidence, .building)
        let elapsed = AnalyticsEngine.analyzeDay(day: "2026-10-28", hr: hr, dayHr: hr,
            profile: profile, dayBounds: start..<(start+3600))
        XCTAssertEqual(elapsed.effortConfidence, .solid)
    }

    func testCoverageDeduplicatesAndExcludesInvalidAndOutOfWindowSamples() {
        let samples = [HRSample(ts: 100, bpm: 100), HRSample(ts: 100, bpm: 110),
                       HRSample(ts: 101, bpm: 0), HRSample(ts: 99, bpm: 100), HRSample(ts: 110, bpm: 100)]
        let coverage = HRInputCoverage(samples: samples, window: 100..<110)
        XCTAssertEqual(coverage.recordedSeconds, 1)
        XCTAssertEqual(coverage.longestGapSeconds, 9)
        XCTAssertEqual(coverage.fraction, 0.1)
        XCTAssertFalse(coverage.isComplete)
    }

    func testConfirmedWakeFlowsThroughScoringSelection() {
        let midnight = AnalyticsEngine.dayStartUtcSeconds("2026-10-28")
        let start = midnight - 3*3600, wake = midnight + 4*3600
        let first = SleepSession(start: start, end: wake, efficiency: 1,
            stages: [.init(start: start, end: wake, stage: "light")], restingHR: nil, avgHRV: nil)
        let tail = SleepSession(start: wake+1800, end: wake+7200, efficiency: 1,
            stages: [.init(start: wake+1800, end: wake+7200, stage: "light")], restingHR: nil, avgHRV: nil)
        let result = AnalyticsEngine.analyzeDay(day: "2026-10-28", profile: profile,
            providedSleep: [tail, first], confirmedSleepStarts: [start])
        XCTAssertEqual(result.daily.totalSleepMin, 420)
        XCTAssertEqual(result.mainNightBlocks.map { $0.end }, [wake])
        XCTAssertEqual(result.sleepSessions.count, 2, "A separate candidate stays available for review")
    }

}
