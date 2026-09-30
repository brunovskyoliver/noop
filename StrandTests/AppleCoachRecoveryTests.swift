import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Strand

/// What an Apple Intelligence turn does after a failure: one condense, one hand-over to Apple's servers (when
/// allowed), then a calm message; and how both OS versions' error types map onto one failure.
final class AppleCoachRecoveryTests: XCTestCase {

    private func inputs(fallback: Bool = true, pcc: ApplePrivateCloudState = .available) -> AppleCoachRoutingInputs {
        AppleCoachRoutingInputs(onDevice: .available, onDeviceSupportsLocale: true, privateCloud: pcc,
                                privateCloudSupportsLocale: true, fallbackAllowed: fallback)
    }

    func testContextOverflowCondensesOnceThenMovesToApplesServers() {
        XCTAssertEqual(AppleCoachRecovery.next(.contextTooLong, route: .onDevice, inputs: inputs(), alreadyCondensed: false),
                       .condenseAndRetry)
        var expected = inputs()
        expected.exceedsOnDeviceContext = true
        XCTAssertEqual(AppleCoachRecovery.next(.contextTooLong, route: .onDevice, inputs: inputs(), alreadyCondensed: true),
                       .retryOnPrivateCloud(expected))
        XCTAssertEqual(AppleCoachRecovery.next(.contextTooLong, route: .onDevice, inputs: inputs(fallback: false),
                                               alreadyCondensed: true),
                       .show(AppleCoachRecovery.message(.contextTooLong)))
    }

    func testRateLimitLanguageAndAssetsHandOverWhenAllowed() {
        for f in [AppleCoachFailure.rateLimited, .unsupportedLanguage, .modelUnavailable] {
            guard case .retryOnPrivateCloud = AppleCoachRecovery.next(f, route: .onDevice, inputs: inputs(), alreadyCondensed: false)
            else { return XCTFail("\(f)") }
            XCTAssertEqual(AppleCoachRecovery.next(f, route: .onDevice, inputs: inputs(pcc: .osTooOld), alreadyCondensed: false),
                           .show(AppleCoachRecovery.message(f)))
        }
    }

    /// Guardrails and refusals never go to another model: a calm message pointing to a professional.
    func testGuardrailAndRefusalStopWithACalmMessage() {
        for f in [AppleCoachFailure.guardrail, .refusal] {
            XCTAssertEqual(AppleCoachRecovery.next(f, route: .onDevice, inputs: inputs(), alreadyCondensed: false),
                           .show(AppleCoachRecovery.message(f)))
        }
        XCTAssertTrue(AppleCoachRecovery.message(.refusal).contains("professional"))
    }

    /// Errors on Apple's servers are final: no retry loop.
    func testPrivateCloudErrorsAreFinal() {
        for f in [AppleCoachFailure.network, .quota, .serviceUnavailable, .contextTooLong, .rateLimited] {
            XCTAssertEqual(AppleCoachRecovery.next(f, route: .privateCloud, inputs: inputs(), alreadyCondensed: false),
                           .show(AppleCoachRecovery.message(f)))
        }
    }

    /// A malformed tool call is retried once on the same model, then a calm message.
    func testBadToolCallRetriesOnceThenStops() {
        XCTAssertEqual(AppleCoachRecovery.next(.badToolCall, route: .onDevice, inputs: inputs(), alreadyCondensed: false),
                       .retrySame)
        XCTAssertEqual(AppleCoachRecovery.next(.badToolCall, route: .privateCloud, inputs: inputs(), alreadyCondensed: false),
                       .retrySame)
        XCTAssertEqual(AppleCoachRecovery.next(.badToolCall, route: .onDevice, inputs: inputs(), alreadyCondensed: false,
                                               alreadyRetried: true),
                       .show(AppleCoachRecovery.message(.other)))
    }

    func testCondensedSummaryKeepsNoNumbers() {
        XCTAssertEqual(AppleCoachClient.withoutNumbers("We talked about sleep. Your HRV was 48 ms. Then caffeine timing."),
                       "We talked about sleep. Then caffeine timing.")
    }

    #if canImport(FoundationModels)
    func testErrorTypesOfBothOSVersionsMapToOneFailure() throws {
        guard #available(macOS 27.0, *) else { throw XCTSkip("needs the macOS 27 error types") }
        let f = { (e: Error, r: AppleCoachRoute) in AppleCoachClient.failure(e, route: r) }
        XCTAssertEqual(f(LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "")), .onDevice), .contextTooLong)
        XCTAssertEqual(f(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "")), .onDevice), .rateLimited)
        XCTAssertEqual(f(LanguageModelError.refusal(.init(explanation: "", debugDescription: "")), .onDevice), .refusal)
        XCTAssertEqual(f(LanguageModelError.unsupportedLanguageOrLocale(.init(languageCode: Locale.LanguageCode("pl"), debugDescription: "")), .onDevice), .unsupportedLanguage)
        XCTAssertEqual(f(LanguageModelSession.Error.concurrentRequests, .onDevice), .busy)
        XCTAssertEqual(f(PrivateCloudComputeLanguageModel.Error.networkFailure(.init(debugDescription: "")), .privateCloud), .network)
        XCTAssertEqual(f(PrivateCloudComputeLanguageModel.Error.quotaLimitReached(.init(debugDescription: "")), .privateCloud), .quota)
        XCTAssertEqual(f(PrivateCloudComputeLanguageModel.Error.serviceUnavailable(.init(debugDescription: "")), .privateCloud), .serviceUnavailable)
        // 26.x path, still thrown by devices on 26.
        let ctx = LanguageModelSession.GenerationError.Context(debugDescription: "")
        XCTAssertEqual(f(LanguageModelSession.GenerationError.exceededContextWindowSize(ctx), .onDevice), .contextTooLong)
        XCTAssertEqual(f(LanguageModelSession.GenerationError.guardrailViolation(ctx), .onDevice), .guardrail)
        XCTAssertEqual(f(LanguageModelSession.GenerationError.assetsUnavailable(ctx), .onDevice), .modelUnavailable)
        XCTAssertEqual(f(LanguageModelSession.GenerationError.rateLimited(ctx), .onDevice), .rateLimited)
        // Untyped framework errors: service trouble on Apple's servers, generic on-device.
        let untyped = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        XCTAssertEqual(f(untyped, .privateCloud), .serviceUnavailable)
        XCTAssertEqual(f(untyped, .onDevice), .other)
    }
    #endif
}
