#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// The Journal Insights data: the same load `InsightsView.load()` runs (journal yes/no days per behaviour,
/// the four outcome series with the strap-only DailyMetric fallback, activity costs, metric relationships),
/// ranked with the same `BehaviorInsights` / `CorrelationEngine` / `ActivityCostEngine` calls, so every
/// number here equals the Insights screen's.
@MainActor
final class BroopInsightsImpactModel: ObservableObject {
    typealias Outcome = InsightsRules.Outcome

    struct Relationship: Identifiable {
        let id: String
        let title: String
        let blurb: String
        let corr: Correlation
    }

    @Published private(set) var loaded = false
    @Published private(set) var ranked: [BehaviorEffect] = []
    @Published private(set) var relationships: [Relationship] = []
    @Published private(set) var activityCosts: [ActivityCost] = []
    @Published private(set) var behaviours: [String: Set<String>] = [:]
    @Published private(set) var importedQuestions: [String] = []
    @Published private(set) var outcomeByKey: [String: [String: Double]] = [:]
    private var controls: [String: Set<String>] = [:]
    private var seriesByKey: [String: [(day: String, value: Double)]] = [:]
    private(set) var outcome: Outcome = .recovery

    private let outcomeKeys = ["recovery", "hrv", "sleep_performance", "rhr"]

    func load(repo: Repository) async {
        let entries = await repo.journalEntries()
        var byBehaviour: [String: Set<String>] = [:]
        var controlsByBehaviour: [String: Set<String>] = [:]
        for e in entries {
            if e.answeredYes { byBehaviour[e.question, default: []].insert(e.day) }
            else { controlsByBehaviour[e.question, default: []].insert(e.day) }
        }
        let imported = await repo.importedJournalEntries()
        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []

        let mergedDays = repo.days
        var byKey: [String: [String: Double]] = [:]
        var seriesMap: [String: [(day: String, value: Double)]] = [:]
        for key in outcomeKeys {
            let s = await repo.series(key: key, source: "my-whoop")
            var dict: [String: Double] = [:]
            for row in s { dict[row.day] = row.value }
            for d in mergedDays where dict[d.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: d) { dict[d.day] = v }
            }
            byKey[key] = dict
            seriesMap[key] = dict.sorted { $0.key < $1.key }.map { (day: $0.key, value: $0.value) }
        }
        let costs = InsightsRules.computeActivityCosts(workouts: await repo.workoutRows(), days: mergedDays)

