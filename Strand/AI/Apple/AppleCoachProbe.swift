import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads Apple Intelligence's state into `AppleCoachRoutingInputs`. The only place the Coach asks the
/// framework whether it can run; the answer then goes through the pure `AppleCoachRouting`.
///
/// Deployment targets stay iOS 17 / macOS 13: everything here is behind `canImport(FoundationModels)` and
/// `#available`, and an OS older than 26 reports `.osTooOld`.
enum AppleCoachProbe {

    static func inputs(fallbackAllowed: Bool, locale: Locale) async -> AppleCoachRoutingInputs {
        var i = AppleCoachRoutingInputs(onDevice: .osTooOld, onDeviceSupportsLocale: false, privateCloud: .osTooOld,
                                        privateCloudSupportsLocale: false, fallbackAllowed: fallbackAllowed)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            i.onDevice = onDeviceState(model.availability)
            i.onDeviceSupportsLocale = model.supportsLocale(locale)
            if #available(iOS 27.0, macOS 27.0, *) {
                let pcc = PrivateCloudComputeLanguageModel()
                i.privateCloud = pcc.isAvailable ? .available : .unavailable
                i.privateCloudSupportsLocale = pcc.isAvailable ? ((try? await pcc.supportsLocale(locale)) ?? false) : false
            }
        }
        #endif
        return i
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func onDeviceState(_ a: SystemLanguageModel.Availability) -> AppleOnDeviceState {
        switch a {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): return .modelNotReady
        // A reason added after this SDK: treat the device as unable, which offers Apple's servers if allowed.
        case .unavailable: return .deviceNotEligible
        }
    }
    #endif
}
