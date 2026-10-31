package com.noop.analytics

import com.noop.data.DailyMetric
import kotlin.math.floor
import kotlin.math.max

/** Kotlin twin of StrandAnalytics/RestPerformanceV2.swift; missing measured inputs lose their weight. */
object RestPerformanceV2 {
    const val enabledKey = "noop.restV2Enabled"
    const val hoursVsNeedKey = "rest_hours_vs_need_pct"
    const val consistencyKey = "rest_consistency_pct"
    data class Parts(val sufficiency: Double, val consistency: Double?, val efficiency: Double, val sleepStress: Double?)
    // Swift twin `RestV2.sleepStressCredit(pct:)`.
    fun sleepStressCredit(pct: Double) = (1.0 - pct / 30.0).coerceIn(0.0, 1.0)
    // Swift twin `RestV2.parts(tstSeconds:efficiency:needHours:consistency:sleepStressPct:)`.
    fun parts(tstSeconds: Double, efficiency: Double, needHours: Double, consistency: Double?, sleepStressPct: Double?) = Parts(
        (tstSeconds / (max(needHours, 0.1) * 3600)).coerceIn(0.0, 1.0),
        consistency?.coerceIn(0.0, 1.0), efficiency.coerceIn(0.0, 1.0), sleepStressPct?.let(::sleepStressCredit),
    )
    // Swift twin `RestV2.composite(_:)`.
    fun composite(parts: Parts): Double {
        var weight = 0.55 + 0.15
        var sum = 0.55 * parts.sufficiency + 0.15 * parts.efficiency
        parts.consistency?.let { sum += 0.15 * it; weight += 0.15 }
        parts.sleepStress?.let { sum += 0.15 * it; weight += 0.15 }
        return floor(sum / weight * 10000 + 0.5) / 100
    }
    // Swift twin `RestV2.parts(daily:needHours:consistency:sleepStressPct:)`.
    fun parts(daily: DailyMetric, needHours: Double = RestScorer.defaultSleepNeedHours, consistency: Double? = null, sleepStressPct: Double? = null): Parts? {
        val tst = daily.totalSleepMin?.takeIf { it > 0 } ?: return null
        val efficiency = daily.efficiency ?: return null
        return parts(tst * 60, if (efficiency > 1) efficiency / 100 else efficiency, needHours, consistency, sleepStressPct)
    }
    // Swift twin `RestV2.composite(daily:needHours:consistency:sleepStressPct:)`.
    fun composite(daily: DailyMetric, needHours: Double = RestScorer.defaultSleepNeedHours, consistency: Double? = null, sleepStressPct: Double? = null): Double? =
        parts(daily, needHours, consistency, sleepStressPct)?.let(::composite)
}