        behaviours = byBehaviour
        controls = controlsByBehaviour
        importedQuestions = importedQs
        outcomeByKey = byKey
        seriesByKey = seriesMap
        activityCosts = costs
        relationships = computeRelationships()
        rank(outcome)
        loaded = true
    }

    func rank(_ o: Outcome) {
        outcome = o
        ranked = BehaviorInsights.rank(behaviors: behaviours, controls: controls,
                                       outcomeByDay: outcomeByKey[o.key] ?? [:], outcome: o.outcomeName)
    }

    /// Same mapping as `InsightsRules.dailyOutcome`: sleep_performance has no daily column.
    private static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "recovery": return d.recovery
        case "hrv": return d.avgHrv
        case "rhr": return d.restingHr.map(Double.init)
        default: return nil
        }
    }

    private func computeRelationships() -> [Relationship] {
        func series(_ key: String) -> [(day: String, value: Double)] { seriesByKey[key] ?? [] }
        var out: [Relationship] = []
        if let c = CorrelationEngine.pearson(CorrelationEngine.alignByDay(series("sleep_performance"), series("recovery"))) {
            out.append(.init(id: "sleep-rec", title: String(localized: "Rest ↔ Charge"),
                             blurb: String(localized: "How closely a good night tracks next-morning charge."), corr: c))
        }
        if let c = CorrelationEngine.pearson(CorrelationEngine.alignByDay(series("hrv"), series("recovery"))) {
            out.append(.init(id: "hrv-rec", title: String(localized: "HRV ↔ Charge"),
                             blurb: String(localized: "Heart-rate variability as the engine behind your charge score."), corr: c))
        }
        if let c = CorrelationEngine.pearson(CorrelationEngine.alignByDay(series("rhr"), series("recovery"))) {
            out.append(.init(id: "rhr-rec", title: String(localized: "Resting HR ↔ Charge"),
                             blurb: String(localized: "A lower resting heart rate usually means a higher charge."), corr: c))
        }
        if let c = CorrelationEngine.lagged(x: series("recovery"), y: series("recovery"), lagDays: 1) {
            out.append(.init(id: "rec-lag", title: String(localized: "Charge → Next-day charge"),
                             blurb: String(localized: "How much one day's charge carries into the next."), corr: c))
        }
        return out
    }

    // MARK: Personal experiment (same arithmetic as InsightsView's n-of-1 card)

    struct Experiment {
        let behavior: String
        let outcome: Outcome
        let startDay: String
        let durationDays: Int
        let daysElapsed: Int
        let baselineMean: Double?
        let baselineCount: Int
        let interventionMean: Double?
        let interventionCount: Int
        let loggedToday: Bool
        let compliance: Double
        let confidenceLabel: String
        let confidenceColor: Color

        var progress: Double { min(1, Double(daysElapsed) / Double(max(durationDays, 1))) }
        var complete: Bool { daysElapsed >= durationDays }
        var delta: Double? {
            guard let interventionMean, let baselineMean else { return nil }
            return interventionMean - baselineMean
        }
    }

    /// Behaviours with history, minus hidden ones (InsightsView.experimentCandidates).
    func experimentCandidates(saved: String, hidden: [String]) -> [String] {
        let s = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        let hiddenSet = Set(hidden.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let raw = behaviours.keys.sorted() + importedQuestions + (s.isEmpty ? [] : [s])
        var seen = Set<String>()
        var out: [String] = []
        for q in raw {
            let t = q.trimmingCharacters(in: .whitespaces)
            let key = t.lowercased()
            if !t.isEmpty, !hiddenSet.contains(key), seen.insert(key).inserted { out.append(t) }
        }
        return out
    }

    func experiment(behavior: String?, outcomeRaw: String, startedDay: String,
                    durationDays: Int, baselineDays: Int) -> Experiment? {
        guard !startedDay.isEmpty, let outcome = Outcome(rawValue: outcomeRaw), let behavior else { return nil }
        let today = Repository.localDayKey(Date())
        let duration = max(1, durationDays)
        let outcomeDays = outcomeByKey[outcome.key] ?? [:]
        let loggedDays = behaviours[behavior] ?? []
        let baseline = outcomeDays.keys.filter { $0 < startedDay && !loggedDays.contains($0) }.sorted()
            .suffix(max(1, baselineDays))
        let window = outcomeDays.keys.filter { $0 >= startedDay && $0 <= today }.sorted().prefix(duration)
        let intervention = window.filter { loggedDays.contains($0) }
        let baselineValues = baseline.compactMap { outcomeDays[$0] }
        let interventionValues = intervention.compactMap { outcomeDays[$0] }
        let elapsed = max(1, min(duration, Self.dayDistance(from: startedDay, to: today) + 1))
        let compliance = Double(intervention.count) / Double(max(elapsed, 1))
        let paired = min(baselineValues.count, interventionValues.count)
        let label: String
        let color: Color
        if paired >= 10, compliance >= 0.65 {
            label = String(localized: "STRONGER SIGNAL"); color = BroopInsightsPalette.helps
        } else if paired >= 5 {
            label = String(localized: "EARLY SIGNAL"); color = BroopPalette.rest
        } else {
            label = String(localized: "LOW SIGNAL"); color = BroopInsightsPalette.hurts
        }
        return Experiment(behavior: behavior, outcome: outcome, startDay: startedDay, durationDays: duration,
                          daysElapsed: elapsed, baselineMean: Self.mean(baselineValues),
                          baselineCount: baselineValues.count, interventionMean: Self.mean(interventionValues),
                          interventionCount: interventionValues.count, loggedToday: loggedDays.contains(today),
                          compliance: compliance * 100, confidenceLabel: label, confidenceColor: color)
    }

    private static func mean(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private static func dayDistance(from start: String, to end: String) -> Int {
        func date(_ key: String) -> Date? {
            let p = key.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            var c = DateComponents()
            c.calendar = Calendar(identifier: .gregorian)
            c.year = p[0]; c.month = p[1]; c.day = p[2]
            return c.date
        }
        guard let s = date(start), let e = date(end) else { return 0 }
        return Calendar.current.dateComponents([.day], from: s, to: e).day ?? 0
    }

    static func format(_ v: Double, as outcome: Outcome) -> String {
        switch outcome {
        case .recovery, .sleep: return "\(Int(v.rounded()))%"
        case .hrv: return "\(Int(v.rounded())) ms"
        case .rhr: return "\(Int(v.rounded())) bpm"
        }
    }

    static func formatDelta(_ delta: Double?, outcome: Outcome, sign: Bool = true) -> String {
        guard let delta else { return "—" }
        let prefix = sign ? (delta > 0 ? "+" : (delta < 0 ? "−" : "")) : ""
        let a = Int(abs(delta).rounded())
        switch outcome {
        case .recovery, .sleep: return "\(prefix)\(a)%"
        case .hrv: return "\(prefix)\(a) ms"
        case .rhr: return "\(prefix)\(a) bpm"
        }
    }
}
#endif
