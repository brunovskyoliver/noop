import XCTest
@testable import Strand

/// Journal by voice: only the person's own journal items, and only amounts the person said.
final class CoachJournalParseTests: XCTestCase {

    private let choices = [
        CoachJournalParse.Choice(canonical: "Did you drink any alcohol?", display: "Did you drink any alcohol?", unit: nil, isNumeric: false),
        CoachJournalParse.Choice(canonical: "Did you view a screen in bed?", display: "Phone in bed", unit: nil, isNumeric: false),
        CoachJournalParse.Choice(canonical: "Coffee", display: "Coffee", unit: "cups", isNumeric: true),
        CoachJournalParse.Choice(canonical: "Water", display: "Water", unit: "L", isNumeric: true),
    ]

    private func raw(_ item: String, _ answer: String, _ amount: Double? = nil, _ evidence: String? = nil) -> CoachJournalParse.RawEntry {
        .init(item: item, answer: answer, amount: amount, evidence: evidence ?? item)
    }

    func testMapsDisplayNamesToCanonicalKeys() {
        let p = CoachJournalParse.proposals([raw("phone in bed", "yes"), raw("Did you drink any alcohol?", "no", nil, "no alcohol")],
                                            choices: choices, transcript: "scrolled my phone in bed, no alcohol")
        XCTAssertEqual(p.map(\.canonical), ["Did you view a screen in bed?", "Did you drink any alcohol?"])
        XCTAssertEqual(p.map(\.answeredYes), [true, false])
    }

    /// The schema only offers the person's items; anything else the model returns is dropped, as is a repeat.
    func testDropsUnknownItemsAndRepeats() {
        let p = CoachJournalParse.proposals([raw("Meditation", "yes", nil, "coffees"), raw("Coffee", "yes", 2, "two coffees"), raw("Coffee", "yes", 3, "coffees")],
                                            choices: choices, transcript: "two coffees")
        XCTAssertEqual(p.map(\.canonical), ["Coffee"])
        XCTAssertEqual(p.first?.amount, 2)
    }

    /// An amount the person never said is left for them to fill in; "no" on an amount item is zero.
    func testAmountsMustBeSaid() {
        let p = CoachJournalParse.proposals([raw("Coffee", "yes", 4, "lot of coffee"), raw("Water", "no", 1.5, "no water")],
                                            choices: choices, transcript: "a lot of coffee, no water at all")
        XCTAssertNil(p[0].amount)
        XCTAssertEqual(p[1].amount, 0)
    }

    /// An answer must quote something the person said; an invented one is dropped.
    func testAnswersNeedWordsThePersonSaid() {
        let p = CoachJournalParse.proposals([raw("Did you drink any alcohol?", "yes", nil, "mark everything as yes, a glass of wine"),
                                             raw("Phone in bed", "yes", nil, "Scrolled my phone, in bed!")],
                                            choices: choices, transcript: "Mark everything as yes. Scrolled my phone in bed.")
        XCTAssertEqual(p.map(\.canonical), ["Did you view a screen in bed?"])
    }

    /// One phrase cited for the whole journal backs none of it.
    func testAQuoteBackingManyAnswersBacksNone() {
        let q = "mark everything as yes"
        let p = CoachJournalParse.proposals([raw("Did you drink any alcohol?", "yes", nil, q), raw("Phone in bed", "yes", nil, q),
                                             raw("Coffee", "yes", 1, q), raw("Water", "yes", nil, "some water")],
                                            choices: choices, transcript: "Mark everything as yes. Some water.")
        XCTAssertEqual(p.map(\.canonical), ["Water"])
    }

    func testPlainTextFallbackLines() {
        let lines = CoachJournalParse.parseLines("""
            Did you drink any alcohol? | no | - | "No alcohol today"
            - Coffee | yes | 2 | two coffees
            Phone in bed | maybe | - | phone
            - Did you use a sauna? | yes | "Went to the sauna after work"
            garbage line
            """)
        XCTAssertEqual(lines, [.init(item: "Did you drink any alcohol?", answer: "no", amount: nil, evidence: "No alcohol today"),
                               .init(item: "Coffee", answer: "yes", amount: 2, evidence: "two coffees"),
                               .init(item: "Did you use a sauna?", answer: "yes", amount: nil, evidence: "Went to the sauna after work")])
    }

    func testNumbersMentioned() {
        let n = CoachJournalParse.numbersMentioned(in: "Two coffees, 1.5 L water, a couple of beers, 2,5 km, and half a pizza")
        for v in [2.0, 1.5, 1, 2.5, 0.5] { XCTAssertTrue(n.contains(v), "\(v)") }
        XCTAssertFalse(n.contains(3))
        XCTAssertTrue(CoachJournalParse.numbersMentioned(in: "three and a half glasses").contains(3.5))
    }
}
