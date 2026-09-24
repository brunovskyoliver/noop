import Foundation
import WhoopStore
import StrandAnalytics

// Repository+Healthspan.swift — gathers the 180 days of inputs the Vitality / Body Age / Pace of Aging
// model reads (VitalityWindow.swift). One reader serves both the analysis pass that stores the weekly
// numbers and the Health screen's "what's driving this" breakdown, so the breakdown explains exactly the
// data the headline was computed from.
extension Repository {

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

    /// Build the per-day model inputs. Zone minutes come from workouts (WHOOP's rule: zone time counts
    /// inside activities, not everyday movement), each attributed to the local day it started on. A
    /// workout without stored zones contributes nothing rather than a guess.
    nonisolated static func vitalityDays(dailies: [DailyMetric], workouts: [WorkoutRow],
                                         vo2ByDay: [String: Double],
                                         dayOf: (Int) -> String) -> [VitalityEngine.Day] {
        var byDay: [String: VitalityEngine.Day] = [:]
        for d in dailies {
            byDay[d.day] = VitalityEngine.Day(
                day: d.day,
                restingHR: d.restingHr.map(Double.init),
                sleepHours: d.totalSleepMin.map { $0 / 60.0 },
                rmssd: d.avgHrv,
                steps: d.steps.map(Double.init))
        }
        // Sorted so the per-day float sums run in the same order as the Kotlin twin.
        for w in workouts.sorted(by: { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }) {
            guard let z = VitalityEngine.zoneMinutes(zonesJSON: w.zonesJSON,
                                                     durationS: w.durationS ?? Double(w.endTs - w.startTs))
            else { continue }
            let day = dayOf(w.startTs)
            var entry = byDay[day] ?? VitalityEngine.Day(day: day)
            entry.zone13Min += z.z13
            entry.zone45Min += z.z45
            byDay[day] = entry
        }
        for (day, v) in vo2ByDay {
            var entry = byDay[day] ?? VitalityEngine.Day(day: day)
            entry.vo2max = v
            byDay[day] = entry
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// The first day of the 180-day window ending on `day` (inclusive).
    nonisolated static func vitalityWindowStart(endingOn day: String) -> String {
        guard let end = VitalityEngine.epochDay(day) else { return day }
        let start = Date(timeIntervalSince1970: TimeInterval(end - VitalityEngine.longWindowDays + 1) * 86_400)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }

    /// Read the 180 days ending on `newestDay`. `fresh` rows (the analysis pass's own just-scored days)
    /// replace the stored row for the same day, so a pass never reads its own stale output.
    func vitalityDays(endingOn newestDay: String, fresh: [DailyMetric] = []) async -> [VitalityEngine.Day] {
        let from = Self.vitalityWindowStart(endingOn: newestDay)
        var byDay: [String: DailyMetric] = [:]
        for d in await dailyMetrics(fromDay: from, toDay: newestDay) { byDay[d.day] = d }
        for d in fresh where d.day >= from && d.day <= newestDay { byDay[d.day] = d }
        let lookback = VitalityEngine.longWindowDays + 8
        let workouts = await workoutRowsUnreconciled(days: lookback)
        let vo2 = Self.vitalityVO2Points(
            measured: await series(key: "vo2max", source: "apple-health", days: lookback),
            estimated: await exploreSeries(key: "vo2max_est", source: "my-whoop", days: lookback),
            from: from, to: newestDay)
        let days = Self.vitalityDays(
            dailies: Array(byDay.values), workouts: workouts, vo2ByDay: vo2,
            dayOf: { ts in
                AnalyticsEngine.dayString(ts, offsetSec: TimeZone.current.secondsFromGMT(
                    for: Date(timeIntervalSince1970: TimeInterval(ts))))
            })
        return days.filter { $0.day >= from && $0.day <= newestDay }
    }
}
