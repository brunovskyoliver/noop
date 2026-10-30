package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.WorkoutRow
import org.json.JSONObject
import java.time.LocalDate
import java.util.Locale

/** Healthspan v2 windows, recovery gate, Sunday cadence and projection. Swift VitalityWindow twin. */
object VitalityWindow {
    data class Day(
        val day: String,
        val restingHR: Double? = null,
        val sleepHours: Double? = null,
        val sleepConsistency: Double? = null,
        val steps: Double? = null,
        val vo2max: Double? = null,
        val measuredVO2max: Double? = null,
        val zone13Min: Double = 0.0,
        val zone45Min: Double = 0.0,
        val strengthMin: Double = 0.0,
        val hasRecovery: Boolean = false,
    ) {
        val covered: Boolean get() = restingHR != null || sleepHours != null || steps != null || hasRecovery ||
            zone13Min > 0 || zone45Min > 0 || strengthMin > 0
    }

    data class LeanMassPoint(val day: String, val pct: Double)
    data class Lift(val startTs: Long, val endTs: Long, val sport: String)

    data class Healthspan(
        val asOf: String,
        val current: VitalityEngine.Result,
        val projected: VitalityEngine.Result,
        val paceOfAging: Double,
        val longInputs: VitalityEngine.Inputs,
        val recentInputs: VitalityEngine.Inputs,
        val recoveriesLast31: Int,
        val coveredDays: Int,
    ) {
        val bodyAge: VitalityEngine.Result get() = current
        val recentBodyAge: VitalityEngine.Result get() = projected
    }

    enum class PaceBand { REVERSING, SLOWING, STEADY, ACCELERATED }

    const val longWindowDays = 180
    const val recentWindowDays = 30
    const val gateWindowDays = 31
    const val gateMinRecoveries = 21
    const val leanMassCarryDays = 365
    const val minRateSpanDays = 7
    const val minPace = -1.0
    const val maxPace = 3.0
    const val projectionYears = 0.5

