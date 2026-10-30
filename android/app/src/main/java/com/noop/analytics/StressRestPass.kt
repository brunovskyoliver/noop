package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.MetricSeriesRow
import com.noop.data.SleepSession
import com.noop.data.StressAnalysisStore
import com.noop.data.WhoopRepository
import com.noop.data.WorkoutRow
import java.time.LocalDate
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import kotlin.math.floor

/** Stress is reduced oldest first, so fresh earlier aggregates feed the next day's exact 14-day window. */
internal object StressRestPass {
    suspend fun fromScored(
        repo: WhoopRepository, strapId: String, computedId: String, scored: List<DayResult>, oldestDay: String, newestDay: String,
        now: Long, profile: UserProfile, maxHR: Double?,
    ): Result {
        val zone = java.time.ZoneId.systemDefault()
        val days = windowDays(oldestDay, newestDay)
        if (days.isEmpty()) return Result(emptyList(), emptyMap(), emptyMap())
        val from = LocalDate.parse(oldestDay).minusDays(20).atStartOfDay(zone).toEpochSecond()
        val stored = StressAnalysisStore.allSleepSessions(repo, strapId, from, now + 86_400)
        fun wakeDay(session: SleepSession) = java.time.Instant.ofEpochSecond(session.endTs).atZone(zone).toLocalDate().toString()
        val storedWakeDays = stored.mapTo(HashSet(), ::wakeDay)
        val fresh = scored.flatMap { it.sleepSessions }.map {
            SleepSession(computedId, it.start, it.end, it.efficiency, it.restingHR, it.avgHRV, AnalyticsEngine.encodeStages(it.stages))
        }.filter { wakeDay(it) !in storedWakeDays }
        val sessions = (stored + fresh).distinctBy { (it.startTsAdjusted ?: it.startTs) to it.endTs }
        val merged = repo.daysMerged(strapId).associateBy { it.day }
        return run(repo, strapId, computedId, days, sessions,
            StressAnalysisStore.allWorkouts(repo, strapId, from, now), now,
            maxHR = maxHR ?: StrainScorer.tanakaHRmax(profile.age),
            restingHRByDay = merged.mapNotNull { (day, row) -> row.restingHr?.let { day to it.toDouble() } }.toMap())
    }

    /** Includes waking-only days and follows calendar boundaries across daylight-saving changes. */
    fun windowDays(oldest: String, newest: String): List<String> {
        val first = LocalDate.parse(oldest)
        val last = LocalDate.parse(newest)
        if (first > last) return emptyList()
        return generateSequence(first) { it.plusDays(1) }.takeWhile { it <= last }.map { it.toString() }.toList()
    }

    data class Result(
        val points: List<MetricSeriesRow>,
        val consistency: Map<String, Double>,
        val sleepStressByDay: Map<String, Double>,
        val replaceDays: List<String> = emptyList(),
    ) {
        fun rest(daily: DailyMetric, needHours: Double): Double? = RestPerformanceV2.composite(
            daily, needHours, consistency[daily.day], sleepStressByDay[daily.day],
        )
        // Swift twin `IntelligenceEngine.passRest(_:v2:needHours:consistency:sleepStressPct:)`.
        fun score(daily: DailyMetric, needHours: Double, enabled: Boolean): Double? =
            if (enabled) rest(daily, needHours) else RestScorer.restFromDaily(daily)

        fun appendRest(daily: DailyMetric, computedId: String, needHours: Double, enabled: Boolean, into: MutableList<MetricSeriesRow>) {
            score(daily, needHours, enabled)?.let { into.add(MetricSeriesRow(computedId, daily.day, "sleep_performance", it)) }
            if (enabled) into.addAll(parts(daily, computedId, needHours))
        }

        // Swift twin `IntelligenceEngine.restPartPoints(_:needHours:consistency:)`.
        fun parts(daily: DailyMetric, computedId: String, needHours: Double): List<MetricSeriesRow> = buildList {
            daily.totalSleepMin?.takeIf { it > 0 && needHours > 0 }?.let {
                add(MetricSeriesRow(computedId, daily.day, RestPerformanceV2.hoursVsNeedKey, floor(it / (needHours * 60) * 1000 + 0.5) / 10))
            }
            consistency[daily.day]?.let {
                add(MetricSeriesRow(computedId, daily.day, RestPerformanceV2.consistencyKey, floor(it * 1000 + 0.5) / 10))
            }
        }
    }
    val independentKeys = StressDaySummary.keys + StressMonitor.aggregateKeys + BroopEnergyEngine.keys
    val keys = independentKeys + listOf(RestPerformanceV2.hoursVsNeedKey, RestPerformanceV2.consistencyKey)

    /** No raw rows means retention, while sparse-but-present raw data invalidates stale summaries. */
    fun retainedOrFresh(hasRawHR: Boolean, stored: Map<String, Double>, fresh: Map<String, Double>): Map<String, Double> =
        if (hasRawHR) fresh.filterKeys { it in independentKeys } else stored.filterKeys { it in independentKeys }

    // Swift twin `IntelligenceEngine.stressRestPass(repo:windowDays:sessions:workouts:)`.
    suspend fun run(
        repo: WhoopRepository, strapId: String, computedId: String, days: List<String>,
        sessions: List<SleepSession>, workouts: List<WorkoutRow>, now: Long, maxHR: Double = 190.0,
        restingHRByDay: Map<String, Double> = emptyMap(),
    ): Result {
        if (days.isEmpty()) return Result(emptyList(), emptyMap(), emptyMap())
        val ordered = days.distinct().sorted()
        val first = LocalDate.parse(ordered.first())
        val prior = StressAnalysisStore.storedValues(repo, strapId, independentKeys,
            first.minusDays(14).toString(), ordered.last()).mapValues { it.value.toMutableMap() }.toMutableMap()
        val consistency = SleepRegularity.restConsistency(ordered, sessions.map {
            SleepRegularity.Session(it.startTsAdjusted ?: it.startTs, it.endTs, it.stagesJSON)
        })
        val points = ArrayList<MetricSeriesRow>()
        val sleepStress = LinkedHashMap<String, Double>()
        val replaceDays = ArrayList<String>()
        for (day in ordered) {
            coroutineContext.ensureActive()
            val date = LocalDate.parse(day)
            val previous = (14L downTo 1L).map { date.minusDays(it).toString() }
            val analysis = StressAnalysisStore.analyzeDayWithWitness(repo, strapId, day, now, sessions, workouts,
                previous.map { prior[it]?.get(StressMonitor.wakeFloorKey) },
                previous.map { prior[it]?.let(StressMonitor.NightAggregate::fromStored) })
            val result = analysis.result
            val values = retainedOrFresh(analysis.hasRawHR, prior[day].orEmpty(), result?.storedPairs().orEmpty()).toMutableMap()
            val energy = if (analysis.hasRawHR || values["energy_end"] == null) result?.let {
                BroopEnergyEngine.fromStress(it, prior[date.minusDays(1).toString()]?.get("energy_end"),
                BroopEnergyEngine.HeartProfile(restingHRByDay[day] ?: StrainScorer.defaultRestingHR, maxHR))
            } else null
            energy?.summary?.storedPairs()?.forEach { (key, value) -> values[key] = value }
            if (analysis.hasRawHR || values.isNotEmpty()) replaceDays.add(day)
            prior[day] = values
            values["sleep_stress_pct"]?.let { sleepStress[day] = it }
            for ((key, value) in values) points.add(MetricSeriesRow(computedId, day, key, value))
        }
        return Result(points, consistency, sleepStress, replaceDays)
    }
}
