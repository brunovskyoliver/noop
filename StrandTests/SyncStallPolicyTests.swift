import XCTest
@testable import Strand

final class SyncStallPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testCompletedSyncMovesTheDeadlineWhileAppOpenDoesNotResetIt() {
        let original = SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: 9_500,
                                                monitoringSince: now, now: now, syncInterval: 300)
        XCTAssertEqual(original, Date(timeIntervalSince1970: 11_300))
        let reopened = SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: 9_500,
                                                monitoringSince: now, now: now.addingTimeInterval(600), syncInterval: 300)
        XCTAssertEqual(original, reopened)
        let synced = SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: 10_600,
                                             monitoringSince: now, now: now.addingTimeInterval(600), syncInterval: 300)
        XCTAssertEqual(synced, Date(timeIntervalSince1970: 12_400))
    }

    func testPowerSavingAllowsTwoHourlyIntervals() {
        XCTAssertEqual(SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: 10_000,
                                               monitoringSince: now, now: now, syncInterval: 3_600),
                       now.addingTimeInterval(7_200))
    }

    func testDisabledOrUserDisconnectedCancelsReminder() {
        XCTAssertNil(SyncStallPolicy.deadline(enabled: false, expectsSync: true, lastSyncAt: 1,
                                             monitoringSince: now, now: now, syncInterval: 300))
        XCTAssertNil(SyncStallPolicy.deadline(enabled: true, expectsSync: false, lastSyncAt: 1,
                                             monitoringSince: now, now: now, syncInterval: 300))
    }

    func testNeverSyncedAndInvalidDatesDoNotDisableTheReminder() {
        for last in [nil, .nan, .infinity, 20_000, -1] as [Double?] {
            XCTAssertEqual(SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: last,
                                                   monitoringSince: now, now: now, syncInterval: 300),
                           now.addingTimeInterval(1_800))
        }
    }

    func testOverdueReminderAllowsBriefReconnectOnOpen() {
        XCTAssertEqual(SyncStallPolicy.deadline(enabled: true, expectsSync: true, lastSyncAt: 1,
                                               monitoringSince: now, now: now, syncInterval: 300),
                       now.addingTimeInterval(60))
    }
}