    /** Proleptic Gregorian days_from_civil, matching the Swift parser. */
    fun epochDay(value: String): Int? {
        val parts = value.split('-').filter { it.isNotEmpty() }
        if (parts.size != 3) return null
        val year0 = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        if (month !in 1..12 || day !in 1..31) return null
        val year = if (month <= 2) year0 - 1 else year0
        val era = (if (year >= 0) year else year - 399) / 400
        val yearOfEra = year - era * 400
        val shiftedMonth = (month + 9) % 12
        val dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    // Swift twin `VitalityEngine.sundayKey(onOrBefore:)`.
    fun sundayKey(onOrBefore: String): String? {
        val epoch = epochDay(onOrBefore) ?: return null
        val back = ((epoch + 4) % 7 + 7) % 7
        return HRVStatus.dayString(epoch - back)
    }

    // Swift twin `VitalityEngine.sundays(from:to:)`.
    fun sundays(from: String, to: String): List<String> {
        val firstDay = epochDay(from) ?: return emptyList()
        val lastSunday = sundayKey(to)?.let(::epochDay) ?: return emptyList()
        val firstSunday = firstDay + ((7 - ((firstDay + 4) % 7 + 7) % 7) % 7)
        if (firstSunday > lastSunday) return emptyList()
        return (firstSunday..lastSunday step 7).map(HRVStatus::dayString)
    }

    private fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size

    /** Daily means and weekly rates over the calendar span, including unworn gaps after the first day. */
    // Swift twin `VitalityEngine.inputs(days:windowEnd:chronoAge:sex:leanMass:)`.
    internal fun windowInputs(
        days: List<Pair<Int, Day>>,
        windowEnd: Int,
        chronoAge: Double,
        sex: String,
        leanMass: Double?,
    ): VitalityEngine.Inputs {
        val rows = days.map { it.second }
        var moderate: Double? = null
        var vigorous: Double? = null
        var strength: Double? = null
        days.firstOrNull { it.second.covered }?.first?.let { first ->
            val span = windowEnd - first + 1
            if (span >= minRateSpanDays) {
                val perWeek = 7 / span.toDouble()
                moderate = rows.sumOf { maxOf(0.0, it.zone13Min) } * perWeek
                vigorous = rows.sumOf { maxOf(0.0, it.zone45Min) } * perWeek
                val totalStrength = rows.sumOf { maxOf(0.0, it.strengthMin) }
                strength = if (totalStrength > 0) totalStrength * perWeek else null
            }
        }
        return VitalityEngine.Inputs(
            chronoAge = chronoAge, sex = sex,
            sleepHours = mean(rows.mapNotNull { it.sleepHours }.filter { it > 0 }),
            sleepConsistency = mean(rows.mapNotNull { it.sleepConsistency }.filter { it >= 0 }),
            zone13MinPerWeek = moderate, zone45MinPerWeek = vigorous, strengthMinPerWeek = strength,
            steps = mean(rows.mapNotNull { it.steps }.filter { it > 0 }),
            vo2max = mean(rows.mapNotNull { it.measuredVO2max }.filter { it > 0 })
                ?: mean(rows.mapNotNull { it.vo2max }.filter { it > 0 }),
            restingHR = mean(rows.mapNotNull { it.restingHR }.filter { it > 0 }),
            leanMassPct = leanMass,
        )
    }

    fun overlay(recent: VitalityEngine.Inputs, long: VitalityEngine.Inputs): VitalityEngine.Inputs {
        var result = long
        for (factor in VitalityEngine.Factor.entries) recent.value(factor)?.let { result = result.setting(factor, it) }
        return result
    }

    // Swift twin `VitalityEngine.recoveries(days:asOf:)`.
    fun recoveries(days: List<Day>, asOf: String): Int {
        val end = epochDay(asOf) ?: return 0
        return days.count { day ->
            val epoch = epochDay(day.day)
            day.hasRecovery && epoch != null && epoch <= end && epoch > end - gateWindowDays
        }
    }

    // Swift twin `VitalityEngine.healthspan(days:leanMass:asOf:chronoAge:sex:)`.
    fun healthspan(
        days: List<Day>,
        asOf: String,
        chronoAge: Double,
        sex: String,
        leanMass: List<LeanMassPoint> = emptyList(),
    ): Healthspan? {
        val end = epochDay(asOf) ?: return null
        if (chronoAge <= 0) return null
        val recoveries = recoveries(days, asOf)
        if (recoveries < gateMinRecoveries) return null
        val dated = days.mapNotNull { day -> epochDay(day.day)?.let { it to day } }
            .filter { it.first <= end && it.first > end - longWindowDays }.sortedBy { it.first }
        val recent = dated.filter { it.first > end - recentWindowDays }
        val lean = leanMass.mapNotNull { point -> epochDay(point.day)?.takeIf { it <= end && point.pct > 0 }?.let { it to point.pct } }
            .sortedBy { it.first }
        val longLean = mean(lean.filter { it.first > end - longWindowDays }.map { it.second })
            ?: lean.lastOrNull { it.first > end - leanMassCarryDays }?.second
        val recentLean = mean(lean.filter { it.first > end - recentWindowDays }.map { it.second })
        val longInputs = windowInputs(dated, end, chronoAge, sex, longLean)
        val current = VitalityEngine.compute(longInputs) ?: return null
        val recentInputs = windowInputs(recent, end, chronoAge + projectionYears, sex, recentLean)
        val projectedInputs = overlay(recentInputs, longInputs).copy(chronoAge = chronoAge + projectionYears)
        val projected = VitalityEngine.compute(projectedInputs) ?: return null
        val pace = minOf(maxPace, maxOf(minPace, 1 + (projected.ageDelta - current.ageDelta) / projectionYears))
        return Healthspan(asOf, current, projected, pace, longInputs, recentInputs, recoveries, dated.count { it.second.covered })
    }

    fun paceBand(pace: Double): PaceBand = when {
        pace < 0 -> PaceBand.REVERSING
        pace < 0.95 -> PaceBand.SLOWING
        pace < 1.05 -> PaceBand.STEADY
        else -> PaceBand.ACCELERATED
    }

    fun zoneMinutes(zonesJSON: String?, durationS: Double?): Pair<Double, Double>? {
        if (zonesJSON == null || durationS == null || durationS <= 0) return null
        val json = runCatching { JSONObject(zonesJSON) }.getOrNull() ?: return null
        val percent = DoubleArray(5) { index ->
            val first = "z${index + 1}"
            val second = "zone${index + 1}"
            val value = if (json.has(first)) json.opt(first) else json.opt(second)
            maxOf(0.0, when (value) {
                is Number -> value.toDouble()
                is Boolean -> if (value) 1.0 else 0.0
                else -> 0.0
            })
        }
        if (percent.none { it > 0 }) return null
        val minutes = durationS / 60
        return minutes * (percent[0] + percent[1] + percent[2]) / 100 to minutes * (percent[3] + percent[4]) / 100
    }

    private val strengthSports = setOf("strength", "strengthtraining", "strengthtrainer", "weightlifting", "powerlifting", "bodybuilding",
        "functionalfitness", "functionalstrengthtraining", "traditionalstrengthtraining", "crossfit", "hiit", "highintensityintervaltraining",
        "pilates", "yoga", "hotyoga", "barre", "barre3", "barrys", "f45", "f45training", "boxfitness", "bootcamp", "calisthenics",
        "coretraining", "rucking", "solidcore", "babywearing", "toddlerwearing")

    // Swift twin `VitalityEngine.isStrengthSport(_:)`.
    fun isStrengthSport(sport: String): Boolean = sport.lowercase(Locale.ROOT).filter { it.isLetterOrDigit() } in strengthSports

    // Swift twin `Repository.vitalityVO2Points(measured:estimated:from:to:)`.
    fun vo2Points(measured: List<Pair<String, Double>>, estimated: List<Pair<String, Double>>, from: String, to: String): Map<String, Double> {
        fun inWindow(point: Pair<String, Double>): Boolean = point.first in from..to && point.second > 0
        val chosen = if (measured.any(::inWindow)) measured else estimated
        val result = linkedMapOf<String, Double>()
        for (point in chosen) if (inWindow(point)) result[point.first] = point.second
        return result
    }

    /** Source shaping shared by the weekly writer and health readouts, including Lift Log deduplication. */
    // Swift twin `Repository.vitalityDays(dailies:workouts:lifts:vo2ByDay:measuredVO2ByDay:consistencyByDay:stepsByDay:dayOf:)`.
    fun days(
        dailies: List<DailyMetric>,
        workouts: List<WorkoutRow>,
        vo2ByDay: Map<String, Double>,
        lifts: List<Lift> = emptyList(),
        measuredVO2ByDay: Map<String, Double> = emptyMap(),
        consistencyByDay: Map<String, Double> = emptyMap(),
        stepsByDay: Map<String, Double> = emptyMap(),
        dayOf: (Long) -> String,
    ): List<Day> {
        val byDay = linkedMapOf<String, Day>()
        for (daily in dailies) byDay[daily.day] = Day(daily.day, restingHR = daily.restingHr?.toDouble(),
            sleepHours = daily.totalSleepMin?.let { it / 60 }, steps = daily.steps?.toDouble(), hasRecovery = daily.recovery != null)
        val workoutKeys = mutableSetOf<String>()
        for (workout in workouts.sortedWith(compareBy({ it.startTs }, { it.endTs }))) {
            val duration = workout.durationS ?: (workout.endTs - workout.startTs).toDouble()
            val day = dayOf(workout.startTs)
            workoutKeys += "${workout.startTs}|${workout.sport.lowercase(Locale.ROOT)}"
            zoneMinutes(workout.zonesJSON, duration)?.let { zones ->
                val current = byDay[day] ?: Day(day)
                byDay[day] = current.copy(zone13Min = current.zone13Min + zones.first, zone45Min = current.zone45Min + zones.second)
            }
            if (isStrengthSport(workout.sport) && duration > 0) {
                val current = byDay[day] ?: Day(day)
                byDay[day] = current.copy(strengthMin = current.strengthMin + duration / 60)
            }
        }
        for (lift in lifts.sortedBy { it.startTs }) if (lift.endTs > lift.startTs &&
            "${lift.startTs}|${lift.sport.lowercase(Locale.ROOT)}" !in workoutKeys) {
            val day = dayOf(lift.startTs)
            val current = byDay[day] ?: Day(day)
            byDay[day] = current.copy(strengthMin = current.strengthMin + (lift.endTs - lift.startTs).toDouble() / 60)
        }
        for ((day, value) in vo2ByDay) byDay[day] = (byDay[day] ?: Day(day)).copy(vo2max = value)
        for ((day, value) in measuredVO2ByDay) byDay[day] = (byDay[day] ?: Day(day)).copy(measuredVO2max = value)
        for ((day, value) in stepsByDay) if (value > 0) byDay[day] = (byDay[day] ?: Day(day)).copy(steps = value)
        for ((day, value) in consistencyByDay) byDay[day]?.let { byDay[day] = it.copy(sleepConsistency = value) }
        return byDay.values.sortedBy { it.day }
    }

    /** Lab Book body fat overrides imported fat, then imported lean kilograms divided by same-day weight. */
    // Swift twin `Repository.leanMassPoints(labBodyFat:appleBodyFat:leanKg:weightKg:)`.
    fun leanMassPoints(labBodyFat: List<Pair<String, Double>>, bodyFat: List<Pair<String, Double>>,
        leanKg: List<Pair<String, Double>>, weightKg: List<Pair<String, Double>>): List<LeanMassPoint> {
        val result = mutableMapOf<String, Double>()
        val weights = mutableMapOf<String, Double>()
        for ((day, value) in weightKg) if (value > 0) weights[day] = value
        for ((day, value) in leanKg) weights[day]?.takeIf { value > 0 }?.let { result[day] = value / it * 100 }
        for ((day, value) in bodyFat) if (value > 0) result[day] = 100 - value
        for ((day, value) in labBodyFat) if (value > 0) result[day] = 100 - value
        return result.filterValues { it in 40.0..97.0 }.map { LeanMassPoint(it.key, it.value) }.sortedBy { it.day }
    }

    // Swift twin `Repository.vitalityWindowStart(endingOn:days:)`.
    fun windowStart(day: String, days: Int = longWindowDays): String = epochDay(day)?.let { HRVStatus.dayString(it - days + 1) } ?: day
}
