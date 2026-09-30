import XCTest
@testable import Strand

/// Dictation across pauses: what was said before a pause stays in the field.
final class DictationTranscriptTests: XCTestCase {

    /// The recognizer marks the end of an utterance; the next one starts from nothing.
    func testKeepsUtterancesTheRecognizerEnded() {
        var t = DictationTranscript()
        t.update("Two", utteranceEnded: false)
        t.update("Two coffees", utteranceEnded: false)
        t.update("Two coffees today", utteranceEnded: true)
        t.update("A beer", utteranceEnded: false)
        XCTAssertEqual(t.update("A beer with dinner", utteranceEnded: false), "Two coffees today A beer with dinner")
    }

    /// No end marker: a result that stops continuing the previous one starts a new utterance.
    func testDetectsASilentResetAfterAPause() {
        var t = DictationTranscript()
        t.update("I had two coffees", utteranceEnded: false)
        t.update("I had two coffees today", utteranceEnded: false)
        t.update("Then", utteranceEnded: false)
        XCTAssertEqual(t.update("Then a glass of wine", utteranceEnded: false), "I had two coffees today Then a glass of wine")
    }

    /// Revisions of the same utterance replace, never stack.
    func testRevisionsReplaceTheUtteranceInProgress() {
        var t = DictationTranscript()
        t.update("Hi had", utteranceEnded: false)
        t.update("I had two", utteranceEnded: false)
        XCTAssertEqual(t.update("I had to coffees", utteranceEnded: false), "I had to coffees")
        XCTAssertEqual(t.update("I had two coffees", utteranceEnded: false), "I had two coffees")
    }
}
