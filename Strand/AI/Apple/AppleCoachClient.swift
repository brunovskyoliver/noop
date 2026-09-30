import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The reply being generated, observed ONLY by the streaming bubble, so a token re-renders that one view and
/// not the Coach screen. Snapshots are cumulative: `text` is replaced, never appended to.
@MainActor
final class CoachStreamState: ObservableObject {
    @Published var text = ""
    /// The turn is running on Apple's servers.
    @Published var offDevice = false
}

/// One Apple Intelligence turn's outcome.
enum AppleTurnResult: Equatable, Sendable {
    case reply(String, offDevice: Bool)
    /// The wording failed the number check twice: the facts the model looked up, without its prose.
    case factsOnly(String, offDevice: Bool)
    case failed(String)
}

/// Runs Apple Intelligence Coach turns: on-device first (`SystemLanguageModel.default`), Apple's Private
/// Cloud Compute when `AppleCoachRouting` says so. Holds one session per model so a turn on Apple's servers
/// does not throw away the on-device conversation.
///
/// Per turn: condense first if the conversation is near the context limit; stream the reply; check every
/// number against the tools' output (`CoachNumberValidator`); if it fails, ask once more with a stricter
/// instruction; if that fails too, show the looked-up facts without the prose. Errors go through
/// `AppleCoachRecovery`: one condense, one hand-over to Apple's servers, then a calm message.
@MainActor
final class AppleCoachClient {

    private(set) var source: (any CoachFactsSource)?
    private let log = CoachToolLog()
    private var onDeviceSession: AnyObject?
    private var cloudSession: AnyObject?
    /// Characters that have gone into the on-device session (for the pre-26.4 token estimate).
    private var onDeviceChars = 0
    /// A condensed earlier conversation, prepended to the next prompt (never to the instructions).
    private var carriedSummary: String?
    private var condensedNotice = false

    /// Tool-schema overhead for the character estimate, about 70 tokens per tool.
    static let toolOverheadTokens = 350

    func attach(source: any CoachFactsSource) { self.source = source }

    /// A new conversation: drop both sessions and any carried summary.
    func reset() {
        onDeviceSession = nil
        cloudSession = nil
        onDeviceChars = 0
        carriedSummary = nil
        condensedNotice = false
    }

    /// True once after a turn that condensed the conversation, so the chat says so exactly once.
    func consumeCondensedNotice() -> Bool {
        defer { condensedNotice = false }
        return condensedNotice
    }

