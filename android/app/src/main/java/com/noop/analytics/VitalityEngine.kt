package com.noop.analytics

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.sqrt

/** Healthspan v2. Independent wellness estimate; mirrors StrandAnalytics/VitalityEngine.swift. */
object VitalityEngine {
    const val yearsPerLnHazard = 10.0
    const val minBodyAge = 18.0
    const val maxBodyAge = 100.0
    const val minFactors = 3
    const val overlapFactor = 0.7
    private const val vitalityPerYear = 2.5

    enum class Pillar { SLEEP, STRAIN, FITNESS }

    enum class Factor(val raw: String, val label: String, val pillar: Pillar) {
        SLEEP_HOURS("sleepHours", "Hours of Sleep", Pillar.SLEEP),
        SLEEP_CONSISTENCY("sleepConsistency", "Sleep Regularity", Pillar.SLEEP),
        ZONE13("zone13", "Time in HR Zones 1-3 (Weekly)", Pillar.STRAIN),
        ZONE45("zone45", "Time in HR Zones 4-5 (Weekly)", Pillar.STRAIN),
        STRENGTH("strength", "Strength Activity Time (Weekly)", Pillar.STRAIN),
        STEPS("steps", "Steps", Pillar.STRAIN),
        VO2MAX("vo2max", "VO₂ Max", Pillar.FITNESS),
        RHR("rhr", "RHR", Pillar.FITNESS),
        LEAN_MASS("leanMass", "Lean Body Mass", Pillar.FITNESS);

        val higherIsBetter: Boolean get() = this != RHR
    }

    /** Consistency and lean mass are percentages; activity time is minutes per week. */
    data class Inputs(
        val chronoAge: Double,
        val sex: String = "",
        val sleepHours: Double? = null,
        val sleepConsistency: Double? = null,
        val zone13MinPerWeek: Double? = null,
        val zone45MinPerWeek: Double? = null,
        val strengthMinPerWeek: Double? = null,
        val steps: Double? = null,
        val vo2max: Double? = null,
        val restingHR: Double? = null,
        val leanMassPct: Double? = null,
    ) {
        // Swift twin `Inputs.value(_:)`.
        fun value(factor: Factor): Double? = when (factor) {
            Factor.SLEEP_HOURS -> sleepHours
            Factor.SLEEP_CONSISTENCY -> sleepConsistency
            Factor.ZONE13 -> zone13MinPerWeek
            Factor.ZONE45 -> zone45MinPerWeek
            Factor.STRENGTH -> strengthMinPerWeek
            Factor.STEPS -> steps
            Factor.VO2MAX -> vo2max
            Factor.RHR -> restingHR
            Factor.LEAN_MASS -> leanMassPct
        }

        // Swift twin `Inputs.set(_:_:)`.
        fun setting(factor: Factor, value: Double?): Inputs = when (factor) {
            Factor.SLEEP_HOURS -> copy(sleepHours = value)
            Factor.SLEEP_CONSISTENCY -> copy(sleepConsistency = value)
            Factor.ZONE13 -> copy(zone13MinPerWeek = value)
            Factor.ZONE45 -> copy(zone45MinPerWeek = value)
            Factor.STRENGTH -> copy(strengthMinPerWeek = value)
            Factor.STEPS -> copy(steps = value)
            Factor.VO2MAX -> copy(vo2max = value)
            Factor.RHR -> copy(restingHR = value)
            Factor.LEAN_MASS -> copy(leanMassPct = value)
        }
    }

    data class Impact(
        val factor: Factor,
        val value: Double?,
        val target: Double,
        val lnHazard: Double,
        val adjustment: Double,
        val years: Double,
    ) {
        val isMissing: Boolean get() = value == null
    }

    /** Compatibility readout for the existing Android health cards; values come from the nine impacts. */
    data class Contribution(val key: String, val label: String, val lnHazard: Double, val weight: Double = 1.0) {
        val ageImpactYears: Double get() = yearsPerLnHazard * weight * lnHazard
    }

    data class Result(
        val chronoAge: Double,
        val bodyAge: Double,
        val ageDelta: Double,
        val vitality: Double,
        val impacts: List<Impact>,
        val factorsUsed: Int,
    ) {
        val contributions: List<Contribution> get() = impacts.filterNot { it.isMissing }.map {
            Contribution(it.factor.raw, it.factor.label, it.lnHazard, it.adjustment)
        }
        val deltaYears: Double get() = ageDelta
    }

    // Swift twin `VitalityEngine.clamp(_:_:_:)`.
    private fun clamp(value: Double, low: Double, high: Double): Double = minOf(high, maxOf(low, value))

