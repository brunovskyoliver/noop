import XCTest
@testable import StrandAnalytics

final class SleepPlannerTests: XCTestCase {

    /// 8 h need, 0.88 efficiency default, 15 min latency, wake 07:00:
    /// in bed = 480/0.88 + 15 = 560.45 min → bed 21:39.55 → rounded to 21:40.
    func testBaselinePlan() {
        let p = SleepPlanner.plan(.init(baseNeedHours: 8, wakeMinute: 7 * 60))
        XCTAssertEqual(p.needMin, 480)
        XCTAssertEqual(p.efficiency, 0.88)
        XCTAssertEqual(p.target.bedMinute, 21 * 60 + 40)
        XCTAssertEqual(p.tiers.map(\.fraction), [1.0, 0.85, 0.70])
        XCTAssertTrue(p.tiers[1].bedMinute > p.target.bedMinute)
        XCTAssertTrue(p.tiers.allSatisfy(\.reachable))
    }

    /// Debt adds a third, capped at 90 min; naps subtract, capped at 60.
    func testNeedBreakdown() {
        let p = SleepPlanner.plan(.init(baseNeedHours: 8, debtMin: 120, napMin: 25, wakeMinute: 420))
        XCTAssertEqual(p.debtAddMin, 39.6, accuracy: 1e-9)
        XCTAssertEqual(p.napSubMin, 25)
        XCTAssertEqual(p.needMin, 480 + 39.6 - 25, accuracy: 1e-9)
        let big = SleepPlanner.plan(.init(baseNeedHours: 8, debtMin: 600, napMin: 200, wakeMinute: 420))
        XCTAssertEqual(big.debtAddMin, 90)
        XCTAssertEqual(big.napSubMin, 60)
    }

    /// Efficiency: median of recent nights, percent values normalised, clamped; default below 3 nights.
    func testEfficiency() {
        XCTAssertEqual(SleepPlanner.efficiency([0.9, 0.8]), 0.88)
        XCTAssertEqual(SleepPlanner.efficiency([90, 80, 85]), 0.85, accuracy: 1e-12)
        XCTAssertEqual(SleepPlanner.efficiency([0.99, 0.99, 0.99]), 0.97)
        XCTAssertEqual(SleepPlanner.efficiency([0.5, 0.5, 0.6, 0.6]), 0.75)
    }

    /// Usual bedtime is a median across midnight: 23:30, 00:10, 23:50 → 23:50.
    func testUsualBedtimeAcrossMidnight() {
        XCTAssertEqual(SleepPlanner.usualBedMinute([23 * 60 + 30, 10, 23 * 60 + 50]), 23 * 60 + 50)
        XCTAssertEqual(SleepPlanner.usualBedMinute([23 * 60 + 30, 30]), 0)
        XCTAssertNil(SleepPlanner.usualBedMinute([]))
    }

    /// A bedtime more than 90 min before the usual one is capped and marked not reachable.
    func testGuardCapsTooEarlyBedtime() {
        // Usual bed 00:30; full need wants 21:40 (170 min earlier) → capped at 23:00.
        let p = SleepPlanner.plan(.init(baseNeedHours: 8, wakeMinute: 420, recentBedMinutes: [30, 30, 30]))
        XCTAssertEqual(p.usualBedMinute, 30)
        XCTAssertEqual(p.target.bedMinute, 23 * 60)
        XCTAssertFalse(p.target.reachable)
        // 23:00 → 07:00 is 480 min in bed: (480 − 15) × 0.88 = 409.2 min of sleep expected.
        XCTAssertEqual(p.target.expectedSleepMin, 409.2, accuracy: 1e-9)
        // A later bedtime than usual is never moved.
        let late = SleepPlanner.plan(.init(baseNeedHours: 6, wakeMinute: 420, recentBedMinutes: [22 * 60]))
        XCTAssertTrue(late.target.reachable)
    }

    /// An early wake wraps the bedtime into the previous evening.
    func testEarlyWakeWraps() {
        let p = SleepPlanner.plan(.init(baseNeedHours: 8, wakeMinute: 4 * 60))
        XCTAssertEqual(p.target.bedMinute, 18 * 60 + 40)
    }

    /// Pinned for the Kotlin twin (`SleepPlannerTest.oracle`).
    func testOracle() {
        let p = SleepPlanner.plan(.init(baseNeedHours: 8.25, debtMin: 73.5, napMin: 12, efficiencies: [0.91, 87, 0.84, 0.9, 0.86],
                                        latencyMin: 20, wakeMinute: 6 * 60 + 45,
                                        recentBedMinutes: [23 * 60 + 10, 23 * 60 + 55, 22 * 60 + 40, 5, 23 * 60 + 20]))
        XCTAssertEqual(p.needMin, 507.255)
        XCTAssertEqual(p.efficiency, 0.87)
        XCTAssertEqual(p.usualBedMinute, 23 * 60 + 20)
        XCTAssertEqual(p.tiers.map(\.bedMinute), [21 * 60 + 50, 22 * 60 + 10, 23 * 60 + 35])
        // Full need wants 20:40, 160 min before the usual 23:20, so it is capped at 21:50.
        XCTAssertEqual(p.tiers.map(\.reachable), [false, true, true])
        XCTAssertEqual(p.tiers.map(\.inBedMin), [603.051724137931, 515.5939655172414, 428.1362068965517])
    }

    /// Every plan's bed-to-wake window fits `maxWindowMin`, the bound the wind-down reminder clamps to, and
    /// the bound is reached (a smaller one would move the reminder off the planner's bedtime).
    func testWindowNeverExceedsTheSharedMaximum() {
        var longest = 0
        for wake in stride(from: 0, to: 1440, by: 1) {
            for need in [8.0, 10.5, 12.0] {
                let p = SleepPlanner.plan(.init(baseNeedHours: need, debtMin: 300, efficiencies: [0.75, 0.75, 0.75],
                                                wakeMinute: wake))
                for t in p.tiers {
                    let window = ((p.wakeMinute - t.bedMinute) % 1440 + 1440) % 1440
                    XCTAssertLessThanOrEqual(window, SleepPlanner.maxWindowMin)
                    longest = max(longest, window)
                }
            }
        }
        XCTAssertEqual(longest, SleepPlanner.maxWindowMin)
    }
}
