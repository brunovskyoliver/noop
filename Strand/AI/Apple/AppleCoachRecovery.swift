import Foundation

/// What went wrong with an Apple Intelligence turn, independent of which OS's error type reported it.
/// The client maps iOS 27's `LanguageModelError` / `LanguageModelSession.Error` / `SystemLanguageModel.Error`
/// / `PrivateCloudComputeLanguageModel.Error` and 26.x's `LanguageModelSession.GenerationError` onto this.
enum AppleCoachFailure: Equatable, Sendable {
    case contextTooLong
    case rateLimited
    case guardrail
    case refusal
    case unsupportedLanguage
    case timeout
    case busy
    case modelUnavailable
    /// Private Cloud Compute: no connection.
    case network
    /// Private Cloud Compute: the usage limit.
    case quota
    /// Private Cloud Compute: the service is down or refused the app.
    case serviceUnavailable
    /// The model called a tool with arguments that did not decode (the app's tools never throw).
    case badToolCall
    case other
}

/// The next step after a failed turn. At most one condense and one hand-over to Apple's servers per turn,
/// then a calm message: never a retry loop, never an error dump. Pure; unit-tested.
enum AppleCoachRecovery {

    enum Step: Equatable, Sendable {
        /// Summarise the conversation into a fresh on-device session and ask again.
        case condenseAndRetry
        /// Ask the same model once more (a malformed tool call is usually a one-off).
        case retrySame
        /// Ask Apple's servers instead, with this routing change.
        case retryOnPrivateCloud(AppleCoachRoutingInputs)
        /// Stop and show this message.
        case show(String)
    }

    static func next(_ failure: AppleCoachFailure, route: AppleCoachRoute, inputs: AppleCoachRoutingInputs,
                     alreadyCondensed: Bool, alreadyRetried: Bool = false) -> Step {
        if failure == .badToolCall { return alreadyRetried ? .show(message(.other)) : .retrySame }
        guard route == .onDevice else { return .show(message(failure)) }
        var fallback = inputs
        switch failure {
        case .contextTooLong:
            if !alreadyCondensed { return .condenseAndRetry }
            fallback.exceedsOnDeviceContext = true
        case .rateLimited:
            fallback.onDeviceRateLimited = true
        case .unsupportedLanguage:
            fallback.onDeviceSupportsLocale = false
        case .modelUnavailable:
            fallback.onDevice = .modelNotReady
        default:
            return .show(message(failure))
        }
        return AppleCoachRouting.route(fallback) == .privateCloud ? .retryOnPrivateCloud(fallback) : .show(message(failure))
    }

    static func message(_ failure: AppleCoachFailure) -> String {
        switch failure {
        case .contextTooLong:
            return String(localized: "This conversation got too long for Coach. Start a new conversation to keep going.")
        case .rateLimited:
            return String(localized: "Coach is busy right now. Try again in a minute.")
        case .guardrail, .refusal:
            return String(localized: "Coach can't help with that topic. For anything about your health, a doctor or another professional is the right person to ask.")
        case .unsupportedLanguage:
            return String(localized: "Coach can't answer in this language yet.")
        case .timeout:
            return String(localized: "Coach took too long to answer. Try again.")
        case .busy:
            return String(localized: "Coach is still answering your last question.")
        case .modelUnavailable:
            return String(localized: "Apple Intelligence isn't ready on this iPhone right now. Try again later.")
        case .network:
            return String(localized: "Couldn't reach Apple's servers. Check your connection and try again.")
        case .quota:
            return String(localized: "You've reached the current limit for Apple's servers. Coach can use them again later.")
        case .serviceUnavailable:
            return String(localized: "Apple's servers aren't available right now. Try again later.")
        case .badToolCall, .other:
            return String(localized: "Coach couldn't answer that. Try again.")
        }
    }
}
