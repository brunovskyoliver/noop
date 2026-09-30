import XCTest
@testable import Strand

/// The model-written follow-up chips: what survives the cleaner, and when the fixed chips take over.
final class CoachFollowUpsTests: XCTestCase {

    func testKeepsShortDistinctQuestions() {
        XCTAssertEqual(CoachFollowUps.clean(["How can I sleep deeper?", " \"why is my HRV low?\" ", "What should I eat tonight?"],
                                            asked: "How did I sleep?"),
                       ["How can I sleep deeper?", "Why is my HRV low?", "What should I eat tonight?"])
    }

    /// A chip is sent as the next question, so a number in it would be one the model made up.
    func testDropsNumbersRepeatsAndLongOnes() {
        XCTAssertEqual(CoachFollowUps.clean([
            "Should I sleep 8 hours?",
            "How did I sleep?",
            "HOW CAN I SLEEP DEEPER",
            "How can I sleep deeper?",
            "Could you please explain in much more detail what all of this means for me?",
            "",
            "Is tonight a good night to train?",
        ], asked: "how did I sleep"),
                       ["HOW CAN I SLEEP DEEPER?", "Is tonight a good night to train?"])
    }

    /// A chip is sent as the person's own words, so one addressed to them is dropped.
    func testDropsCoachVoiceAndAddsQuestionMark() {
        XCTAssertEqual(CoachFollowUps.clean(["What’s your HRV like tonight?", "How did stress affect my rest",
                                             "Can you explain that?", "You're doing great, right?"], asked: ""),
                       ["How did stress affect my rest?", "Can you explain that?"])
    }

    func testFewerThanTwoFallsBackAndAtMostThree() {
        XCTAssertNil(CoachFollowUps.clean(["What about 10 pm?", "Why?"], asked: "Why?"))
        XCTAssertEqual(CoachFollowUps.clean(["A one?", "B two?", "C three?", "D four?"], asked: "")?.count, 3)
    }
}
