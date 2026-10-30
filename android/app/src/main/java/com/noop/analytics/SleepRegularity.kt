package com.noop.analytics

import java.time.LocalDate
import java.util.TimeZone
import kotlin.math.ceil
import org.json.JSONArray

/** Sleep Regularity Index and Rest consistency. Twin of StrandAnalytics/SleepRegularity.swift. */
object SleepRegularity {
    const val epochSeconds = 60
    private const val epochsPerDay = 86_400 / epochSeconds
    const val windowDays = 7
    const val minPairedSeconds = 120 * 3600
    const val minCapturedSleepSeconds = 2 * 3600
    const val restPriorDays = 4
    const val minRestPriorDays = 2
    const val minRestPairSeconds = 12 * 3600
    const val windowStartHour = 18

    /** Wake intervals use half-open ranges (`start until end`), in epoch seconds. */
    data class Session(val start: Long, val end: Long, val wake: List<LongRange> = emptyList()) {
        constructor(start: Long, end: Long, stagesJSON: String?) : this(start, end, parseWake(start, end, stagesJSON))
    }

    internal data class Timeline(val days: List<String>, val bounds: List<Int>, val state: ByteArray)

    private fun parseWake(start: Long, end: Long, json: String?): List<LongRange> = runCatching {
        if (json == null) return@runCatching emptyList()
        val array = JSONArray(json)
        buildList {
            for (index in 0 until array.length()) {
                val segment = array.optJSONObject(index) ?: continue
                val stage = segment.opt("stage") as? String ?: continue
                if (!SleepStageVocabulary.isWake(stage)) continue
                val a = (segment.opt("start") as? Number)?.toLong() ?: continue
                val b = (segment.opt("end") as? Number)?.toLong() ?: continue
                val lo = maxOf(a, start)
                val hi = minOf(b, end)
                if (hi > lo) add(lo until hi)
            }
        }
    }.getOrDefault(emptyList())

    private fun date(day: String): LocalDate? = runCatching {
        val parts = day.split('-').mapNotNull(String::toIntOrNull)
        if (parts.size != 3) return@runCatching null
        // Foundation's DateComponents normalises day/month overflow; mirror that behavior.
        LocalDate.of(parts[0], 1, 1).plusMonths(parts[1].toLong() - 1).plusDays(parts[2].toLong() - 1)
    }.getOrNull()

    // Swift twin `SleepRegularity.windowStart(day:timeZone:)`.
    fun windowStart(day: String, timeZone: TimeZone): Long? = date(day)?.minusDays(1)
        ?.atTime(windowStartHour, 0)?.atZone(timeZone.toZoneId())?.toEpochSecond()

    // Swift twin `SleepRegularity.dayKey(_:offset:)`.
    internal fun dayKey(day: String, offset: Int): String? = date(day)?.plusDays(offset.toLong())?.toString()

    // Swift twin `SleepRegularity.timeline(first:last:sessions:timeZone:)`.
    internal fun timeline(first: String, last: String, sessions: List<Session>, timeZone: TimeZone): Timeline? {
        val days = mutableListOf<String>()
        var day = first
        while (day <= last && days.size < 20_000) {
            days += day
            day = dayKey(day, 1) ?: return null
        }
        val next = dayKey(last, 1) ?: return null
        val starts = (days + next).mapNotNull { windowStart(it, timeZone) }
        if (starts.size != days.size + 1) return null
        val origin = starts.firstOrNull() ?: return null
        val bounds = starts.map { ((it - origin) / epochSeconds).toInt() }
        val count = bounds.last()
        if (count <= 0) return null
        val asleep = BooleanArray(count)
        // Swift twin `SleepRegularity.mark(_:_:_:)`.
        fun mark(start: Long, end: Long, value: Boolean) {
            val lo = maxOf(0, ceil((start - origin - epochSeconds / 2.0) / epochSeconds).toInt())
            val hi = minOf(count, ceil((end - origin - epochSeconds / 2.0) / epochSeconds).toInt())
            for (epoch in lo until maxOf(lo, hi)) asleep[epoch] = value
        }
        sessions.filter { it.end > it.start }.forEach { mark(it.start, it.end, true) }
        sessions.forEach { session -> session.wake.filterNot(LongRange::isEmpty).forEach { mark(it.first, it.last + 1, false) } }
        val state = ByteArray(count) { -1 }
        for (index in days.indices) {
            val lo = bounds[index]
            val hi = bounds[index + 1]
            var slept = 0
            for (epoch in lo until hi) if (asleep[epoch]) slept++
            if (slept * epochSeconds < minCapturedSleepSeconds) continue
            for (epoch in lo until hi) state[epoch] = if (asleep[epoch]) 1 else 0
        }
        return Timeline(days, bounds, state)
    }

