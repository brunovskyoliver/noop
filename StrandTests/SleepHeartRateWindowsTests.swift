import XCTest
@testable import Strand

final class SleepHeartRateWindowsTests: XCTestCase {
    func testMissingEpochsStayOnTheGrid() {
        let grid = SleepHeartRateWindows.grid(from: 0, to: 1200, buckets: [0: 60, 600: 70])
        XCTAssertEqual(grid.count, 4)
        XCTAssertEqual(grid, [60, nil, 70, nil])
    }

    func testOnlyWholeEpochsAreIncluded() {
        let grid = SleepHeartRateWindows.grid(from: 100, to: 1199, buckets: [0: 50, 300: 60, 600: 70, 900: 80])
        XCTAssertEqual(grid, [60, 70])
    }

    func testNapsExcludeOverlappingWakeEpochsWithoutImputingGaps() {
        let grid = SleepHeartRateWindows.grid(from: 0, to: 1500,
                                              buckets: [0: 60, 300: 70, 600: 50, 900: 80],
                                              excluding: [450..<750])
        XCTAssertEqual(grid, [60, 80, nil])
    }

    func testTooShortAWindowHasNoEpochs() {
        XCTAssertTrue(SleepHeartRateWindows.grid(from: 100, to: 599, buckets: [:]).isEmpty)
    }
}