    // Swift twin `VitalityEngine.interp(_:_:)`.
    private fun interp(value: Double, knots: List<Pair<Double, Double>>): Double {
        if (value <= knots.first().first) return knots.first().second
        for (index in 1 until knots.size) if (value <= knots[index].first) {
            val (x0, y0) = knots[index - 1]
            val (x1, y1) = knots[index]
            return y0 + (y1 - y0) * (value - x0) / (x1 - x0)
        }
        return knots.last().second
    }

    // Swift twin `VitalityEngine.byAge(_:_:_:_:_:)`.
    private fun byAge(age: Double, age0: Double, young: Double, age1: Double, old: Double): Double =
        interp(age, listOf(age0 to young, age1 to old))

    // Swift twin `VitalityEngine.bySex(_:male:female:)`.
    private fun bySex(sex: String, male: Double, female: Double): Double = when (sex.lowercase(Locale.ROOT)) {
        "male" -> male
        "female" -> female
        else -> (male + female) / 2
    }

    private val vo2RecFemale = doubleArrayOf(40.0, 40.0, 38.0, 36.0, 34.0, 32.0, 30.0, 29.0, 27.0, 26.0, 25.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0)
    private val vo2RecMale = doubleArrayOf(46.0, 46.0, 44.0, 42.0, 40.0, 37.0, 36.0, 34.0, 32.0, 30.0, 29.0, 27.0, 26.0, 25.0, 23.0, 22.0, 21.0)

    fun expectedVO2max(age: Double, sex: String): Double {
        // Swift twin `VitalityEngine.row(_:)`.
        fun row(values: DoubleArray): Double {
            val position = clamp((age - 20) / 5, 0.0, (values.size - 1).toDouble())
            val index = kotlin.math.floor(position).toInt()
            if (index >= values.lastIndex) return values.last()
            return values[index] + (values[index + 1] - values[index]) * (position - index)
        }
        return bySex(sex, row(vo2RecMale), row(vo2RecFemale))
    }

    /** Health-optimised recommendations; age ramps mirror the documented Swift assumptions. */
    // Swift twin `VitalityEngine.target(_:age:sex:)`.
    fun target(factor: Factor, age: Double, sex: String): Double = when (factor) {
        Factor.SLEEP_HOURS -> 7.0
        Factor.SLEEP_CONSISTENCY -> 70.0
        Factor.ZONE13 -> byAge(age, 30.0, 100.0, 70.0, 70.0)
        Factor.ZONE45 -> byAge(age, 30.0, 10.0, 70.0, 7.0)
        Factor.STRENGTH -> 40.0
        Factor.STEPS -> byAge(age, 40.0, 8000.0, 60.0, 5600.0)
        Factor.VO2MAX -> expectedVO2max(age, sex)
        Factor.RHR -> bySex(sex, 60.0, 64.0)
        Factor.LEAN_MASS -> bySex(sex, 80.0, 67.0) - 0.1 * maxOf(0.0, age - 30)
    }

    // Swift twin `VitalityEngine.cSleepHours(_:)`.
    private fun sleepHoursCurve(hours: Double): Double = if (hours < 7) ln(1.12) * (7 - maxOf(hours, 4.0)) else 0.0

    // Swift twin `VitalityEngine.cConsistency(_:)`.
    private fun consistencyCurve(percent: Double): Double {
        val slope = ln(0.80) / 5.1
        return interp(percent, listOf(60.0 to -slope * 10, 70.0 to 0.0, 75.1 to ln(0.80),
            80.9 to ln(0.75), 85.25 to ln(0.72), 90.0 to ln(0.70)))
    }

    // Swift twin `VitalityEngine.cZone13(_:)`.
    private fun zone13Curve(minutes: Double): Double = interp(maxOf(0.0, minutes),
        listOf(0.0 to 0.0, 150.0 to ln(0.80), 300.0 to ln(0.74), 600.0 to ln(0.72)))

    // Swift twin `VitalityEngine.cZone45(_:)`.
    private fun zone45Curve(minutes: Double): Double = interp(maxOf(0.0, minutes),
        listOf(0.0 to 0.0, 15.0 to ln(0.82), 53.6 to ln(0.64)))

    // Swift twin `VitalityEngine.cStrength(_:)`.
    private fun strengthCurve(minutes: Double): Double = interp(maxOf(0.0, minutes),
        listOf(0.0 to 0.0, 40.0 to ln(0.88), 60.0 to ln(0.85), 120.0 to ln(0.83)))

