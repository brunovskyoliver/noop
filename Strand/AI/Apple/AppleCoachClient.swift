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

    /// Follow-up chips for the reply just shown (see `CoachFollowUps`). On-device only: chips are not worth a
    /// request to Apple's servers. Nil when the on-device model can't serve them or the output is rejected;
    /// the caller shows the fixed chips then.
    func followUps(question: String, reply: String, inputs: AppleCoachRoutingInputs) async -> [String]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), inputs.onDevice == .available, inputs.onDeviceSupportsLocale {
            var instructions = CoachFollowUps.instructions
            if let language = CoachInstructions.languageLine(AppLanguage.activeLocale) { instructions += "\n\n" + language }
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let draft = try? await session.respond(to: CoachFollowUps.prompt(question: question, reply: reply),
                                                   generating: CoachFollowUpDraft.self,
                                                   options: GenerationOptions(temperature: 0.6, maximumResponseTokens: 120)).content
            return draft.flatMap { CoachFollowUps.clean($0.questions, asked: question) }
        }
        #endif
        return nil
    }

    /// This evening's review (see `AppleCoachEveningPolicy`). Nil when neither model can serve it.
    func evening(inputs: AppleCoachRoutingInputs, day: String, dataKey: String) async -> AppleCoachBrief? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await eveningWithModel(inputs: inputs, day: day, dataKey: dataKey)
        }
        #endif
        return nil
    }

    /// Journal proposals from what the person said; nil when the on-device model can't answer.
    func journal(transcript: String, choices: [CoachJournalParse.Choice], inputs: AppleCoachRoutingInputs) async -> [CoachJournalProposal]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), inputs.onDevice == .available, inputs.onDeviceSupportsLocale, !choices.isEmpty {
            return await journalWithModel(transcript: transcript, choices: choices)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)

    /// How a guided generation ended (see `guided`).
    private enum GuidedOutcome<Draft> {
        case draft(Draft, offDevice: Bool)
        /// The prose failed the number check twice, or a guardrail stopped it: show the values alone.
        case factsOnly(offDevice: Bool)
        case unavailable
    }

    /// Guided generation with no tools: the facts go in the prompt, the model writes a draft without
    /// numbers, and the number check runs on its prose. One retry, then values only. Errors hand over to
    /// Apple's servers once when `AppleCoachRecovery` allows it.
    @available(iOS 26.0, macOS 26.0, *)
    private func guided<Draft: Generable>(inputs start: AppleCoachRoutingInputs, facts: String, prompt: String,
                                          generating: Draft.Type, prose: (Draft) -> String) async -> GuidedOutcome<Draft> {
        var inputs = start
        var route = AppleCoachRouting.route(inputs)
        let instructions = Self.instructions()
        let fullPrompt = prompt + "\n\nFACTS:\n" + facts
        for _ in 0..<2 {
            guard route != .none else { return .unavailable }
            let session: LanguageModelSession
            if route == .privateCloud, #available(iOS 27.0, macOS 27.0, *) {
                session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            } else {
                session = LanguageModelSession(model: .default, instructions: instructions)
            }
            let offDevice = route == .privateCloud
            func valid(_ d: Draft) -> Bool {
                CoachNumberValidator.validate(reply: prose(d), sources: [facts, instructions]).isValid
            }
            do {
                var draft = try await session.respond(to: fullPrompt, generating: Draft.self,
                                                      options: AppleCoachSessionFactory.factualOptions).content
                if !valid(draft) {
                    draft = try await session.respond(to: "Write it again with no numbers at all.", generating: Draft.self,
                                                      options: AppleCoachSessionFactory.factualOptions).content
                }
                return valid(draft) ? .draft(draft, offDevice: offDevice) : .factsOnly(offDevice: offDevice)
            } catch {
                #if DEBUG
                print("COACH_GUIDED_ERROR \(error)")
                #endif
                let failure = Self.failure(error, route: route)
                // A guardrail or refusal on the person's own facts still leaves the values worth showing.
                if failure == .guardrail || failure == .refusal { return .factsOnly(offDevice: offDevice) }
                guard case .retryOnPrivateCloud(let next) = AppleCoachRecovery.next(failure, route: route, inputs: inputs,
                                                                                   alreadyCondensed: true) else { return .unavailable }
                inputs = next
                route = .privateCloud
            }
        }
        return .unavailable
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func briefWithModel(inputs: AppleCoachRoutingInputs, day: String, dataKey: String) async -> AppleCoachBrief? {
        guard let source else { return nil }
        let facts = await source.todaySnapshot() + "\n" + (await source.sleepPlan())
        let prompt = "Write today's brief from these facts. Pick the two or three metrics that matter most today, starting with the one furthest below its usual level or target. For each, write one concrete thing to do today (training, recovery or bedtime). Do not write any numbers."
        switch await guided(inputs: inputs, facts: facts, prompt: prompt, generating: CoachBriefDraft.self,
                            prose: { ([$0.headline] + $0.points.map(\.sentence)).joined(separator: " ") }) {
        case .draft(let d, let offDevice):
            return AppleCoachBrief(day: day, dataKey: dataKey, headline: d.headline,
                                   points: d.points.map { .init(metric: $0.metric.metric.rawValue, sentence: $0.sentence) },
                                   offDevice: offDevice, factsOnly: false)
        case .factsOnly(let offDevice):
            return AppleCoachBriefPolicy.factsOnly(day: day, dataKey: dataKey, metrics: [.charge, .rest, .sleepDebt],
                                                   offDevice: offDevice)
        case .unavailable:
            return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func eveningWithModel(inputs: AppleCoachRoutingInputs, day: String, dataKey: String) async -> AppleCoachBrief? {
        guard let source else { return nil }
        let facts = [await source.todaySnapshot(), await source.sleepPlan(),
                     await source.recentNotes(days: 1, includeCheckIns: false)].joined(separator: "\n")
        switch await guided(inputs: inputs, facts: facts, prompt: AppleCoachEveningPolicy.prompt, generating: CoachEveningDraft.self,
                            prose: { ([$0.headline, $0.tonight] + $0.points.map(\.sentence)).joined(separator: " ") }) {
        case .draft(let d, let offDevice):
            return AppleCoachBrief(day: day, dataKey: dataKey, headline: d.headline,
                                   points: d.points.map { .init(metric: $0.metric.metric.rawValue, sentence: $0.sentence) },
                                   offDevice: offDevice, factsOnly: false, tonight: d.tonight)
        case .factsOnly(let offDevice):
            return AppleCoachBriefPolicy.factsOnly(day: day, dataKey: dataKey, metrics: AppleCoachEveningPolicy.factsOnlyMetrics,
                                                   offDevice: offDevice, headline: String(localized: "Today at a glance"))
        case .unavailable:
            return nil
        }
    }

    /// Journal by voice (see `CoachJournalParse`). On-device only: it is the person's own words about their
    /// day. Throws nothing; nil when the model can't answer.
    @available(iOS 26.0, macOS 26.0, *)
    private func journalWithModel(transcript: String, choices: [CoachJournalParse.Choice]) async -> [CoachJournalProposal]? {
        guard let schema = try? CoachJournalParse.schema(choices: choices) else { return nil }
        var instructions = CoachJournalParse.instructions
        if let language = CoachInstructions.languageLine(AppLanguage.activeLocale) { instructions += "\n\n" + language }
        // Sorting the person's own words into their journal is a transformation task: the default guardrails
        // refused ordinary days ("no alcohol today", "went to bed early") as sensitive.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let content = try await session.respond(to: CoachJournalParse.prompt(transcript: transcript, choices: choices),
                                                    schema: schema,
                                                    options: GenerationOptions(temperature: 0, maximumResponseTokens: 600)).content
            return CoachJournalParse.proposals(CoachJournalParse.rawEntries(content), choices: choices, transcript: transcript)
        } catch {
            #if DEBUG
            print("COACH_JOURNAL_ERROR \(Self.failure(error, route: .onDevice)) \(error)")
            #endif
            let failure = Self.failure(error, route: .onDevice)
            guard failure == .guardrail || failure == .refusal else { return nil }
            // The permissive guardrails apply to plain-text answers only: ask again for lines, checked the same way.
            let plain = LanguageModelSession(model: model, instructions: instructions)
            let prompt = CoachJournalParse.prompt(transcript: transcript, choices: choices) + "\n\n" + CoachJournalParse.plainTextFormat
            let text: String
            do {
                text = try await plain.respond(to: prompt, options: GenerationOptions(temperature: 0, maximumResponseTokens: 600)).content
            } catch {
                #if DEBUG
                print("COACH_JOURNAL_PLAIN_ERROR \(error)")
                #endif
                return nil
            }
            #if DEBUG
            print("COACH_JOURNAL_PLAIN \(text.replacingOccurrences(of: "\n", with: " / "))")
            #endif
            return CoachJournalParse.proposals(CoachJournalParse.parseLines(text), choices: choices, transcript: transcript)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func respondWithModel(question: String, history: [ChatMessage], inputs start: AppleCoachRoutingInputs,
                                  stream: CoachStreamState) async -> AppleTurnResult {
        guard let source else { return .failed(AppleCoachRecovery.message(.other)) }
        var inputs = start
        var route = AppleCoachRouting.route(inputs)
        var condensed = false
        var retriedSame = false
        lastReport = TurnReport()
        if route == .onDevice, await needsCondense(question: question) {
            await condense(history: history)
            condensed = true
            lastReport.condensed = true
        }
        // First try, at most one condense-and-retry or tool-call retry, at most one hand-over to Apple's servers.
        for _ in 0..<4 {
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
                switch AppleCoachRecovery.next(failure, route: route, inputs: inputs, alreadyCondensed: condensed,
                                               alreadyRetried: retriedSame) {
                case .retrySame:
                    retriedSame = true
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
        let stricter = "Call the tools again for the current numbers, then answer my last question again in full sentences, as a coach would. Use only numbers that appear in that tool output, written the same way, and leave out every other number."
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
        var size = model.contextSize
        #if DEBUG
        // Verification only: `--coach-context <tokens>` shrinks the budget so a short chat condenses.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--coach-context"), i + 1 < args.count, let n = Int(args[i + 1]) { size = n }
        #endif
        return CoachTokenBudget.needsCondense(sessionTokens: used, promptTokens: CoachTokenBudget.estimate(question),
                                              contextSize: size)
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
        // The app's tools never throw, so a tool-call error is the model's arguments failing to decode.
        if error is LanguageModelSession.ToolCallError { return .badToolCall }
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