    // Swift twin `SleepRegularity.agreement(_:_:_:lag:)`.
    internal fun agreement(state: ByteArray, lo: Int, hi: Int, lag: Int): Pair<Int, Int> {
        var same = 0
        var known = 0
        val from = maxOf(lo, lag)
        for (epoch in from until maxOf(from, hi)) {
            val a = state[epoch]
            val b = state[epoch - lag]
            if (a < 0 || b < 0) continue
            known++
            if (a == b) same++
        }
        return same to known
    }

    /** Seven-window SRI, absent until at least 120 hours of known consecutive-day pairs exist. */
    // Swift twin `SleepRegularity.sri(days:sessions:timeZone:)`.
    fun sri(days: List<String>, sessions: List<Session>, timeZone: TimeZone = TimeZone.getDefault()): Map<String, Double> {
        val first = days.minOrNull() ?: return emptyMap()
        val last = days.maxOrNull() ?: return emptyMap()
        val lead = dayKey(first, -(windowDays - 1)) ?: return emptyMap()
        val timeline = timeline(lead, last, sessions, timeZone) ?: return emptyMap()
        val wanted = days.toHashSet()
        return buildMap {
            for (index in (windowDays - 1) until timeline.days.size) {
                if (timeline.days[index] !in wanted) continue
                val (same, known) = agreement(timeline.state,
                    timeline.bounds[index - windowDays + 1] + epochsPerDay, timeline.bounds[index + 1], epochsPerDay)
                if (known * epochSeconds < minPairedSeconds) continue
                put(timeline.days[index], 200.0 * same / known - 100)
            }
        }
    }

    /** Tonight against up to four prior windows; at least two valid 12-hour comparisons are required. */
    // Swift twin `SleepRegularity.restConsistency(days:sessions:timeZone:)`.
    fun restConsistency(days: List<String>, sessions: List<Session>, timeZone: TimeZone = TimeZone.getDefault()): Map<String, Double> {
        val first = days.minOrNull() ?: return emptyMap()
        val last = days.maxOrNull() ?: return emptyMap()
        val lead = dayKey(first, -restPriorDays) ?: return emptyMap()
        val timeline = timeline(lead, last, sessions, timeZone) ?: return emptyMap()
        val wanted = days.toHashSet()
        return buildMap {
            for (index in restPriorDays until timeline.days.size) {
                if (timeline.days[index] !in wanted) continue
                val credits = mutableListOf<Double>()
                for (lag in 1..restPriorDays) {
                    val (same, known) = agreement(timeline.state, timeline.bounds[index], timeline.bounds[index + 1], lag * epochsPerDay)
                    if (known * epochSeconds < minRestPairSeconds) continue
                    credits += (2.0 * same / known - 1).coerceIn(0.0, 1.0)
                }
                if (credits.size >= minRestPriorDays) put(timeline.days[index], credits.sum() / credits.size)
            }
        }
    }

    // Swift twin `SleepRegularity.consistencyPercent(sri:)`.
    fun consistencyPercent(sri: Double): Double = sri.coerceIn(0.0, 100.0)

    /** Imported consistency wins only when it covers the newest requested day, as in Swift. */
    // Swift twin `SleepRegularity.resolve(dayKeys:importedPct:sriByDay:)`.
    fun resolve(dayKeys: List<String>, importedPct: Map<String, Double>, sriByDay: Map<String, Double>): List<Pair<String, Double>> =
        if (dayKeys.lastOrNull()?.let { importedPct[it] != null } == true) {
            dayKeys.mapNotNull { day -> importedPct[day]?.let { day to it } }
        } else sriByDay.toSortedMap().map { (day, value) -> day to consistencyPercent(value) }
}
