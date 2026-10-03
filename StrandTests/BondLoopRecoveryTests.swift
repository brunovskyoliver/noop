import XCTest
@testable import Strand

final class BondLoopRecoveryTests: XCTestCase {
    func testPauseDuringDisconnectParksAfterLiveStateIsCleared() {
        var recovery = BondLoopRecovery()
        var requests = 0
        let park = { requests += 1; return true }
        // The detector runs before didDisconnect clears LiveState.connected.
        XCTAssertFalse(recovery.parkIfDue(paused: true, connected: true,
                                         intentionalDisconnect: false, secondsSincePause: 0,
                                         justTripped: true, park: park))
        // The same delegate callback reaches the paused branch after clearing that state.
        XCTAssertTrue(recovery.parkIfDue(paused: true, connected: false,
                                        intentionalDisconnect: false, secondsSincePause: 0,
                                        park: park))
        XCTAssertEqual(requests, 1, "The overnight pause must leave a reconnect with CoreBluetooth")
        XCTAssertFalse(recovery.parkIfDue(paused: true, connected: false,
                                         intentionalDisconnect: false, secondsSincePause: 1,
                                         park: park))
        XCTAssertEqual(requests, 1, "A consumed request must retain the cooldown")
    }

    func testUnavailableRadioDoesNotConsumeInitialRecovery() {
        var recovery = BondLoopRecovery()
        XCTAssertFalse(recovery.parkIfDue(paused: true, connected: false,
                                         intentionalDisconnect: false, secondsSincePause: 0,
                                         justTripped: true, park: { false }))
        XCTAssertTrue(recovery.parkIfDue(paused: true, connected: false,
                                        intentionalDisconnect: false, secondsSincePause: 1,
                                        park: { true }))
    }

    func testUserDisconnectAndInactivePauseDoNotReconnect() {
        for paused in [false, true] {
            var recovery = BondLoopRecovery()
            XCTAssertFalse(recovery.parkIfDue(paused: paused, connected: false,
                                             intentionalDisconnect: true, secondsSincePause: nil,
                                             justTripped: true, park: { XCTFail("User disconnected"); return true }))
        }
        var recovery = BondLoopRecovery()
        XCTAssertFalse(recovery.parkIfDue(paused: false, connected: false,
                                         intentionalDisconnect: false, secondsSincePause: nil,
                                         park: { XCTFail("Pause is not active"); return true }))
    }

    func testResetDiscardsThePendingRequest() {
        var recovery = BondLoopRecovery()
        _ = recovery.parkIfDue(paused: true, connected: true,
                               intentionalDisconnect: false, secondsSincePause: 0,
                               justTripped: true, park: { true })
        recovery.reset()
        XCTAssertFalse(recovery.parkIfDue(paused: true, connected: false,
                                         intentionalDisconnect: false, secondsSincePause: 1,
                                         park: { XCTFail("Old pause must not carry over"); return true }))
        XCTAssertTrue(recovery.parkIfDue(paused: true, connected: false,
                                        intentionalDisconnect: false, secondsSincePause: BondLoopRecovery.retryFloor,
                                        park: { true }))
    }
}
