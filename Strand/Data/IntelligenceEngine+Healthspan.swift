import Foundation
import WhoopStore
import StrandAnalytics

// IntelligenceEngine+Healthspan.swift — the weekly Healthspan v2 store pass and its one-shot history
// backfill. Both go through `Repository.healthspan` / `VitalityEngine.healthspan`, the resolver the screens
// also call, and write the computed source's `body_age` (Broop Age), `pace_of_aging` and the derived
// `vitality` under the update SUNDAY.
//
// iOS-only fork change: the Android pass is intentionally not updated.
extension IntelligenceEngine {

    /// The three stored Healthspan keys.
    static let healthspanKeys = ["body_age", "pace_of_aging", "vitality"]

    /// UserDefaults flag guarding the one-shot v2 backfill. Set once the pass completes.
    static let healthspanV2BackfillFlagKey = "intelligence.healthspanV2.backfill.done"

    nonisolated static func healthspanPoints(_ h: VitalityEngine.Healthspan) -> [MetricPoint] {
        [MetricPoint(day: h.asOf, key: "body_age", value: h.current.bodyAge),
         MetricPoint(day: h.asOf, key: "pace_of_aging", value: h.paceOfAging),
         MetricPoint(day: h.asOf, key: "vitality", value: h.current.vitality)]
    }

    /// The weekly pass: recompute the latest Sunday on or before `newestDay` and upsert it. Re-running
    /// during the week rewrites the same Sunday row from the same (now complete) Sunday window, so the
    /// value settles on Monday and then holds until the next Sunday. Writes nothing while the recovery
    /// gate fails, so a stopped strap leaves the last value in place, as WHOOP does.
    static func writeWeeklyHealthspan(repo: Repository, store: WhoopStore, computedId: String,
                                      profileAge: Int, sex: String, newestDay: String,
                                      fresh: [DailyMetric]) async {
        let sunday = VitalityEngine.sundayKey(onOrBefore: newestDay) ?? newestDay
        guard let h = await repo.healthspan(asOf: sunday, profileAge: profileAge, sex: sex,
                                            fresh: fresh) else { return }
        _ = try? await store.upsertMetricSeries(Self.healthspanPoints(h), deviceId: computedId)
    }

    /// One-shot v2 backfill. Deletes every stored v1 `body_age` / `vitality` / `pace_of_aging` row (v1
    /// keyed them to Saturdays, under the computed sources and, for the old demo seed, the canonical
    /// import source), then recomputes every Sunday of the available history with v2, so the trend is
    /// continuous and no v1 value can show. The read happens once for the whole history and the compute
    /// runs off the main actor.
    static func runHealthspanV2BackfillIfNeeded(repo: Repository, profileAge: Int, sex: String,
                                                log: ((String) -> Void)? = nil) async {
        let flagKey = Self.healthspanV2BackfillFlagKey + "." + repo.deviceId
        guard !UserDefaults.standard.bool(forKey: flagKey), profileAge > 0,
              let computedId = repo.computedReadIds.first, !repo.days.isEmpty else { return }
        guard let store = await repo.storeHandle() else { return }   // retry next launch
        let today = Repository.dayString(Date())
        let currentSunday = Repository.healthspanUpdateDay(today: today)
        if profileAge > 0, let first = repo.days.first?.day, first <= currentSunday {
            let history = await repo.healthspanHistory(from: first, to: currentSunday)
            let sundays = VitalityEngine.sundays(from: first, to: currentSunday)
            let ages = sundays.map { Repository.healthspanAge(profileAge: profileAge, asOf: $0,
                                                              currentUpdateDay: currentSunday) }
            let points: [MetricPoint] = await Task.detached(priority: .utility) {
                Self.backfillPoints(history: history, sundays: sundays, ages: ages, sex: sex)
            }.value
            do {
                try await store.replaceDerivedMetricSeries(points, deviceId: computedId,
                    replacingSourceIds: repo.computedReadIds + repo.importedReadIds,
                    keys: Self.healthspanKeys)
            } catch {
                log?("Healthspan history replacement failed; will retry: \(error.localizedDescription)")
                return
            }
            let latest = points.suffix(Self.healthspanKeys.count)
                .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: " ")
            let line = "Healthspan v2 backfill: \(points.count / Self.healthspanKeys.count) of \(sundays.count) Sunday(s) passed the recovery gate; latest \(points.last?.day ?? "-"): \(latest)"
            NSLog("%@", line)
            log?(line)
        }
        UserDefaults.standard.set(true, forKey: flagKey)
        await repo.refresh()
    }

    /// Pure: every gated Sunday's points. Each Sunday only sees the days up to it (a 365-day slice is
    /// passed so lean-mass carry-over still works), so a backfilled week equals what the weekly pass would
    /// have written on that Sunday.
    nonisolated static func backfillPoints(history: Repository.HealthspanHistory, sundays: [String],
                                           ages: [Double], sex: String) -> [MetricPoint] {
        var out: [MetricPoint] = []
        let days = history.days   // sorted by day
        var lo = 0, hi = 0
        for (sunday, age) in zip(sundays, ages) {
            guard let end = VitalityEngine.epochDay(sunday) else { continue }
            let start = VitalityEngine.dayString(epochDay: end - VitalityEngine.longWindowDays + 1)
            while lo < days.count && days[lo].day < start { lo += 1 }
            while hi < days.count && days[hi].day <= sunday { hi += 1 }
            let slice = lo < hi ? Array(days[lo..<hi]) : []
            if let h = VitalityEngine.healthspan(days: slice, leanMass: history.leanMass, asOf: sunday,
                                                 chronoAge: age, sex: sex) {
                out += healthspanPoints(h)
            }
        }
        return out
    }
}
