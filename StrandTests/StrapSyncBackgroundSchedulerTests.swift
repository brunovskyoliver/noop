import XCTest
@testable import Strand

@MainActor
final class StrapSyncBackgroundSchedulerTests: XCTestCase {
    func testWakeWaitsForAnActualCompletedOffload() async {
        var requests = 0
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: { requests += 1 }, completed: { ticks == 3 },
            wait: { ticks += 1 }, attempts: 5)
        XCTAssertTrue(success)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(ticks, 3)
    }

    func testAnOutstandingConnectIsNotReportedAsCompletedSync() async {
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: {}, completed: { false }, wait: { ticks += 1 }, attempts: 5)
        XCTAssertFalse(success)
        XCTAssertEqual(ticks, 5)
    }

    func testExpirationStopsWaitingWithoutClaimingSuccess() async {
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: {}, completed: { false },
            wait: { ticks += 1; throw CancellationError() }, attempts: 5)
        XCTAssertFalse(success)
        XCTAssertEqual(ticks, 1)
    }
}
