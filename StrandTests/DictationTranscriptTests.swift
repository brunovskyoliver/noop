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

    /// An end marker on every partial result must not repeat the text.
    func testEndMarkersOnPartialsDoNotRepeat() {
        var t = DictationTranscript()
        t.update("I", utteranceEnded: true)
        t.update("I had", utteranceEnded: true)
        t.update("I had two coffees", utteranceEnded: true)
        XCTAssertEqual(t.text, "I had two coffees")
        t.update("Then", utteranceEnded: false)
        XCTAssertEqual(t.update("Then a beer", utteranceEnded: true), "I had two coffees Then a beer")
    }

    /// Revisions of the same utterance replace, never stack.
    func testRevisionsReplaceTheUtteranceInProgress() {
        var t = DictationTranscript()
        t.update("Hi had", utteranceEnded: false)
        t.update("I had two", utteranceEnded: false)
        XCTAssertEqual(t.update("I had to coffees", utteranceEnded: false), "I had to coffees")
        XCTAssertEqual(t.update("I had two coffees", utteranceEnded: false), "I had two coffees")
    }

    /// English with a Slovak region setting has no Slovak-English recognizer: fall back to US English.
    func testSpeechLocaleFallsBackWithinTheLanguage() {
        let supported = ["en-US", "en-GB", "en-AU", "de-DE", "de-AT", "sk-SK"]
        XCTAssertEqual(DictationLocale.pick(language: "en", region: "SK", supported: supported), "en-US")
        XCTAssertEqual(DictationLocale.pick(language: "en", region: "GB", supported: supported), "en-GB")
        XCTAssertEqual(DictationLocale.pick(language: "de", region: "CH", supported: supported), "de-AT")
        XCTAssertEqual(DictationLocale.pick(language: "sk", region: nil, supported: supported), "sk-SK")
        XCTAssertNil(DictationLocale.pick(language: "pl", region: "PL", supported: supported))
    }
}
