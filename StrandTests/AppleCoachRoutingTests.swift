import XCTest
@testable import Strand

/// The Apple Intelligence Coach's pure pieces: routing between the on-device model and Apple's Private Cloud
/// Compute, the availability state the Coach screen shows, the number validator and the context budget.
final class AppleCoachRoutingTests: XCTestCase {

    private func inputs(_ onDevice: AppleOnDeviceState, locale: Bool = true, pcc: ApplePrivateCloudState = .available,
                        pccLocale: Bool = true, fallback: Bool = true, tooLong: Bool = false,
                        rateLimited: Bool = false) -> AppleCoachRoutingInputs {
        AppleCoachRoutingInputs(onDevice: onDevice, onDeviceSupportsLocale: locale, privateCloud: pcc,
                                privateCloudSupportsLocale: pccLocale, fallbackAllowed: fallback,
                                exceedsOnDeviceContext: tooLong, onDeviceRateLimited: rateLimited)
    }

    func testOnDeviceFirst() {
        XCTAssertEqual(AppleCoachRouting.route(inputs(.available)), .onDevice)
        XCTAssertEqual(AppleCoachRouting.availability(inputs(.available)), .onDeviceReady)
    }

    func testFallsBackToApplesServersForEveryOnDeviceGap() {
        for i in [inputs(.appleIntelligenceNotEnabled), inputs(.modelNotReady), inputs(.deviceNotEligible),
                  inputs(.available, locale: false), inputs(.available, tooLong: true),
                  inputs(.available, rateLimited: true)] {
            XCTAssertEqual(AppleCoachRouting.route(i), .privateCloud, "\(i)")
        }
        XCTAssertEqual(AppleCoachRouting.availability(inputs(.modelNotReady)), .appleServersOnly)
    }

    func testFallbackOffNeverLeavesTheDevice() {
        XCTAssertEqual(AppleCoachRouting.route(inputs(.available, fallback: false, tooLong: true)), .none)
        XCTAssertEqual(AppleCoachRouting.route(inputs(.modelNotReady, fallback: false)), .none)
        XCTAssertEqual(AppleCoachRouting.availability(inputs(.modelNotReady, fallback: false)), .modelDownloading)
    }

    func testPrivateCloudNeedsItsOwnAvailabilityAndLocale() {
        XCTAssertEqual(AppleCoachRouting.route(inputs(.modelNotReady, pcc: .unavailable)), .none)
        XCTAssertEqual(AppleCoachRouting.route(inputs(.modelNotReady, pcc: .osTooOld)), .none)
        XCTAssertEqual(AppleCoachRouting.route(inputs(.modelNotReady, pccLocale: false)), .none)
    }

    func testAvailabilityNamesTheOnDeviceReason() {
        let noPCC: (AppleOnDeviceState, Bool) -> AppleCoachAvailability = {
            AppleCoachRouting.availability(self.inputs($0, locale: $1, pcc: .osTooOld))
        }
        XCTAssertEqual(noPCC(.appleIntelligenceNotEnabled, true), .appleIntelligenceOff)
        XCTAssertEqual(noPCC(.deviceNotEligible, true), .deviceNotEligible)
        XCTAssertEqual(noPCC(.modelNotReady, true), .modelDownloading)
        XCTAssertEqual(noPCC(.available, false), .languageNotSupported)
        // The framework reports an unsupported app language as "model not ready".
        XCTAssertEqual(noPCC(.modelNotReady, false), .languageNotSupported)
        XCTAssertEqual(noPCC(.osTooOld, true), .osTooOld)
        XCTAssertFalse(AppleCoachAvailability.languageNotSupported.canChat)
        XCTAssertTrue(AppleCoachAvailability.appleServersOnly.canChat)
    }
}
