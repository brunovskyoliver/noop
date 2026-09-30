import XCTest
@testable import Strand

final class CoachNumberValidatorTests: XCTestCase {

    private let facts = """
    Charge 64% (scored today). Rest 81%. Effort 9.4 of 21, target 10.2 to 13.8 (optimal zone).
    HRV readiness: within your usual range, 48.3 ms (usual 44 to 55 ms).
    Tonight's plan: bed 21:40, wake 07:00, need 8 h 29 min, reachable.
    Steps 10,432.
    """

    private func check(_ reply: String, user: String = "") -> [String] {
        CoachNumberValidator.validate(reply: reply, sources: [facts, user]).offending
    }

    func testFactsAtDisplayPrecisionPass() {
        XCTAssertEqual(check("Your Charge is **64%** and Rest 81%, so aim for 10.2 to 13.8 Effort."), [])
        XCTAssertEqual(check("HRV sits at 48 ms, inside your 44 to 55 ms range."), [])
        XCTAssertEqual(check("Bed at 21:40 gives you 8 h 29 min before 07:00."), [])
        XCTAssertEqual(check("Bed at 9:40 PM, up at 7:00 AM."), [])
        XCTAssertEqual(check("You've walked 10,432 steps."), [])
        XCTAssertEqual(check("You've walked 10432 steps."), [])
    }

    func testInventedNumbersFail() {
        XCTAssertEqual(check("Your Charge is 65%."), ["65"])
        XCTAssertEqual(check("HRV 48.30 ms"), ["48.30"])
        XCTAssertEqual(check("Most adults need 6 to 7 hours."), ["6", "7"])
        XCTAssertEqual(check("Go to bed at 22:15."), ["22:15"])
        XCTAssertEqual(check("That's about 8.5 hours."), ["8.5"])
    }

    func testMoreDecimalsThanTheFactFail() {
        XCTAssertEqual(check("Charge 64.0%"), ["64.0"])
        XCTAssertEqual(check("Effort 9.4"), [])
        XCTAssertEqual(check("Effort 9"), [])
    }

    func testUserTypedCountsAndTimesPass() {
        XCTAssertEqual(check("A 5 km run at 18:30 fits under your target.", user: "I plan a 5 km run at 18:30"), [])
    }

    func testListMarkersAndDigitsInWordsAreNotNumbers() {
        XCTAssertEqual(check("1. Keep Effort near 10.2.\n2) Check SpO2 later."), [])
    }

    func testTokensReadDecimalCommaAndTimes() {
        let t = CoachNumberValidator.tokens(in: "HRV 48,3 ms um 21:40, 7 PM")
        XCTAssertEqual(t.map(\.raw), ["48,3", "21:40", "7 PM"])
        XCTAssertEqual(t[0].value, 48.3, accuracy: 1e-9)
        XCTAssertEqual(t[1].minuteOfDay, 1300)
        XCTAssertEqual(t[2].minuteOfDay, 1140)
    }
}
