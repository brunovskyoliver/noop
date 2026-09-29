#if os(iOS)
import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Check-in storage

/// The monthly Mind check-in, stored like MoodStore: rows in the metric-series table under a dedicated
/// source id, so no import can overwrite or clear them and no schema change is needed. One row per form per
/// local day (`mind_pss4`, `mind_gad2`, `mind_phq2`, holding the form's total); a second check-in on the
/// same day overwrites the first.
enum BroopMindCheckInStore {
    static let deviceId = "noop-mind"
    enum WriteError: Error { case unavailable, invalidTotals }

}

extension Repository {
    /// Every stored total for one form, oldest first.
    func mindCheckInSeries(_ form: MindCheckIn.Form) async -> [(day: String, value: Double)] {
        await series(key: form.seriesKey, source: BroopMindCheckInStore.deviceId)
    }

    /// Save one completed check-in (all three totals) for `day`.
    func saveMindCheckIn(day: String, totals: [MindCheckIn.Form: Int]) async throws {
        guard MindCheckIn.Form.allCases.allSatisfy({ form in
            totals[form].map { (0...form.maxScore).contains($0) } ?? false
        }) else { throw BroopMindCheckInStore.WriteError.invalidTotals }
        guard let store = await storeHandle() else { throw BroopMindCheckInStore.WriteError.unavailable }
        let rows = totals.map { MetricPoint(day: day, key: $0.key.seriesKey, value: Double($0.value)) }
        _ = try await store.upsertMetricSeries(rows, deviceId: BroopMindCheckInStore.deviceId)
        mindCheckInRevision += 1
    }

    /// Remove the check-in stored for `day`.
    func deleteMindCheckIn(day: String) async throws {
        guard let store = await storeHandle() else { throw BroopMindCheckInStore.WriteError.unavailable }
        try await store.deleteMetricSeriesPoints(deviceId: BroopMindCheckInStore.deviceId,
                                                day: day, keys: MindCheckIn.Form.allCases.map(\.seriesKey))
        mindCheckInRevision += 1
    }
}

// MARK: - Screen data

/// Everything the Mind screen and the Health-tab card show, resolved once. Resilience and Cumulative Stress
/// come from their engines over `mindDays` (stress summaries from `Repository.stressDaySummaries`, Rest
/// from the shared `restScore` resolver and Charge from the day rows, the same sources Home reads),
/// so the card and the screen can never disagree.
struct BroopMindData {
    struct CheckIn: Identifiable, Equatable {
        let day: String
        let pss4: Int?
        let gad2: Int?
        let phq2: Int?
        var id: String { day }
    }

    struct Link: Equatable, Identifiable {
        var id: String { form.rawValue + signal }
        let form: MindCheckIn.Form
        let signal: String     // "Charge" or "HRV"
        let r: Double
        let n: Int
    }

    var resilience: ResilienceEngine.Result?
    var resilienceHistory: [(day: String, score: Double)] = []
    var cumulative: CumulativeStressEngine.Result?
    var cumulativeHistory: [(day: String, score: Double)] = []
    /// Days in the last 14 / 31 that already carry stress data (cold-start progress).
    var resilienceStressDays = 0
    var cumulativeStressDays = 0
    var checkIns: [CheckIn] = []
    var links: [Link] = []
    var checkInDue = true
    var loaded = false

    var latestCheckIn: CheckIn? { checkIns.last }

    static let historySpan = 90

    @MainActor
    static func load(repo: Repository) async -> BroopMindData {
        let today = Repository.dayString(Date())
        async let summariesA = repo.stressDaySummaries(days: 120)
        async let pssA = repo.mindCheckInSeries(.pss4)
        async let gadA = repo.mindCheckInSeries(.gad2)
        async let phqA = repo.mindCheckInSeries(.phq2)
        let summaries = await summariesA
        let pss = await pssA, gad = await gadA, phq = await phqA
        let dailies = repo.days
        let rest = dailies.compactMap { day in repo.restScore(for: day).map { (day: day.day, value: $0) } }

        return await Task.detached(priority: .userInitiated) {
            build(today: today, summaries: summaries, rest: rest, dailies: dailies,
                  pss: pss, gad: gad, phq: phq)
        }.value
    }

