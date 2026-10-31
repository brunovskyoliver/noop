import XCTest
import StrandAnalytics
import WhoopProtocol
@testable import Strand

final class WhoopHRVSourceTests: XCTestCase {
    func testBothWhoopGenerationsUseOpticalTiming() {
        XCTAssertEqual(LiveRules.hrvSnapshotSource(for: .whoop4), .opticalPPG)
        XCTAssertEqual(LiveRules.hrvSnapshotSource(for: .whoop5mg), .opticalPPG)
    }
}