    /// Load the on-device model ahead of the first question (the Coach screen appearing).
    func prewarm(inputs: AppleCoachRoutingInputs) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), AppleCoachRouting.route(inputs) == .onDevice, let source {
            onDevice(source).prewarm(promptPrefix: nil)
        }
        #endif
    }

    /// The instructions for today's session.
    static func instructions(now: Date = Date()) -> String {
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: "effort.scale") ?? "")
        return CoachInstructions.text(.init(today: now, locale: AppLanguage.activeLocale,
                                            unitSystem: UserDefaults.standard.string(forKey: "units.system") ?? "metric",
                                            effortMax: scale == .whoop ? 21 : 100))
    }

    func respond(question: String, history: [ChatMessage], inputs: AppleCoachRoutingInputs,
                 stream: CoachStreamState) async -> AppleTurnResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await respondWithModel(question: question, history: history, inputs: inputs, stream: stream)
        }
        #endif
        return .failed(AppleCoachRecovery.message(.modelUnavailable))
    }

    #if canImport(FoundationModels)

    @available(iOS 26.0, macOS 26.0, *)
    private func respondWithModel(question: String, history: [ChatMessage], inputs start: AppleCoachRoutingInputs,
                                  stream: CoachStreamState) async -> AppleTurnResult {
        guard let source else { return .failed(AppleCoachRecovery.message(.other)) }
        var inputs = start
        var route = AppleCoachRouting.route(inputs)
        var condensed = false
        if route == .onDevice, await needsCondense(question: question) {
            await condense(history: history)
            condensed = true
        }
        // First try, at most one condense-and-retry, at most one hand-over to Apple's servers.
        for _ in 0..<3 {
            guard route != .none else {
                return .failed(AppleCoachRecovery.message(inputs.onDevice == .available ? .unsupportedLanguage : .modelUnavailable))
            }
            log.begin(includeCheckIns: CoachFactFormat.asksAboutCheckIns(question))
            stream.text = ""
            stream.offDevice = route == .privateCloud
            let session = route == .privateCloud ? cloud(source) : onDevice(source)
            let prompt = promptText(question)
            do {
                let text = try await streamReply(session, prompt: prompt, into: stream)
                if route == .onDevice { onDeviceChars += prompt.count + text.count + log.outputs.joined().count }
                carriedSummary = nil
                return await checked(text, question: question, session: session, route: route, stream: stream, source: source)
            } catch {
                let failure = Self.failure(error, route: route)
                switch AppleCoachRecovery.next(failure, route: route, inputs: inputs, alreadyCondensed: condensed) {
                case .condenseAndRetry:
                    await condense(history: history)
                    condensed = true
                case .retryOnPrivateCloud(let next):
                    inputs = next
                    route = .privateCloud
                case .show(let message):
                    return .failed(message)
                }
            }
        }
        return .failed(AppleCoachRecovery.message(.other))
    }

    /// The question, preceded once by the condensed earlier conversation when there is one.
    private func promptText(_ question: String) -> String {
        guard let summary = carriedSummary, !summary.isEmpty else { return question }
        return "Earlier in this conversation (context only): \(summary)\n\nQuestion: \(question)"
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func streamReply(_ session: LanguageModelSession, prompt: String, into stream: CoachStreamState) async throws -> String {
        var last = ""
        for try await snapshot in session.streamResponse(to: prompt, options: AppleCoachSessionFactory.factualOptions) {
            last = snapshot.content
            stream.text = last
        }
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validate the reply's numbers; retry once with a stricter instruction; then fall back to the facts.
    @available(iOS 26.0, macOS 26.0, *)
    private func checked(_ text: String, question: String, session: LanguageModelSession, route: AppleCoachRoute,
                         stream: CoachStreamState, source: any CoachFactsSource) async -> AppleTurnResult {
        let offDevice = route == .privateCloud
        let instructions = Self.instructions()
        if CoachNumberValidator.validate(reply: text, sources: log.outputs + [instructions, question]).isValid {
            return .reply(text, offDevice: offDevice)
        }
        stream.text = ""
        let stricter = "Answer my last question again. Use only numbers that appear in the tool output, written the same way. Leave out every other number."
        if let retry = try? await streamReply(session, prompt: stricter, into: stream),
           CoachNumberValidator.validate(reply: retry, sources: log.outputs + [instructions, question]).isValid {
            return .reply(retry, offDevice: offDevice)
        }
        var facts: [String] = []
        for output in log.outputs where !facts.contains(output) { facts.append(output) }
        if facts.isEmpty { facts = [await source.todaySnapshot()] }
        return .factsOnly(facts.joined(separator: "\n\n"), offDevice: offDevice)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func onDevice(_ source: any CoachFactsSource) -> LanguageModelSession {
        if let s = onDeviceSession as? LanguageModelSession { return s }
        let instructions = Self.instructions()
        let s = AppleCoachSessionFactory.onDevice(instructions: instructions, source: source, log: log)
        onDeviceSession = s
        onDeviceChars = instructions.count
        return s
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func cloud(_ source: any CoachFactsSource) -> LanguageModelSession {
        if let s = cloudSession as? LanguageModelSession { return s }
        if #available(iOS 27.0, macOS 27.0, *) {
            let s = AppleCoachSessionFactory.privateCloud(instructions: Self.instructions(), source: source, log: log)
            cloudSession = s
            return s
        }
        // Unreachable: routing never picks Private Cloud Compute below 27.
        return onDevice(source)
    }

    /// Whether the on-device session is near its context limit: `tokenCount` on 26.4+, else the estimate.
    @available(iOS 26.0, macOS 26.0, *)
    private func needsCondense(question: String) async -> Bool {
        guard let session = onDeviceSession as? LanguageModelSession else { return false }
        let model = SystemLanguageModel.default
        var used = CoachTokenBudget.estimate(latinCharacters: onDeviceChars) + Self.toolOverheadTokens
        if #available(iOS 26.4, macOS 26.4, *), let counted = try? await model.tokenCount(for: session.transcript) {
            used = counted
        }
        return CoachTokenBudget.needsCondense(sessionTokens: used, promptTokens: CoachTokenBudget.estimate(question),
                                              contextSize: model.contextSize)
    }

    /// Summarise the conversation with the on-device model in a separate session, drop the old session, and
    /// carry the summary into the next prompt. Sentences with digits are removed: the summary may name topics,
    /// never numbers the next turn's facts do not carry.
    @available(iOS 26.0, macOS 26.0, *)
    private func condense(history: [ChatMessage]) async {
        let recent = history.suffix(8).map { m in
            (m.role == .user ? "Person: " : "Coach: ") + String(m.text.prefix(300))
        }.joined(separator: "\n")
        let summariser = LanguageModelSession(instructions: "Summarise a conversation between a person and a wellness coach in at most two short sentences. Name the topics only. Do not include any numbers.")
        let raw = (try? await summariser.respond(to: recent, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 120)).content) ?? ""
        carriedSummary = Self.withoutNumbers(raw)
        onDeviceSession = nil
        onDeviceChars = 0
        condensedNotice = true
    }

    /// Map either OS's error types onto `AppleCoachFailure`.
    @available(iOS 26.0, macOS 26.0, *)
    nonisolated static func failure(_ error: Error, route: AppleCoachRoute) -> AppleCoachFailure {
        if let e = error as? LanguageModelSession.ToolCallError { return failure(e.underlyingError, route: route) }
        if #available(iOS 27.0, macOS 27.0, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .contextSizeExceeded: return .contextTooLong
                case .rateLimited: return .rateLimited
                case .guardrailViolation: return .guardrail
                case .refusal: return .refusal
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .timeout: return .timeout
                default: return .other
                }
            }
            if let e = error as? LanguageModelSession.Error {
                return e == .concurrentRequests ? .busy : .other
            }
            if error is SystemLanguageModel.Error { return .modelUnavailable }
            if let e = error as? PrivateCloudComputeLanguageModel.Error {
                switch e {
                case .networkFailure: return .network
                case .quotaLimitReached: return .quota
                case .serviceUnavailable: return .serviceUnavailable
                @unknown default: return .serviceUnavailable
                }
            }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return .contextTooLong
            case .assetsUnavailable: return .modelUnavailable
            case .guardrailViolation: return .guardrail
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .rateLimited: return .rateLimited
            case .concurrentRequests: return .busy
            case .refusal: return .refusal
            default: return .other
            }
        }
        // An error the framework reports untyped (for example an unentitled Private Cloud Compute call).
        return route == .privateCloud ? .serviceUnavailable : .other
    }
    #endif

    /// Drop every sentence that contains a digit.
    nonisolated static func withoutNumbers(_ text: String) -> String {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s, !s.contains(where: \.isNumber) { sentences.append(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return sentences.joined(separator: " ")
    }
}
