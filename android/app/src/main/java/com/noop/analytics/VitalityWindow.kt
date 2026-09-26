package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.WorkoutRow
import org.json.JSONObject

/**
 * The 6-month Body Age window and Pace of Aging. Byte-identical twin of the Swift
 * `VitalityWindow.swift` (StrandAnalytics); see that file for the method and sources.
 *
 * Body Age reads the last 180 days. Pace of Aging projects Body Age six months ahead assuming the last
 * 30 days' averages hold: pace = 1 + 2 · (BodyAge30 − BodyAge180), clamped to −1…3. A factor the recent
 * window lacks keeps its 6-month value.
 */
object VitalityWindow {

    /** One local day of inputs. [vo2max] is set only on days that carry a VO₂max point. */
    data class Day(
        val day: String,
        val restingHR: Double? = null,
        val sleepHours: Double? = null,
        val rmssd: Double? = null,
        val steps: Double? = null,
        val vo2max: Double? = null,
        val zone13Min: Double = 0.0,
        val zone45Min: Double = 0.0,
    ) {
        /** A worn day: any daily value. VO₂max alone does not count (it is weekly). */
        val covered: Boolean
            get() = restingHR != null || sleepHours != null || rmssd != null || steps != null ||
                zone13Min > 0 || zone45Min > 0
    }

    data class Healthspan(
        val bodyAge: VitalityEngine.Result,
        val recentBodyAge: VitalityEngine.Result?,
        val paceOfAging: Double?,
        val coveredDays: Int,
        val recentCoveredDays: Int,
    )

    enum class PaceBand { REVERSING, SLOWING, STEADY, ACCELERATED }

    const val longWindowDays = 180
    const val recentWindowDays = 30
    const val minZoneDays = 7
    const val minPaceDays = 60
    const val minRecentPaceDays = 14
    const val minPace = -1.0
    const val maxPace = 3.0