    // Swift twin `VitalityEngine.cSteps(_:age:)`.
    private fun stepsCurve(steps: Double, age: Double): Double {
        val plateau = byAge(age, 40.0, 10901.0, 60.0, 8000.0)
        val value = minOf(maxOf(steps, 2000.0), plateau)
        val slope = ln(0.60) / (5801 - 3553)
        if (value < 3553) return slope * (value - 3553)
        return interp(value, listOf(3553.0 to 0.0, 5801.0 to ln(0.60), 7842.0 to ln(0.55), 10901.0 to ln(0.47)))
    }

    // Swift twin `VitalityEngine.cVO2(_:target:)`.
    private fun vo2Curve(value: Double, target: Double): Double = -ln(0.87) * clamp((target - value) / 3.5, -4.0, 4.0)
    // Swift twin `VitalityEngine.cRHR(_:target:)`.
    private fun restingCurve(value: Double, target: Double): Double = ln(1.09) * (clamp(value, 40.0, 100.0) - target) / 10

    // Swift twin `VitalityEngine.cLeanMass(_:target:age:)`.
    private fun leanMassCurve(value: Double, target: Double, age: Double): Double {
        val slope = ln(1.11) / 10 * if (age >= 60) 0.5 else 1.0
        if (value < target) return slope * (target - maxOf(value, 40.0))
        return -slope * 0.5 * minOf(value - target, 10.0)
    }

    // Swift twin `VitalityEngine.lnHazard(_:value:age:sex:)`.
    fun lnHazard(factor: Factor, value: Double, age: Double, sex: String): Double {
        val neutral = target(factor, age, sex)
        return when (factor) {
            Factor.SLEEP_HOURS -> sleepHoursCurve(value) - sleepHoursCurve(neutral)
            Factor.SLEEP_CONSISTENCY -> consistencyCurve(value) - consistencyCurve(neutral)
            Factor.ZONE13 -> zone13Curve(value) - zone13Curve(neutral)
            Factor.ZONE45 -> zone45Curve(value) - zone45Curve(neutral)
            Factor.STRENGTH -> strengthCurve(value) - strengthCurve(neutral)
            Factor.STEPS -> stepsCurve(value, age) - stepsCurve(neutral, age)
            Factor.VO2MAX -> vo2Curve(value, neutral)
            Factor.RHR -> restingCurve(value, neutral)
            Factor.LEAN_MASS -> leanMassCurve(value, neutral, age)
        }
    }

    private val overlapPairs = listOf(Factor.VO2MAX to Factor.RHR, Factor.STEPS to Factor.ZONE13)

    // Swift twin `VitalityEngine.impacts(_:)`.
    fun impacts(inputs: Inputs): List<Impact> {
        val hazards = Factor.entries.mapNotNull { factor -> inputs.value(factor)?.let {
            factor to lnHazard(factor, it, inputs.chronoAge, inputs.sex)
        } }.toMap()
        val adjustments = mutableMapOf<Factor, Double>()
        for ((first, second) in overlapPairs) {
            val a = hazards[first] ?: continue
            val b = hazards[second] ?: continue
            adjustments[if (abs(b) <= abs(a)) second else first] = overlapFactor
        }
        return Factor.entries.map { factor ->
            val hazard = hazards[factor] ?: 0.0
            val adjustment = adjustments[factor] ?: 1.0
            Impact(factor, inputs.value(factor), target(factor, inputs.chronoAge, inputs.sex),
                hazard, adjustment, yearsPerLnHazard * adjustment * hazard)
        }
    }

    fun contributions(inputs: Inputs): List<Contribution> = impacts(inputs).filterNot { it.isMissing }.map {
        Contribution(it.factor.raw, it.factor.label, it.lnHazard, it.adjustment)
    }

    fun compute(inputs: Inputs): Result? {
        if (inputs.chronoAge <= 0) return null
        val impacts = impacts(inputs)
        val used = impacts.count { !it.isMissing }
        if (used < minFactors) return null
        val sum = impacts.sumOf { it.years }
        val bodyAge = clamp(inputs.chronoAge + sum, minBodyAge, maxBodyAge)
        val delta = bodyAge - inputs.chronoAge
        return Result(inputs.chronoAge, bodyAge, delta, clamp(50 - delta * vitalityPerYear, 0.0, 100.0), impacts, used)
    }

    /** Legacy Rest duration regularity, 0-1. Healthspan uses SleepRegularity percentages. */
    fun sleepConsistency(nightlyHours: List<Double>): Double? {
        val hours = nightlyHours.filter { it > 0 }
        if (hours.size < 3) return null
        val mean = hours.sum() / hours.size
        if (mean <= 0) return null
        val variance = hours.sumOf { (it - mean) * (it - mean) } / hours.size
        return clamp(1 - sqrt(variance) / mean, 0.0, 1.0)
    }
}
