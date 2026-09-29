import Foundation
import WhoopStore
import StrandAnalytics

// Repository+Healthspan.swift — gathers the inputs of the Healthspan v2 model (Broop Age / Body Age and
// Pace of Aging, VitalityEngine + VitalityWindow). One reader serves the weekly store pass, the one-shot
// history backfill and the screens' per-factor breakdown, so every readout explains exactly the data the
// stored number was computed from.
//
// iOS-only fork change: the Android twin of this reader is intentionally not updated.
extension Repository {

    /// Everything the model reads for a span of days: one `VitalityEngine.Day` per day plus the dated
    /// lean-mass readings.
    struct HealthspanHistory: Sendable {
        var days: [VitalityEngine.Day]
        var leanMass: [VitalityEngine.LeanMassPoint]
    }

    /// A Lift Log session reduced to what strength time needs.
    struct HealthspanLift: Sendable {
        var startTs: Int
        var endTs: Int
        var sport: String
    }

    /// VO₂max points for the window. A measured value (Apple Health, from Apple Watch outdoor workouts or
    /// a lab entry) is preferred over NOOP's resting-HR estimate, and the two are never averaged together:
    /// they sit on different scales and mixing them would read as a trend. The source is chosen once for
    /// the whole window.
    nonisolated static func vitalityVO2Points(measured: [(day: String, value: Double)],
                                              estimated: [(day: String, value: Double)],
                                              from: String, to: String) -> [String: Double] {
        let inWindow = { (p: (day: String, value: Double)) in p.day >= from && p.day <= to && p.value > 0 }
        let chosen = measured.contains(where: inWindow) ? measured : estimated
        var out: [String: Double] = [:]
        for p in chosen where inWindow(p) { out[p.day] = p.value }
        return out
    }