    /** Days since 1970-01-01 for "yyyy-MM-dd" (Hinnant's days_from_civil); pure integer math. */
    fun epochDay(s: String): Int? {
        val parts = s.split("-")
        if (parts.size != 3) return null
        val y0 = parts[0].toIntOrNull() ?: return null
        val m = parts[1].toIntOrNull() ?: return null
        val d = parts[2].toIntOrNull() ?: return null
        if (m !in 1..12 || d !in 1..31) return null
        val y = if (m <= 2) y0 - 1 else y0
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = (m + 9) % 12
        val doy = (153 * mp + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    internal fun median(xs: List<Double>): Double? {
        if (xs.isEmpty()) return null
        val s = xs.sorted(); val n = s.size
        return if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2
    }

    internal fun mean(xs: List<Double>): Double? {
        if (xs.isEmpty()) return null
        var sum = 0.0
        for (x in xs) sum += x
        return sum / xs.size
    }

    /** Aggregate a window (sorted by day) into model inputs; see the Swift twin for the rules. */
    fun inputs(days: List<Day>, chronoAge: Double, sex: String): VitalityEngine.Inputs {
        val nights = days.mapNotNull { it.sleepHours }.filter { it > 0 }
        val worn = days.filter { it.covered }
        var z13: Double? = null
        var z45: Double? = null
        if (worn.size >= minZoneDays) {
            val perWeek = 7 / worn.size.toDouble()
            var a = 0.0; var b = 0.0
            for (w in worn) { a += maxOf(0.0, w.zone13Min); b += maxOf(0.0, w.zone45Min) }
            z13 = a * perWeek; z45 = b * perWeek
        }
        val vo2 = mean(days.mapNotNull { it.vo2max }.filter { it > 0 })
        return VitalityEngine.Inputs(
            chronoAge = chronoAge,
            restingHR = median(days.mapNotNull { it.restingHR }.filter { it > 0 }),
            vo2max = vo2,
            expectedVO2max = if (vo2 == null) null else VitalityEngine.expectedVO2max(chronoAge, sex),
            sleepHours = mean(nights),
            sleepConsistency = VitalityEngine.sleepConsistency(nights),
            rmssd = median(days.mapNotNull { it.rmssd }.filter { it > 0 }),
            rmssdNorm = VitalityEngine.rmssdNorm(chronoAge),
            steps = mean(days.mapNotNull { it.steps }.filter { it >= 0 }),
            zone13MinPerWeek = z13, zone45MinPerWeek = z45,
        )
    }

    /** Recent inputs over long ones: every factor the recent window measured replaces the long value. */
    fun overlay(recent: VitalityEngine.Inputs, long: VitalityEngine.Inputs): VitalityEngine.Inputs {
        var out = long
        recent.restingHR?.let { out = out.copy(restingHR = it) }
        recent.vo2max?.let { out = out.copy(vo2max = it, expectedVO2max = recent.expectedVO2max) }
        recent.sleepHours?.let { out = out.copy(sleepHours = it) }
        recent.sleepConsistency?.let { out = out.copy(sleepConsistency = it) }
        recent.rmssd?.let { out = out.copy(rmssd = it) }
        recent.steps?.let { out = out.copy(steps = it) }
        val a = recent.zone13MinPerWeek; val b = recent.zone45MinPerWeek
        if (a != null && b != null) out = out.copy(zone13MinPerWeek = a, zone45MinPerWeek = b)
        return out
    }

    /** Body Age over the 180 days ending at [asOf] plus Pace of Aging from its last 30 days. */
    fun healthspan(days: List<Day>, asOf: String, chronoAge: Double, sex: String): Healthspan? {
        val end = epochDay(asOf) ?: return null
        val dated = days.mapNotNull { d -> epochDay(d.day)?.let { it to d } }
            .filter { it.first <= end && it.first > end - longWindowDays }
            .sortedBy { it.first }
        val long = dated.map { it.second }
        val recent = dated.filter { it.first > end - recentWindowDays }.map { it.second }
        val longInputs = inputs(long, chronoAge, sex)
        val bodyAge = VitalityEngine.compute(longInputs) ?: return null
        val covered = long.count { it.covered }
        val recentCovered = recent.count { it.covered }
        var recentResult: VitalityEngine.Result? = null
        var pace: Double? = null
        if (covered >= minPaceDays && recentCovered >= minRecentPaceDays) {
            val projected = overlay(inputs(recent, chronoAge, sex), longInputs)
            VitalityEngine.compute(projected)?.let { r ->
                recentResult = r
                pace = (1 + 2 * (r.bodyAge - bodyAge.bodyAge)).coerceIn(minPace, maxPace)
            }
        }
        return Healthspan(bodyAge, recentResult, pace, covered, recentCovered)
    }

    fun paceBand(pace: Double): PaceBand = when {
        pace < 0 -> PaceBand.REVERSING
        pace < 0.95 -> PaceBand.SLOWING
        pace < 1.05 -> PaceBand.STEADY
        else -> PaceBand.ACCELERATED
    }

    /**
     * A workout's zone 1–3 and 4–5 minutes from its `zonesJSON` (percent per zone, keys "z1"…"z5" or
     * "zone1"…"zone5"). Only JSON numbers count, matching the Swift twin's NSNumber cast. null when the
     * row carries no usable zones.
     */
    fun zoneMinutes(zonesJSON: String?, durationS: Double?): Pair<Double, Double>? {
        if (zonesJSON == null || durationS == null || durationS <= 0) return null
        val o = runCatching { JSONObject(zonesJSON) }.getOrNull() ?: return null
        val pct = DoubleArray(5) { i ->
            val k1 = "z${i + 1}"; val k2 = "zone${i + 1}"
            val v = if (o.has(k1)) o.opt(k1) else o.opt(k2)
            maxOf(0.0, (v as? Number)?.toDouble() ?: 0.0)
        }
        if (pct.none { it > 0 }) return null
        val minutes = durationS / 60
        return Pair(minutes * (pct[0] + pct[1] + pct[2]) / 100, minutes * (pct[3] + pct[4]) / 100)
    }

    /**
     * VO₂max points for the window: a measured value (Apple Health / Health Connect import) wins over the
     * resting-HR estimate, chosen once for the whole window and never averaged together. Twin of Swift
     * `Repository.vitalityVO2Points`.
     */
    fun vo2Points(
        measured: List<Pair<String, Double>>,
        estimated: List<Pair<String, Double>>,
        from: String,
        to: String,
    ): Map<String, Double> {
        val inWindow = { p: Pair<String, Double> -> p.first >= from && p.first <= to && p.second > 0 }
        val chosen = if (measured.any(inWindow)) measured else estimated
        val out = HashMap<String, Double>()
        for (p in chosen) if (inWindow(p)) out[p.first] = p.second
        return out
    }

    /** Per-day inputs from dailies, workouts (zones by local start day) and VO₂max points, sorted by day.
     *  Twin of Swift `Repository.vitalityDays(dailies:workouts:vo2ByDay:dayOf:)`. */
    fun days(
        dailies: List<DailyMetric>,
        workouts: List<WorkoutRow>,
        vo2ByDay: Map<String, Double>,
        dayOf: (Long) -> String,
    ): List<Day> {
        val byDay = HashMap<String, Day>()
        for (d in dailies) {
            byDay[d.day] = Day(
                day = d.day,
                restingHR = d.restingHr?.toDouble(),
                sleepHours = d.totalSleepMin?.let { it / 60.0 },
                rmssd = d.avgHrv,
                steps = d.steps?.toDouble(),
            )
        }
        // Sorted so the per-day float sums run in the same order as the Swift twin.
        for (w in workouts.sortedWith(compareBy({ it.startTs }, { it.endTs }))) {
            val z = zoneMinutes(w.zonesJSON, w.durationS ?: (w.endTs - w.startTs).toDouble()) ?: continue
            val day = dayOf(w.startTs)
            val e = byDay[day] ?: Day(day)
            byDay[day] = e.copy(zone13Min = e.zone13Min + z.first, zone45Min = e.zone45Min + z.second)
        }
        for ((day, v) in vo2ByDay) {
            byDay[day] = (byDay[day] ?: Day(day)).copy(vo2max = v)
        }
        return byDay.values.sortedBy { it.day }
    }

    /** First day of the 180-day window ending on [day] (inclusive). */
    fun windowStart(day: String): String {
        val end = epochDay(day) ?: return day
        return java.time.LocalDate.ofEpochDay((end - longWindowDays + 1).toLong()).toString()
    }
}
