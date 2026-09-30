import Foundation

// AppleCoachRouting.swift — where an Apple Intelligence Coach turn runs, and what the Coach screen says when
// it cannot run. Pure (no FoundationModels import) so it is unit-tested on every OS and toolchain; the engine
// maps the framework's availability types onto these inputs.

/// The on-device system model's state (`SystemLanguageModel.default.availability`, plus "OS older than 26").
enum AppleOnDeviceState: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// iOS/macOS older than 26: no FoundationModels at all.
    case osTooOld
}

/// Apple's Private Cloud Compute model (`PrivateCloudComputeLanguageModel`, iOS/macOS 27+).
enum ApplePrivateCloudState: Equatable, Sendable {
    case available
    case unavailable
    /// Older than 27: the type does not exist.
    case osTooOld
}

/// What the Coach screen shows instead of failing. One resolver, `AppleCoachRouting.availability`.
enum AppleCoachAvailability: Equatable, Sendable {
    /// The on-device model can answer.
    case onDeviceReady
    /// The on-device model cannot, but Apple's servers can (27+, "Use Apple servers when needed" on).
    case appleServersOnly
    case appleIntelligenceOff
    case deviceNotEligible
    case modelDownloading
    case languageNotSupported
    case osTooOld

    /// Whether a conversation can start at all.
    var canChat: Bool { self == .onDeviceReady || self == .appleServersOnly }
}

/// Which model serves one turn.
enum AppleCoachRoute: Equatable, Sendable {
    case onDevice
    case privateCloud
    /// Neither can take this turn; the caller explains why from its own context.
    case none
}

struct AppleCoachRoutingInputs: Equatable, Sendable {
    var onDevice: AppleOnDeviceState
    /// `SystemLanguageModel.supportsLocale()` for the app's language.
    var onDeviceSupportsLocale: Bool
    var privateCloud: ApplePrivateCloudState
    /// `PrivateCloudComputeLanguageModel.supportsLocale()`; false when unknown.
    var privateCloudSupportsLocale: Bool
    /// The "Use Apple servers when needed" setting (on by default).
    var fallbackAllowed: Bool
    /// This turn still does not fit the on-device context after condensing the conversation.
    var exceedsOnDeviceContext = false
    /// The on-device model rate-limited this turn.
    var onDeviceRateLimited = false
}

enum AppleCoachRouting {

    /// On-device first; Apple's Private Cloud Compute only when the on-device model cannot serve the turn
    /// (unavailable, language unsupported, too long after condensing, or rate-limited) AND the user allows it.
    ///
    /// FORK DECISION: sending a turn to Apple's Private Cloud Compute is off-device processing, which
    /// NOOP's upstream scope (docs/SCOPE.md: offline by default, no cloud dependency) does not allow. This
    /// fork accepts it deliberately for the Coach only: default on with a visible toggle, every off-device
    /// reply labelled "via Apple servers", and the info sheet stating what leaves the phone. No other
    /// `LanguageModel` and no third-party server is reachable from this route.
    static func route(_ i: AppleCoachRoutingInputs) -> AppleCoachRoute {
        let onDeviceServes = i.onDevice == .available && i.onDeviceSupportsLocale
            && !i.exceedsOnDeviceContext && !i.onDeviceRateLimited
        if onDeviceServes { return .onDevice }
        if privateCloudServes(i) { return .privateCloud }
        return .none
    }

    /// The Coach screen's state before any turn: ready on-device, ready via Apple's servers, or why not.
    static func availability(_ i: AppleCoachRoutingInputs) -> AppleCoachAvailability {
        if i.onDevice == .available && i.onDeviceSupportsLocale { return .onDeviceReady }
        if privateCloudServes(i) { return .appleServersOnly }
        // An app language Apple Intelligence does not speak is reported with the model "not ready" (seen on
        // the iOS 27 simulator with Polish): name the language, not a download that will never finish.
        if i.onDevice == .modelNotReady && !i.onDeviceSupportsLocale { return .languageNotSupported }
        switch i.onDevice {
        case .osTooOld: return .osTooOld
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
        case .modelNotReady: return .modelDownloading
        case .available: return .languageNotSupported
        }
    }

    private static func privateCloudServes(_ i: AppleCoachRoutingInputs) -> Bool {
        i.fallbackAllowed && i.privateCloud == .available && i.privateCloudSupportsLocale
    }
}