    nonisolated static func mindDays(summaries: [StressDaySummary], rest: [(day: String, value: Double)],
                                     dailies: [DailyMetric]) -> [MindDay] {
        var byDay: [String: MindDay] = [:]
        func entry(_ day: String) -> MindDay { byDay[day] ?? MindDay(day: day) }
        for s in summaries {
            var d = entry(s.day)
            d.highStressMin = Double(s.highMin)
            d.lowStressMin = Double(s.lowMin)
            d.scoredMin = Double(s.scoredMin)
            d.sleepStressPct = s.sleepStressPct
            byDay[s.day] = d
        }
        for p in rest {
            var d = entry(p.day); d.rest = p.value; byDay[p.day] = d
        }
        for m in dailies {
            guard let charge = m.recovery else { continue }
            var d = entry(m.day); d.charge = charge; byDay[m.day] = d
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    nonisolated static func build(today: String, summaries: [StressDaySummary],
                                  rest: [(day: String, value: Double)], dailies: [DailyMetric],
                                  pss: [(day: String, value: Double)], gad: [(day: String, value: Double)],
                                  phq: [(day: String, value: Double)]) -> BroopMindData {
        var d = BroopMindData()
        let days = mindDays(summaries: summaries, rest: rest, dailies: dailies)
        d.resilience = ResilienceEngine.compute(days: days, asOf: today)
        d.resilienceHistory = ResilienceEngine.history(days: days, asOf: today, span: historySpan)
        d.cumulative = CumulativeStressEngine.compute(days: days, asOf: today)
        d.cumulativeHistory = CumulativeStressEngine.history(days: days, asOf: today, span: historySpan)
        d.resilienceStressDays = MindEngine.window(days, asOf: today, length: ResilienceEngine.windowDays)
            .filter { $0.hasDaytimeStress }.count
        d.cumulativeStressDays = MindEngine.window(days, asOf: today, length: CumulativeStressEngine.windowDays)
            .filter { CumulativeStressEngine.dayLoad($0) != nil }.count

        func valid(_ series: [(day: String, value: Double)], form: MindCheckIn.Form) -> [(day: String, value: Double)] {
            series.filter { $0.day <= today && MindEngine.epoch($0.day) != nil
                && $0.value.isFinite && $0.value.rounded() == $0.value
                && (0...Double(form.maxScore)).contains($0.value) }
        }
        let pss = valid(pss, form: .pss4), gad = valid(gad, form: .gad2), phq = valid(phq, form: .phq2)
        let pssBy = Dictionary(pss.map { ($0.day, Int($0.value.rounded())) }, uniquingKeysWith: { _, b in b })
        let gadBy = Dictionary(gad.map { ($0.day, Int($0.value.rounded())) }, uniquingKeysWith: { _, b in b })
        let phqBy = Dictionary(phq.map { ($0.day, Int($0.value.rounded())) }, uniquingKeysWith: { _, b in b })
        let checkInDays = Set(pssBy.keys).union(gadBy.keys).union(phqBy.keys).sorted()
        d.checkIns = checkInDays.map { CheckIn(day: $0, pss4: pssBy[$0], gad2: gadBy[$0], phq2: phqBy[$0]) }
        d.checkInDue = MindCheckIn.isDue(lastCheckInDay: checkInDays.last, today: today)

        // Charge and HRV over each form's recall window, strongest link first.
        let charge = dailies.compactMap { m in m.recovery.map { (day: m.day, value: $0) } }
        let hrv = dailies.compactMap { m in m.avgHrv.map { (day: m.day, value: $0) } }
        for (form, series) in [(MindCheckIn.Form.pss4, pss), (.gad2, gad), (.phq2, phq)] {
            for (name, signal) in [("Charge", charge), ("HRV", hrv)] {
                if let c = MindCheckIn.correlate(scores: series, signal: signal,
                                                  windowDays: MindCheckIn.recallDays(form)) {
                    d.links.append(Link(form: form, signal: name, r: c.r, n: c.n))
                }
            }
        }
        d.links.sort { abs($0.r) > abs($1.r) }
        d.loaded = true
        return d
    }
}
#endif
