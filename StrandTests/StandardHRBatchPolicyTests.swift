import XCTest
@testable import Strand

final class StandardHRBatchPolicyTests: XCTestCase {
    func testSwiftOraclePinnedAcrossBoundaryCases() {
        let readings = [0, 1, 15, 29, 30, 31]
        let rows = [0, 1, 30, 120, 255, 256, 257]
        let ages: [Double] = [-1, 0, 29, 30, 31, .nan, .infinity]
        let actual = readings.map { reading in
            rows.flatMap { row in
                ages.map { StandardHRBatchPolicy.shouldFlush(readings: reading, rows: row, elapsedSeconds: $0) ? "1" : "0" }
            }.joined()
        }.joined(separator: "\n")
        // Standalone optimized Swift oracle stdout.
        XCTAssertEqual(actual, """
        0000000000110000011000001100000110011111111111111
        0000000000110000011000001100000110011111111111111
        0000000000110000011000001100000110011111111111111
        0000000000110000011000001100000110011111111111111
        0000000111111111111111111111111111111111111111111
        0000000111111111111111111111111111111111111111111
        """)
    }
}
