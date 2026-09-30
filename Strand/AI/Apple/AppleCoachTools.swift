#if canImport(FoundationModels)
import Foundation
import FoundationModels

// AppleCoachTools.swift — the Coach's five tools and its session. Each tool is a thin read of the app's own
// resolvers (`CoachFactsSource`), returns short text with units, and logs what it returned so the turn's
// reply is validated against exactly what the model saw. Behind `canImport(FoundationModels)` and iOS/macOS 26.

/// Every tool output of the current turn, for the number validator. Tools may run concurrently.
final class CoachToolLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _outputs: [String] = []
    private var _calls: [String] = []
    private var _includeCheckIns = false

    /// Start a turn. `includeCheckIns` is decided from the question by the app, never by the model.
    func begin(includeCheckIns: Bool) {
        lock.lock(); defer { lock.unlock() }
        _outputs = []; _calls = []; _includeCheckIns = includeCheckIns
    }

    func record(_ tool: String, _ output: String) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(tool); _outputs.append(output)
    }

    var outputs: [String] { lock.lock(); defer { lock.unlock() }; return _outputs }
    var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
    var includeCheckIns: Bool { lock.lock(); defer { lock.unlock() }; return _includeCheckIns }
}

/// The metric whitelist as the model sees it: a closed enum, never a free string.
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum CoachMetricChoice {
    case charge, rest, effort, hrv, restingHeartRate, sleepDuration, sleepDebt, stress, energy, steps

    var metric: CoachMetric {
        switch self {
        case .charge: return .charge
        case .rest: return .rest
        case .effort: return .effort
        case .hrv: return .hrv
        case .restingHeartRate: return .restingHeartRate
        case .sleepDuration: return .sleepDuration
        case .sleepDebt: return .sleepDebt
        case .stress: return .stress
        case .energy: return .energy
        case .steps: return .steps
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CoachTodaySnapshotTool: Tool {
    let name = "todaySnapshot"
    let description = "Today's Charge, Rest, Effort and its target, Energy, stress, HRV readiness, sleep debt and body-signal heads-up."
    let source: any CoachFactsSource
    let log: CoachToolLog

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let out = await source.todaySnapshot()
        log.record(name, out)
        return out
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CoachMetricTrendTool: Tool {
    let name = "metricTrend"
    let description = "Average, lowest, highest and direction of one metric over the last 7, 30 or 90 days."
    let source: any CoachFactsSource
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "Which metric")
        var metric: CoachMetricChoice
        @Guide(description: "Days: 7, 30 or 90", .range(7...90))
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let out = await source.metricTrend(arguments.metric.metric, days: arguments.days)
        log.record(name, out)
        return out
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CoachSleepPlanTool: Tool {
    let name = "sleepPlan"
    let description = "Tonight's planned bedtime, wake time and sleep need, whether it is reachable, and any jet-lag step for today."
    let source: any CoachFactsSource
    let log: CoachToolLog

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let out = await source.sleepPlan()
        log.record(name, out)
        return out
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CoachExplainMetricTool: Tool {
    let name = "explainMetric"
    let description = "How the app computes a metric, in the app's own words."
    let source: any CoachFactsSource
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "Which metric")
        var metric: CoachMetricChoice
    }

    func call(arguments: Arguments) async throws -> String {
        let out = await source.explain(arguments.metric.metric)
        log.record(name, out)
        return out
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CoachRecentNotesTool: Tool {
    let name = "recentNotes"
    let description = "The person's journal tags and short notes from recent days, as quoted data."
    let source: any CoachFactsSource
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "Days to look back", .range(1...14))
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let out = await source.recentNotes(days: arguments.days, includeCheckIns: log.includeCheckIns)
        log.record(name, out)
        return out
    }
}

@available(iOS 26.0, macOS 26.0, *)
enum AppleCoachSessionFactory {

    static func tools(source: any CoachFactsSource, log: CoachToolLog) -> [any Tool] {
        [CoachTodaySnapshotTool(source: source, log: log),
         CoachMetricTrendTool(source: source, log: log),
         CoachSleepPlanTool(source: source, log: log),
         CoachExplainMetricTool(source: source, log: log),
         CoachRecentNotesTool(source: source, log: log)]
    }

    /// The on-device session (the general-purpose system model).
    static func onDevice(instructions: String, source: any CoachFactsSource, log: CoachToolLog) -> LanguageModelSession {
        LanguageModelSession(model: .default, tools: tools(source: source, log: log), instructions: instructions)
    }

    /// The Private Cloud Compute session: the same tools and instructions on Apple's servers (27+).
    @available(iOS 27.0, macOS 27.0, *)
    static func privateCloud(instructions: String, source: any CoachFactsSource, log: CoachToolLog) -> LanguageModelSession {
        LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools(source: source, log: log),
                             instructions: instructions)
    }

    /// Factual turns: low temperature. The reply budget guards against runaway output only.
    static var factualOptions: GenerationOptions {
        GenerationOptions(temperature: 0.2, maximumResponseTokens: 400)
    }
}
#endif
