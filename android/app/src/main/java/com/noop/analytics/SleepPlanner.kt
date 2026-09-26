package com.noop.analytics

import kotlin.math.floor

/**
 * Tonight's bedtime for 100 / 85 / 70 % of your sleep need. Byte-identical twin of the Swift
 * `SleepPlanner.swift`; see that file for the method and sources.
 *
 * need = base + min(33 % of debt, 90) − naps (≤ 60); in bed = goal ÷ efficiency + latency; bedtime = wake −
 * in bed, rounded to 5 min, and never more than 90 min before the usual bedtime (then marked not reachable).
 */
object SleepPlanner {

    data class Inputs(
        val baseNeedHours: Double,
        val debtMin: Double = 0.0,
        val napMin: Double = 0.0,
        val efficiencies: List<Double> = emptyList(),
        val latencyMin: Double = defaultLatencyMin,
        val wakeMinute: Int,
        val recentBedMinutes: List<Int> = emptyList(),
    )

    data class Tier(
        val fraction: Double,
        val goalSleepMin: Double,
        val inBedMin: Double,
        val bedMinute: Int,
        val reachable: Boolean,
        val expectedSleepMin: Double,
    )

    data class Plan(
        val baseNeedMin: Double,
        val debtAddMin: Double,
        val napSubMin: Double,
        val needMin: Double,
        val efficiency: Double,
        val latencyMin: Double,
        val wakeMinute: Int,
        val usualBedMinute: Int?,
        val tiers: List<Tier>,
    ) {
        /** The full-need tier: the bedtime the caffeine cutoff and wind-down plan around. */
        val target: Tier get() = tiers[0]
    }

    val tierFractions = listOf(1.0, 0.85, 0.70)
    const val debtRepayShare = 0.33
    const val maxDebtAddMin = 90.0
    const val maxNapSubMin = 60.0
    const val maxNeedMin = 660.0
    const val defaultEfficiency = 0.88
    const val minEfficiency = 0.75
    const val maxEfficiency = 0.97
    const val minEfficiencyNights = 3
    const val defaultLatencyMin = 15.0
    const val maxInBedMin = 720.0
    const val maxEarlierThanUsualMin = 90
    const val roundToMin = 5

    fun plan(i: Inputs): Plan {
        val base = maxOf(0.0, i.baseNeedHours) * 60
        val debtAdd = minOf(debtRepayShare * maxOf(0.0, i.debtMin), maxDebtAddMin)
        val napSub = minOf(maxOf(0.0, i.napMin), maxNapSubMin)
        val need = minOf(maxOf(0.0, base + debtAdd - napSub), maxNeedMin)
        val eff = efficiency(i.efficiencies)
        val latency = maxOf(0.0, i.latencyMin)
        val wake = wrap(i.wakeMinute)
        val usual = usualBedMinute(i.recentBedMinutes)
        val tiers = tierFractions.map { f ->
            val goal = need * f
            val inBed = minOf(goal / eff + latency, maxInBedMin)
            var bed = wrap(roundTo(wake.toDouble() - inBed))
            var reachable = true
            if (usual != null) {
                val earlier = wrap(usual - bed)
                if (earlier > maxEarlierThanUsualMin && earlier < 720) {
                    bed = wrap(usual - maxEarlierThanUsualMin)
                    reachable = false
                }
            }
            val window = wrap(wake - bed).toDouble()
            Tier(f, goal, inBed, bed, reachable, maxOf(0.0, window - latency) * eff)
        }
        return Plan(base, debtAdd, napSub, need, eff, latency, wake, usual, tiers)
    }

    internal fun efficiency(xs: List<Double>): Double {
        val v = xs.mapNotNull { e ->
            if (!e.isFinite() || e <= 0) null
            else { val f = if (e > 1) e / 100 else e; if (f <= 1) f else null }
        }
        if (v.size < minEfficiencyNights) return defaultEfficiency
        val s = v.sorted(); val n = s.size
        val m = if (n % 2 == 1) s[n / 2] else (s[n / 2 - 1] + s[n / 2]) / 2
        return minOf(maxOf(m, minEfficiency), maxEfficiency)
    }

    internal fun usualBedMinute(xs: List<Int>): Int? {
        if (xs.isEmpty()) return null
        val shifted = xs.map { wrap(it - 720) }.sorted()
        val n = shifted.size
        val m = if (n % 2 == 1) shifted[n / 2].toDouble() else (shifted[n / 2 - 1] + shifted[n / 2]).toDouble() / 2
        return wrap(floor(m + 0.5).toInt() + 720)
    }

    internal fun wrap(m: Int): Int = ((m % 1440) + 1440) % 1440

    internal fun roundTo(x: Double): Int = floor(x / roundToMin + 0.5).toInt() * roundToMin
}
