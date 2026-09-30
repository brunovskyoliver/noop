import XCTest
@testable import Strand

final class CoachTokenBudgetTests: XCTestCase {

    func testEstimateCountsLatinByCharactersAndCJKByGlyph() {
        XCTAssertEqual(CoachTokenBudget.estimate(String(repeating: "a", count: 35)), 10)
        XCTAssertEqual(CoachTokenBudget.estimate("睡眠不足"), 4)
        XCTAssertEqual(CoachTokenBudget.estimate(""), 0)
    }

    func testCondensesNearTheContextLimit() {
        // 4096 × 0.9 = 3686.4; reply reserve 900.
        XCTAssertFalse(CoachTokenBudget.needsCondense(sessionTokens: 2500, promptTokens: 200, contextSize: 4096))
        XCTAssertTrue(CoachTokenBudget.needsCondense(sessionTokens: 2700, promptTokens: 100, contextSize: 4096))
        XCTAssertFalse(CoachTokenBudget.needsCondense(sessionTokens: 2700, promptTokens: 100, contextSize: 8192))
        // Unknown size falls back to the documented 4096.
        XCTAssertTrue(CoachTokenBudget.needsCondense(sessionTokens: 2700, promptTokens: 100, contextSize: 0))
    }
}
