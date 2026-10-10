import XCTest
@testable import Strand

@MainActor
final class StrapSyncBackgroundSchedulerTests: XCTestCase {
    func testWakeWaitsForAnActualCompletedOffload() async {
        var requests = 0
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: { requests += 1; return .waitingForSync }, completed: { ticks == 3 },
            wait: { ticks += 1 }, attempts: 5)
        XCTAssertEqual(success, .offloadCompleted)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(ticks, 3)
    }

    func testAnOutstandingConnectIsNotReportedAsCompletedSync() async {
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: { .waitingForSync }, completed: { false }, wait: { ticks += 1 }, attempts: 5)
        XCTAssertEqual(success, .incomplete)
        XCTAssertEqual(ticks, 5)
    }

    func testExpirationStopsWaitingWithoutClaimingSuccess() async {
        var ticks = 0
        let success = await StrapSyncBackgroundScheduler.perform(
            prepare: { .waitingForSync }, completed: { false },
            wait: { ticks += 1; throw CancellationError() }, attempts: 5)
        XCTAssertEqual(success, .incomplete)
        XCTAssertEqual(ticks, 1)
    }

    func testFreshLinkFinishesWithoutPollingOrClaimingAnOffload() async {
        var ticks = 0
        let outcome = await StrapSyncBackgroundScheduler.perform(
            prepare: { .nothingDue }, completed: { false }, wait: { ticks += 1 })
        XCTAssertEqual(outcome, .alreadyFresh)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(ticks, 0)
        XCTAssertEqual(outcome.logLine, "Background strap sync: already fresh; no offload needed")
    }

    func testUnavailableStrapDoesNotPoll() async {
        var ticks = 0
        let outcome = await StrapSyncBackgroundScheduler.perform(
            prepare: { .unavailable }, completed: { false }, wait: { ticks += 1 })
        XCTAssertEqual(outcome, .incomplete)
        XCTAssertEqual(ticks, 0)
    }

    func testFreshnessRequiresHealthyBondAndCompletedHistory() {
        func preparation(connected: Bool = true, bonded: Bool = true, backfilling: Bool = false,
                         started: Bool = false, error: Bool = false, pending: Bool = false,
                         last: TimeInterval? = 900) -> StrapSyncBackgroundScheduler.Preparation {
            BLEManager.backgroundSyncPreparation(
                connected: connected, bonded: bonded, backfilling: backfilling, syncStarted: started,
                hasSyncError: error, historyPending: pending, lastCompletedAt: last, now: 1000, interval: 300)
        }
        XCTAssertEqual(preparation(), .nothingDue)
        XCTAssertEqual(preparation(connected: false), .waitingForSync)
        XCTAssertEqual(preparation(bonded: false), .waitingForSync)
        XCTAssertEqual(preparation(backfilling: true), .waitingForSync)
        XCTAssertEqual(preparation(started: true), .waitingForSync)
        XCTAssertEqual(preparation(error: true), .waitingForSync)
        XCTAssertEqual(preparation(pending: true), .waitingForSync)
        XCTAssertEqual(preparation(last: nil), .waitingForSync)
        XCTAssertEqual(preparation(last: 700), .waitingForSync)
        XCTAssertEqual(preparation(last: 1001), .waitingForSync)
    }
}
