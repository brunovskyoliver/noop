import XCTest
import StrandAnalytics
import WhoopProtocol
@testable import Strand

final class WhoopHRVSourceTests: XCTestCase {
    func testBothWhoopGenerationsUseOpticalTiming() {
        XCTAssertEqual(LiveView.hrvSnapshotSource(for: .whoop4), .opticalPPG)
        XCTAssertEqual(LiveView.hrvSnapshotSource(for: .whoop5mg), .opticalPPG)
    }
}
