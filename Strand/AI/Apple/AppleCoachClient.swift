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

    /// What the last turn did, for diagnostics and the verification report: where it ran, which tools the
    /// model called, and what the number check found.
    struct TurnReport: Equatable, Sendable {
        var route: AppleCoachRoute = .none
        var toolCalls: [String] = []
        var firstOffending: [String] = []
        var retried = false
        var retryOffending: [String] = []
        var factsOnly = false
        var failure: AppleCoachFailure?
        /// The framework's own description of the last error, for diagnostics only (never shown).
        var errorDetail: String?
        var condensed = false
    }
    private(set) var lastReport = TurnReport()

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

    /// Write today's brief (see `AppleCoachBrief`). Nil when neither model can serve it; the caller keeps
    /// the stored brief then.
    func brief(inputs: AppleCoachRoutingInputs, day: String, dataKey: String) async -> AppleCoachBrief? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await briefWithModel(inputs: inputs, day: day, dataKey: dataKey)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)

    /// Guided generation with no tools: the facts go in the prompt (the brief always needs them), the model
    /// picks metrics and writes sentences without numbers, and the number check runs on its prose. One
    /// retry, then the values-only brief.
    @available(iOS 26.0, macOS 26.0, *)
    private func briefWithModel(inputs start: AppleCoachRoutingInputs, day: String, dataKey: String) async -> AppleCoachBrief? {
        guard let source else { return nil }
        var inputs = start
        var route = AppleCoachRouting.route(inputs)
        let facts = await source.todaySnapshot() + "\n" + (await source.sleepPlan())
        let instructions = Self.instructions()
        let prompt = "Write today's brief from these facts. Pick the two or three metrics that matter most today. Do not write any numbers.\n\nFACTS:\n" + facts
        for _ in 0..<2 {
            guard route != .none else { return nil }
            let session: LanguageModelSession
            if route == .privateCloud, #available(iOS 27.0, macOS 27.0, *) {
                session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            } else {
                session = LanguageModelSession(model: .default, instructions: instructions)
            }
            let offDevice = route == .privateCloud
            func valid(_ d: CoachBriefDraft) -> Bool {
                let prose = ([d.headline] + d.points.map(\.sentence)).joined(separator: " ")
                return CoachNumberValidator.validate(reply: prose, sources: [facts, instructions]).isValid
            }
            do {
                var draft = try await session.respond(to: prompt, generating: CoachBriefDraft.self,
                                                      options: AppleCoachSessionFactory.factualOptions).content
                if !valid(draft) {
                    draft = try await session.respond(to: "Write it again with no numbers at all.", generating: CoachBriefDraft.self,
                                                      options: AppleCoachSessionFactory.factualOptions).content
                }
                guard valid(draft) else {
                    return AppleCoachBriefPolicy.factsOnly(day: day, dataKey: dataKey, metrics: [.charge, .rest, .sleepDebt],
                                                           offDevice: offDevice)
                }
                return AppleCoachBrief(day: day, dataKey: dataKey, headline: draft.headline,
                                       points: draft.points.map { .init(metric: $0.metric.metric.rawValue, sentence: $0.sentence) },
                                       offDevice: offDevice, factsOnly: false)
            } catch {
                let failure = Self.failure(error, route: route)
                guard case .retryOnPrivateCloud(let next) = AppleCoachRecovery.next(failure, route: route, inputs: inputs,
                                                                                   alreadyCondensed: true) else { return nil }
                inputs = next
                route = .privateCloud
            }
        }
        return nil
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func respondWithModel(question: String, history: [ChatMessage], inputs start: AppleCoachRoutingInputs,
                                  stream: CoachStreamState) async -> AppleTurnResult {
        guard let source else { return .failed(AppleCoachRecovery.message(.other)) }
        var inputs = start
        var route = AppleCoachRouting.route(inputs)
        var condensed = false
        lastReport = TurnReport()
        if route == .onDevice, await needsCondense(question: question) {
            await condense(history: history)
            condensed = true
            lastReport.condensed = true
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
            lastReport.route = route
            do {
                let text = try await streamReply(session, prompt: prompt, into: stream)
                if route == .onDevice { onDeviceChars += prompt.count + text.count + log.outputs.joined().count }
                carriedSummary = nil
                return await checked(text, question: question, session: session, route: route, stream: stream, source: source)
            } catch {
                let failure = Self.failure(error, route: route)
                lastReport.failure = failure
                lastReport.errorDetail = String(describing: error)
                lastReport.toolCalls = log.calls
                switch AppleCoachRecovery.next(failure, route: route, inputs: inputs, alreadyCondensed: condensed) {
                case .condenseAndRetry:
                    await condense(history: history)
                    condensed = true
                    lastReport.condensed = true
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
        lastReport.toolCalls = log.calls
        let first = CoachNumberValidator.validate(reply: text, sources: log.outputs + [instructions, question])
        lastReport.firstOffending = first.offending
        if first.isValid { return .reply(text, offDevice: offDevice) }
        stream.text = ""
        lastReport.retried = true
        let stricter = "Answer my last question again. Use only numbers that appear in the tool output, written the same way. Leave out every other number."
        if let retry = try? await streamReply(session, prompt: stricter, into: stream) {
            let second = CoachNumberValidator.validate(reply: retry, sources: log.outputs + [instructions, question])
            lastReport.retryOffending = second.offending
            lastReport.toolCalls = log.calls
            if second.isValid { return .reply(retry, offDevice: offDevice) }
        }
        lastReport.factsOnly = true
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
