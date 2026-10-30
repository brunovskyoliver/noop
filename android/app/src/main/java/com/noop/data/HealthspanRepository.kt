package com.noop.data

import com.noop.analytics.LabBookProjection
import com.noop.analytics.VitalityWindow
import java.time.LocalDate

data class HealthspanHistory(val days: List<VitalityWindow.Day>, val leanMass: List<VitalityWindow.LeanMassPoint>)

/** All Healthspan readouts use the same Sunday result and its stored fallback. */
data class HealthspanSnapshot(
    val updateDay: String,
    val chronoAge: Double,
    val result: VitalityWindow.Healthspan?,
    val recoveriesLast31: Int,
    val bodyAge: Double? = null,
    val pace: Double? = null,
    val vitality: Double? = null,
    val isStale: Boolean = false,
    val shownDay: String? = null,
    val trend: List<Pair<String, Double>> = emptyList(),
) {
    val delta: Double? get() = bodyAge?.let { it - chronoAge }
}

object HealthspanDates {
    // Swift twin `Repository.healthspanUpdateDay(today:)`.
    fun updateDay(today: String = LocalDate.now().toString()): String = VitalityWindow.sundayKey(today) ?: today

    // Swift twin `Repository.healthspanAge(profileAge:asOf:currentUpdateDay:)`.
    fun age(profileAge: Int, asOf: String, currentUpdateDay: String = updateDay()): Double {
        if (profileAge <= 0) return 0.0
        val asEpoch = VitalityWindow.epochDay(asOf) ?: return profileAge.toDouble()
        val currentEpoch = VitalityWindow.epochDay(currentUpdateDay) ?: return profileAge.toDouble()
        return profileAge - (currentEpoch - asEpoch).toDouble() / 365.25
    }
}

// Swift twin `Repository.healthspanHistory(from:to:fresh:)`.
suspend fun WhoopRepository.healthspanHistory(
    activeDeviceId: String,
    from: String,
    to: String,
    fresh: List<DailyMetric> = emptyList(),
): HealthspanHistory {
    val days = vitalityDays(activeDeviceId, to, fresh, fromDay = from)
    val leanStart = VitalityWindow.windowStart(from, VitalityWindow.leanMassCarryDays + 1)
    suspend fun bodySeries(key: String): List<Pair<String, Double>> {
        val result = linkedMapOf<String, Double>()
        for (source in listOf("health-connect", "apple-health")) {
            for (point in metricSeries(source, key, leanStart, to)) result[point.day] = point.value
            if (key == "weight") for (point in appleDaily(source, leanStart, to)) point.weightKg?.let { result[point.day] = it }
        }
        return result.map { it.key to it.value }
    }
    val lean = VitalityWindow.leanMassPoints(
        labBodyFat = metricSeries(LabBookProjection.SOURCE_ID, "body_fat", leanStart, to).map { it.day to it.value },
        bodyFat = bodySeries("body_fat"), leanKg = bodySeries("lean_mass"), weightKg = bodySeries("weight"),
    )
    return HealthspanHistory(days, lean)
}

// Swift twin `Repository.healthspan(asOf:profileAge:sex:fresh:)`.
suspend fun WhoopRepository.healthspan(
    activeDeviceId: String,
    asOf: String,
    profileAge: Int,
    sex: String,
    fresh: List<DailyMetric> = emptyList(),
    currentUpdateDay: String = HealthspanDates.updateDay(),
): VitalityWindow.Healthspan? {
    val age = HealthspanDates.age(profileAge, asOf, currentUpdateDay)
    if (age <= 0) return null
    val history = healthspanHistory(activeDeviceId, VitalityWindow.windowStart(asOf), asOf, fresh)
    return VitalityWindow.healthspan(history.days, asOf, age, sex, history.leanMass)
}

// Swift twin `Repository.healthspanSnapshot(profileAge:sex:)`.
suspend fun WhoopRepository.healthspanSnapshot(
    activeDeviceId: String,
    profileAge: Int,
    sex: String,
    today: String = LocalDate.now().toString(),
): HealthspanSnapshot {
    val updateDay = HealthspanDates.updateDay(today)
    val age = HealthspanDates.age(profileAge, updateDay, updateDay)
    val trend = metricSeriesComputedUnion(activeDeviceId, "body_age", "0000-01-01", "9999-12-31")
        .filter { VitalityWindow.sundayKey(it.day) == it.day }.map { it.day to it.value }.toMutableList()
    val paces = metricSeriesComputedUnion(activeDeviceId, "pace_of_aging", "0000-01-01", "9999-12-31")
    val vitality = metricSeriesComputedUnion(activeDeviceId, "vitality", "0000-01-01", "9999-12-31")
    val history = if (profileAge > 0) healthspanHistory(activeDeviceId, VitalityWindow.windowStart(updateDay), updateDay) else null
    val result = history?.let { VitalityWindow.healthspan(it.days, updateDay, age, sex, it.leanMass) }
    val recoveries = history?.let { VitalityWindow.recoveries(it.days, updateDay) } ?: 0
    var snapshot = HealthspanSnapshot(updateDay, age, result, recoveries)
    if (result != null) {
        trend.removeAll { it.first >= updateDay }
        trend += updateDay to result.current.bodyAge
        snapshot = snapshot.copy(bodyAge = result.current.bodyAge, pace = result.paceOfAging,
            vitality = result.current.vitality, shownDay = updateDay)
    } else trend.lastOrNull()?.let { last ->
        snapshot = snapshot.copy(bodyAge = last.second, pace = paces.lastOrNull { it.day == last.first }?.value,
            vitality = vitality.lastOrNull { it.day == last.first }?.value, isStale = true, shownDay = last.first,
            chronoAge = HealthspanDates.age(profileAge, last.first, updateDay))
    }
    return snapshot.copy(trend = trend)
}

/** Sunday rows for the current week, or an explicit history backfill using the same model and age clock. */
suspend fun WhoopRepository.healthspanWeeklyRows(
    activeDeviceId: String,
    newestDay: String,
    profileAge: Int,
    sex: String,
    fresh: List<DailyMetric> = emptyList(),
    backfillFrom: String? = null,
    currentUpdateDay: String = HealthspanDates.updateDay(),
): List<MetricSeriesRow> {
    if (profileAge <= 0) return emptyList()
    val latestSunday = HealthspanDates.updateDay(newestDay)
    val firstSunday = backfillFrom ?: latestSunday
    val sundays = VitalityWindow.sundays(firstSunday, latestSunday)
    val first = sundays.firstOrNull() ?: return emptyList()
    val history = healthspanHistory(activeDeviceId, VitalityWindow.windowStart(first), latestSunday, fresh)
    val source = computedDeviceId(activeDeviceId)
    return sundays.flatMap { sunday ->
        val age = HealthspanDates.age(profileAge, sunday, currentUpdateDay)
        val healthspan = VitalityWindow.healthspan(history.days, sunday, age, sex, history.leanMass)
        if (healthspan == null) emptyList() else listOf(
            MetricSeriesRow(source, sunday, "vitality", healthspan.current.vitality),
            MetricSeriesRow(source, sunday, "body_age", healthspan.current.bodyAge),
            MetricSeriesRow(source, sunday, "pace_of_aging", healthspan.paceOfAging),
        )
    }
}