    /// Build the per-day model inputs.
    /// - Zone minutes come from workouts (WHOOP's rule: zone time counts inside activities, not everyday
    ///   movement), each attributed to the local day it started on. A workout without stored zones adds
    ///   no zone time rather than a guess.
    /// - Strength minutes: every workout whose sport `VitalityEngine.isStrengthSport` accepts, plus each
    ///   finished Lift Log session that has NO workout row with the same start and sport (a logged session
    ///   normally also exists as a workout row under that natural key, so it is never counted twice).
    /// - Sleep consistency: the Sleep screen's per-night value (`SleepConsistency.resolve`).
    /// - Steps: `stepsByDay` (the app's shared steps resolver) where it has the day, else the daily row.
    /// - `hasRecovery`: a scored Charge day (the white paper's "recovery" for the unlock gate).
    nonisolated static func vitalityDays(dailies: [DailyMetric], workouts: [WorkoutRow],
                                         lifts: [HealthspanLift] = [],
                                         vo2ByDay: [String: Double], measuredVO2ByDay: [String: Double] = [:],
                                         consistencyByDay: [String: Double] = [:],
                                         stepsByDay: [String: Double] = [:],
                                         dayOf: (Int) -> String) -> [VitalityEngine.Day] {
        var byDay: [String: VitalityEngine.Day] = [:]
        func entry(_ day: String) -> VitalityEngine.Day { byDay[day] ?? VitalityEngine.Day(day: day) }
        for d in dailies {
            byDay[d.day] = VitalityEngine.Day(
                day: d.day,
                restingHR: d.restingHr.map(Double.init),
                sleepHours: d.totalSleepMin.map { $0 / 60.0 },
                steps: d.steps.map(Double.init),
                hasRecovery: d.recovery != nil)
        }
        let sorted = workouts.sorted { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }
        var workoutKeys = Set<String>()
        for w in sorted {
            let dur = w.durationS ?? Double(w.endTs - w.startTs)
            let day = dayOf(w.startTs)
            workoutKeys.insert("\(w.startTs)|\(w.sport.lowercased())")
            if let z = VitalityEngine.zoneMinutes(zonesJSON: w.zonesJSON, durationS: dur) {
                var e = entry(day)
                e.zone13Min += z.z13
                e.zone45Min += z.z45
                byDay[day] = e
            }
            if VitalityEngine.isStrengthSport(w.sport), dur > 0 {
                var e = entry(day)
                e.strengthMin += dur / 60
                byDay[day] = e
            }
        }
        for l in lifts.sorted(by: { $0.startTs < $1.startTs })
        where l.endTs > l.startTs && !workoutKeys.contains("\(l.startTs)|\(l.sport.lowercased())") {
            let day = dayOf(l.startTs)
            var e = entry(day)
            e.strengthMin += Double(l.endTs - l.startTs) / 60
            byDay[day] = e
        }
        for (day, v) in vo2ByDay {
            var e = entry(day)
            e.vo2max = v
            byDay[day] = e
        }
        for (day, v) in measuredVO2ByDay {
            var e = entry(day)
            e.measuredVO2max = v
            byDay[day] = e
        }
        for (day, v) in stepsByDay where v > 0 {
            var e = entry(day)
            e.steps = v
            byDay[day] = e
        }
        for (day, v) in consistencyByDay where byDay[day] != nil {
            byDay[day]?.sleepConsistency = v
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Lean body mass % by day. Priority per day: a Lab Book body-fat entry, then Apple Health body fat,
    /// then Apple Health lean mass ÷ weight on the same day. Lean % = 100 − body-fat %. Readings outside
    /// 40–97 % are dropped as implausible.
    nonisolated static func leanMassPoints(labBodyFat: [(day: String, value: Double)],
                                           appleBodyFat: [(day: String, value: Double)],
                                           leanKg: [(day: String, value: Double)],
                                           weightKg: [(day: String, value: Double)]) -> [VitalityEngine.LeanMassPoint] {
        var out: [String: Double] = [:]
        var weight: [String: Double] = [:]
        for w in weightKg where w.value > 0 { weight[w.day] = w.value }
        for l in leanKg { if let w = weight[l.day], l.value > 0 { out[l.day] = l.value / w * 100 } }
        for b in appleBodyFat where b.value > 0 { out[b.day] = 100 - b.value }
        for b in labBodyFat where b.value > 0 { out[b.day] = 100 - b.value }
        return out.filter { (40...97).contains($0.value) }
            .map { VitalityEngine.LeanMassPoint(day: $0.key, pct: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// The first day of the `days`-long window ending on `day` (inclusive).
    nonisolated static func vitalityWindowStart(endingOn day: String,
                                                days: Int = VitalityEngine.longWindowDays) -> String {
        guard let end = VitalityEngine.epochDay(day) else { return day }
        return VitalityEngine.dayString(epochDay: end - days + 1)
    }

    /// Read the model's inputs for every day in `from…to`. `fresh` rows (the analysis pass's own just-scored
    /// days) replace the stored row for the same day, so a pass never reads its own stale output. Lean mass
    /// is read a year further back so an older reading can carry into the window.
    func healthspanHistory(from: String, to: String, fresh: [DailyMetric] = []) async -> HealthspanHistory {
        var byDay: [String: DailyMetric] = [:]
        for d in await dailyMetrics(fromDay: from, toDay: to) { byDay[d.day] = d }
        // dailyMetrics() reads imported sources only. The shared dashboard cache includes computed
        // recoveries and user-edited sleep; without it a strap-only install never unlocks Healthspan.
        for d in days where d.day >= from && d.day <= to { byDay[d.day] = d }
        for d in fresh where d.day >= from && d.day <= to { byDay[d.day] = d }
        let nowEpoch = VitalityEngine.epochDay(Self.dayString(Date())) ?? 0
        let fromEpoch = VitalityEngine.epochDay(from) ?? nowEpoch
        let lookback = max(1, nowEpoch - fromEpoch + 8)
        let workouts = await workoutRowsUnreconciled(days: lookback)
        var lifts: [HealthspanLift] = []
        if let store = await storeHandle() {
            let now = Int(Date().timeIntervalSince1970)
            lifts = ((try? await store.liftSessions(deviceId: deviceId, fromTs: now - lookback * 86_400,
                                                    toTs: now + 86_400)) ?? [])
                .compactMap { s in s.endTs.map { HealthspanLift(startTs: s.startTs, endTs: $0, sport: s.sport) } }
        }
        let measuredVO2 = Self.vitalityVO2Points(
            measured: await series(key: "vo2max", source: LabBookProjection.sourceId, days: lookback)
                + series(key: "vo2max", source: "apple-health", days: lookback),
            estimated: [], from: from, to: to)
        let vo2 = Self.vitalityVO2Points(measured: [],
            estimated: await exploreSeries(key: "vo2max_est", source: "my-whoop", days: lookback),
            from: from, to: to)
        // Steps through the app's shared resolver (measured strap, phone import, strap estimate), with the
        // Apple Health daily aggregate as the last fallback, as the Home screen's steps do.
        var steps: [String: Double] = [:]
        for p in (await resolvedSteps(from: from, to: to)).points where p.value > 0 { steps[p.day] = p.value }
        for a in await appleDailyRows(days: lookback) where steps[a.day] == nil && a.day >= from && a.day <= to {
            if let n = a.steps, n > 0 { steps[a.day] = Double(n) }
        }
        let lmLookback = lookback + VitalityEngine.leanMassCarryDays
        let lean = Self.leanMassPoints(
            labBodyFat: await series(key: "body_fat", source: LabBookProjection.sourceId, days: lmLookback),
            appleBodyFat: await series(key: "body_fat", source: "apple-health", days: lmLookback),
            leanKg: await series(key: "lean_mass", source: "apple-health", days: lmLookback),
            weightKg: await series(key: "weight", source: "apple-health", days: lmLookback))
        // The Sleep screen's consistency, resolved over the full cached history exactly as SleepModel does.
        let dayKeys = days.map(\.day)
        let imported = importedSleep.compactMapValues(\.consistencyPct)
        let sleepRows = sleeps
        let dailies = Array(byDay.values)
        return await Task.detached(priority: .utility) {
            var consistency: [String: Double] = [:]
            for p in SleepConsistency.resolve(dayKeys: dayKeys, importedPct: imported,
                                              nights: SleepModel.consistencyNights(sleepRows))
            where p.day >= from && p.day <= to {
                consistency[p.day] = p.pct
            }
            let days = Self.vitalityDays(
                dailies: dailies, workouts: workouts, lifts: lifts, vo2ByDay: vo2, measuredVO2ByDay: measuredVO2,
                consistencyByDay: consistency, stepsByDay: steps,
                dayOf: { ts in
                    AnalyticsEngine.dayString(ts, offsetSec: TimeZone.current.secondsFromGMT(
                        for: Date(timeIntervalSince1970: TimeInterval(ts))))
                })
            return HealthspanHistory(days: days.filter { $0.day >= from && $0.day <= to }, leanMass: lean)
        }.value
    }

    /// THE Healthspan resolver for one update day: reads the 180-day window ending on `asOf` and runs
    /// `VitalityEngine.healthspan` off the main actor. The weekly store pass, the history backfill and every
    /// screen call this, so no two readouts can disagree.
    func healthspan(asOf: String, profileAge: Int, sex: String,
                    fresh: [DailyMetric] = []) async -> VitalityEngine.Healthspan? {
        let age = Self.healthspanAge(profileAge: profileAge, asOf: asOf)
        guard age > 0 else { return nil }
        let history = await healthspanHistory(from: Self.vitalityWindowStart(endingOn: asOf), to: asOf, fresh: fresh)
        return await Task.detached(priority: .utility) {
            VitalityEngine.healthspan(days: history.days, leanMass: history.leanMass, asOf: asOf,
                                      chronoAge: age, sex: sex)
        }.value
    }

    /// The Sunday the current Healthspan belongs to (the latest update day on or before today).
    static func healthspanUpdateDay(today: String? = nil) -> String {
        let t = today ?? dayString(Date())
        return VitalityEngine.sundayKey(onOrBefore: t) ?? t
    }

    /// Chronological age on update day `asOf`. The profile stores a whole-year age, taken as the age on
    /// the CURRENT update day; an earlier Sunday is that many weeks younger, so the history backfill and
    /// the trend's chronological-age line move with the calendar.
    static func healthspanAge(profileAge: Int, asOf: String, currentUpdateDay: String? = nil) -> Double {
        guard profileAge > 0 else { return 0 }
        let cur = currentUpdateDay ?? healthspanUpdateDay()
        guard let a = VitalityEngine.epochDay(asOf), let c = VitalityEngine.epochDay(cur) else { return Double(profileAge) }
        return Double(profileAge) - Double(c - a) / 365.25
    }

    /// Everything a Healthspan readout shows, from the one resolver (see `HealthspanSnapshot`).
    func healthspanSnapshot(profileAge: Int, sex: String) async -> HealthspanSnapshot {
        let updateDay = Self.healthspanUpdateDay()
        let chrono = Self.healthspanAge(profileAge: profileAge, asOf: updateDay, currentUpdateDay: updateDay)
        var trend = await exploreSeries(key: "body_age", source: "my-whoop")
        trend = trend.filter { VitalityEngine.sundayKey(onOrBefore: $0.day) == $0.day }
        let paces = await exploreSeries(key: "pace_of_aging", source: "my-whoop")
        let vits = await exploreSeries(key: "vitality", source: "my-whoop")
        let history: HealthspanHistory? = profileAge > 0
            ? await healthspanHistory(from: Self.vitalityWindowStart(endingOn: updateDay), to: updateDay) : nil
        let (result, recoveries): (VitalityEngine.Healthspan?, Int) = await Task.detached(priority: .utility) {
            guard let history else { return (nil, 0) }
            return (VitalityEngine.healthspan(days: history.days, leanMass: history.leanMass, asOf: updateDay,
                                              chronoAge: chrono, sex: sex),
                    VitalityEngine.recoveries(days: history.days, asOf: updateDay))
        }.value
        var snap = HealthspanSnapshot(updateDay: updateDay, chronoAge: chrono, result: result,
                                      recoveriesLast31: recoveries)
        if let r = result {
            trend.removeAll { $0.day >= updateDay }
            trend.append((day: updateDay, value: r.current.bodyAge))
            snap.bodyAge = r.current.bodyAge
            snap.pace = r.paceOfAging
            snap.vitality = r.current.vitality
            snap.shownDay = updateDay
        } else if let last = trend.last {
            snap.bodyAge = last.value
            snap.pace = paces.last { $0.day == last.day }?.value
            snap.vitality = vits.last { $0.day == last.day }?.value
            snap.isStale = true
            snap.shownDay = last.day
            snap.chronoAge = Self.healthspanAge(profileAge: profileAge, asOf: last.day, currentUpdateDay: updateDay)
        }
        snap.trend = trend
        return snap
    }
}

/// What every Healthspan readout shows (the Broop Healthspan screen and Health-tab card, the macOS Health
/// section), built by `Repository.healthspanSnapshot` from the ONE resolver, so the headline, the factor
/// rows and the trend's newest point are the same computation.
struct HealthspanSnapshot {
    /// The update Sunday the figures belong to.
    var updateDay: String
    /// Chronological age on the day of the shown value.
    var chronoAge: Double
    /// The live resolver result for `updateDay`; nil while the recovery gate fails (or no profile age).
    var result: VitalityEngine.Healthspan?
    /// Recoveries in the last 31 days, counted as the resolver's gate counts them.
    var recoveriesLast31: Int
    /// Broop Age: the resolver's value, else the newest stored week (then `isStale`).
    var bodyAge: Double? = nil
    var pace: Double? = nil
    var vitality: Double? = nil
    /// The headline is an older stored week because the recovery gate currently fails.
    var isStale = false
    /// The update day of the shown value.
    var shownDay: String? = nil
    /// Stored weekly Broop Age, oldest first, with `updateDay` replaced by the live value.
    var trend: [(day: String, value: Double)] = []

    static let empty = HealthspanSnapshot(updateDay: "", chronoAge: 0, result: nil, recoveriesLast31: 0)

    /// Broop Age − chronological age (positive = older).
    var delta: Double? { bodyAge.map { $0 - chronoAge } }
}
