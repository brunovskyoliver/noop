package com.noop.analytics

import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * A 7-night HRV status against your usual range (Garmin-style band). Byte-identical twin of the Swift
 * `HRVStatus.swift`; see that file for the method and sources.
 *
 * ln RMSSD; short window = last 7 calendar days (≥3 valid nights); usual range = the 60 calendar days
 * before it (≥21 valid nights, one ±3 SD winsorising pass, SD floor 0.08). Bands: balanced within ±0.5 SD,
 * above over +0.5 SD, below under −0.5 SD, low under −1.0 SD. Newest night more than 3 days old → no status.
 */
object HRVStatus {

    enum class Band { BALANCED, ABOVE, BELOW, LOW }

    data class Night(val day: String, val rmssd: Double?)

    data class Reading(
        val band: Band,
        val mean7Ms: Double,
        val usualLowMs: Double,
        val usualHighMs: Double,
        val lowMs: Double,
        val shortNights: Int,
        val baselineNights: Int,
        val mayReflectFlaggedDays: Boolean,
    ) {
        val tentative: Boolean get() = shortNights < solidShortNights
    }

    sealed class Outcome {
        data class Calibrating(val baselineNights: Int) : Outcome()
        object NoRecentData : Outcome()
        data class Status(val reading: Reading) : Outcome()
    }

    const val shortDays = 7
    const val baselineDays = 60
    const val minShortNights = 3
    const val solidShortNights = 5
    const val minBaselineNights = 21
    const val staleDays = 3
    const val usualK = 0.5
    const val lowK = 1.0
    const val sdFloor = 0.08
    const val winsorK = 3.0

    fun evaluate(nights: List<Night>, asOf: String, flaggedDays: Set<String> = emptySet()): Outcome {
        val end = VitalityWindow.epochDay(asOf) ?: return Outcome.Calibrating(0)
        val cfg = Baselines.hrvCfg
        val short = ArrayList<Double>(); val base = ArrayList<Double>()
        var newest: Int? = null
        var flaggedInShort = false
        for (n in nights.sortedBy { it.day }) {
            val e = VitalityWindow.epochDay(n.day) ?: continue
            val v = n.rmssd ?: continue
            if (e > end || v < cfg.minVal || v > cfg.maxVal) continue
            val l = ln(v)
            if (e > end - shortDays) {
                short.add(l)
                newest = e
                if (n.day in flaggedDays) flaggedInShort = true
            } else if (e > end - shortDays - baselineDays && n.day !in flaggedDays) {
                base.add(l)
            }
        }
        if (base.size < minBaselineNights) return Outcome.Calibrating(base.size)
        val last = newest
        if (last == null || end - last > staleDays || short.size < minShortNights) return Outcome.NoRecentData
        val (mu, sigma) = winsorisedMeanSD(base)
        val m = mean(short)
        val band = when {
            m > mu + usualK * sigma -> Band.ABOVE
            m >= mu - usualK * sigma -> Band.BALANCED
            m >= mu - lowK * sigma -> Band.BELOW
            else -> Band.LOW
        }
        return Outcome.Status(Reading(
            band, exp(m), exp(mu - usualK * sigma), exp(mu + usualK * sigma), exp(mu - lowK * sigma),
            short.size, base.size, flaggedInShort,
        ))
    }

    /** The status for each of the last [days] days ending on [asOf], oldest first. */
    fun history(nights: List<Night>, asOf: String, days: Int, flaggedDays: Set<String> = emptySet()):
        List<Pair<String, Outcome>> {
        val end = VitalityWindow.epochDay(asOf) ?: return emptyList()
        if (days <= 0) return emptyList()
        return (0 until days).map { i ->
            val d = dayString(end - (days - 1) + i)
            d to evaluate(nights, d, flaggedDays)
        }
    }

    internal fun mean(xs: List<Double>): Double {
        var s = 0.0
        for (x in xs) s += x
        return s / xs.size
    }

    internal fun sampleSD(xs: List<Double>, m: Double): Double {
        if (xs.size < 2) return 0.0
        var s = 0.0
        for (x in xs) s += (x - m) * (x - m)
        return sqrt(s / (xs.size - 1))
    }

    internal fun winsorisedMeanSD(xs: List<Double>): Pair<Double, Double> {
        val m0 = mean(xs)
        val s0 = sampleSD(xs, m0)
        val lo = m0 - winsorK * s0; val hi = m0 + winsorK * s0
        val w = xs.map { minOf(hi, maxOf(lo, it)) }
        val m = mean(w)
        return Pair(m, maxOf(sampleSD(w, m), sdFloor))
    }

    fun dayString(epochDay: Int): String = java.time.LocalDate.ofEpochDay(epochDay.toLong()).toString()
}
