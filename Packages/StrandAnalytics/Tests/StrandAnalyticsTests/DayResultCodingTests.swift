import Foundation
import XCTest
@testable import StrandAnalytics
import WhoopStore

final class DayResultCodingTests: XCTestCase {
    func testPopulatedResultPreservesStagesProvenanceAndDiagnostics() throws {
        let start = 1_783_640_000
        let stages = [StageSegment(start: start, end: start + 300, stage: "light"),
                      StageSegment(start: start + 300, end: start + 600, stage: "rem")]
        var funnel = WorkoutDetector.DetectionFunnel()
        funnel.hrSamples = 400
        funnel.motionSamples = 350
        funnel.restingHR = 55
        funnel.hrFloor = 70
        funnel.motionPassed = 320
        funnel.hrMissing = 20
        funnel.hrTooLow = 30
        funnel.active = 270
        funnel.runs = 5
        funnel.bridged = 4
        funnel.longestRunS = 1_800
        funnel.meanRunS = 700
        funnel.droppedShort = 1
        funnel.droppedNoHR = 1
        funnel.droppedLowIntensity = 1
        funnel.kept = 1
        let original = AnalyticsEngine.DayResult(
            daily: DailyMetric(day: "2026-09-10", totalSleepMin: 420, efficiency: 0.9,
                deepMin: 80, remMin: 90, lightMin: 250, disturbances: 2, restingHr: 52,
                avgHrv: 64.5, recovery: 72, strain: 30, exerciseCount: 1,
                spo2Pct: 97, skinTempDevC: 0.4, respRateBpm: 15, steps: 9_000,
                activeKcalEst: 456, spo2Red: 120, spo2Ir: 240, avgSdnn: 58,
                skinTempC: 34.1, sleepHrOnly: true),
            sleepSessions: [SleepSession(start: start, end: start + 600,
                efficiency: 0.9, stages: stages, restingHR: nil, avgHRV: nil, hrOnly: true)],
            cachedSleep: [CachedSleepSession(startTs: start, endTs: start + 600,
                efficiency: 0.9, restingHr: 52, avgHrv: 64.5,
                stagesJSON: String(decoding: try JSONEncoder().encode(stages), as: UTF8.self),
                userEdited: true, startTsAdjusted: start + 30, stagingSparse: true)],
            workouts: [ExerciseSession(start: start + 1_000, end: start + 2_800,
                avgHR: 130, peakHR: 155, strain: 22, durationS: 1_800,
                zoneTimePct: [1: 20, 2: 50, 3: 30], avgHRRPct: 55, hrmax: 185,
                hrmaxSource: "observed", caloriesKcal: 250, caloriesKJ: 1_046,
                hrCoveragePct: 83)],
            recovery: 72, strain: 30, nightlySkinTempC: 34.1, restScore: 88,
            chargeConfidence: .solid, effortConfidence: .building, restConfidence: .calibrating,
            sessionMotionByStart: [start: [0.01, 0.5]],
            sessionSleepStateByStart: [start: [1, 2]],
            chargeDrivers: [ChargeDriver(label: "HRV", deltaPoints: 4, valueText: "64.5 ms",
                baselineText: "60 ms", verdict: "Above baseline")],
            skinTempRelative: SkinTempRelative(deviationC: 0.4, tier: .warmer),
            detectionFunnel: funnel)
        try assertRoundTrip(original)
    }

    func testEmptyResultKeepsUnknownValuesAbsent() throws {
        let original = AnalyticsEngine.DayResult(
            daily: DailyMetric(day: "2026-09-10", totalSleepMin: nil, efficiency: nil,
                deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil),
            sleepSessions: [], cachedSleep: [], workouts: [], recovery: nil, strain: nil)
        try assertRoundTrip(original)
    }

    func testPrimarySessionCoverageRoundTrip() throws {
        let original = PrimarySessionRestingHR.Coverage(validSamples: 8_421, durationSec: 27_030)
        let restored = try JSONDecoder().decode(PrimarySessionRestingHR.Coverage.self,
                                                from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }

    private func assertRoundTrip(_ original: AnalyticsEngine.DayResult,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let restored = try JSONDecoder().decode(AnalyticsEngine.DayResult.self,
                                                from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.daily, original.daily, file: file, line: line)
        XCTAssertEqual(restored.sleepSessions, original.sleepSessions, file: file, line: line)
        XCTAssertEqual(restored.cachedSleep, original.cachedSleep, file: file, line: line)
        XCTAssertEqual(restored.workouts, original.workouts, file: file, line: line)
        XCTAssertEqual(restored.detectionFunnel, original.detectionFunnel, file: file, line: line)
        XCTAssertEqual(restored.recovery, original.recovery, file: file, line: line)
        XCTAssertEqual(restored.strain, original.strain, file: file, line: line)
        XCTAssertEqual(restored.restScore, original.restScore, file: file, line: line)
        XCTAssertEqual(restored.chargeDrivers, original.chargeDrivers, file: file, line: line)
        XCTAssertEqual(restored.skinTempRelative, original.skinTempRelative, file: file, line: line)
        XCTAssertEqual(restored.nightlySkinTempC, original.nightlySkinTempC, file: file, line: line)
        XCTAssertEqual(restored.chargeConfidence, original.chargeConfidence, file: file, line: line)
        XCTAssertEqual(restored.effortConfidence, original.effortConfidence, file: file, line: line)
        XCTAssertEqual(restored.restConfidence, original.restConfidence, file: file, line: line)
        XCTAssertEqual(restored.sessionMotionByStart, original.sessionMotionByStart, file: file, line: line)
        XCTAssertEqual(restored.sessionSleepStateByStart, original.sessionSleepStateByStart, file: file, line: line)
    }
}
