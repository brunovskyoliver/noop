package com.noop.analytics

import java.time.LocalDate
import kotlin.math.sqrt

/** The same optional day inputs as StrandAnalytics.MindDay. Missing wear never becomes zero stress. */
data class BroopMindDay(val day: String, val highStressMin: Double? = null,
    val lowStressMin: Double? = null, val scoredMin: Double? = null, val sleepStressPct: Double? = null,
    val rest: Double? = null, val charge: Double? = null) {
    val hasDaytimeStress: Boolean get() {
        val scored = scoredMin ?: return false
        val high = highStressMin ?: return false
        val low = lowStressMin ?: return false
        return scored.isFinite() && high.isFinite() && low.isFinite() && scored >= 120 && high >= 0 && low >= 0 && high + low <= scored
    }
}

/** Pure Kotlin port of MindEngine.swift and MindCheckIn.swift, with Swift oracle coverage. */
object BroopMindEngine {
    enum class Trend { IMPROVING, STEADY, WORSENING }
    data class Resilience(val score: Double, val level: String, val highShare: Double, val lowShare: Double,
        val nightRecovery: Double?, val loadComponent: Double, val daytimeRecoveryComponent: Double,
        val nightComponent: Double?, val stressDays: Int, val nights: Int, val trend: Trend? = null)
    data class Cumulative(val score: Double, val level: String, val days: Int, val daytimeLoad: Double?,
        val sleepLoad: Double?, val recoveryLoad: Double?, val trend: Trend? = null)
    data class Load(val load: Double, val daytime: Double?, val sleep: Double?, val recovery: Double?)
    enum class Form(val key: String, val count: Int, val range: Int, val maximum: Int, val title: String) {
        PSS4("mind_pss4", 4, 4, 16, "Perceived stress"),
        GAD2("mind_gad2", 2, 3, 6, "Worry"), PHQ2("mind_phq2", 2, 3, 6, "Mood")
    }
    // Swift twin `MindEngine.validPercent(_:)`.
    fun validPercent(x: Double?): Double? = x?.takeIf { it.isFinite() && it in 0.0..100.0 }
    // Swift twin `MindEngine.window(_:asOf:length:)`.
    fun window(days: List<BroopMindDay>, asOf: String, length: Int): List<BroopMindDay> {
        val end = VitalityWindow.epochDay(asOf) ?: return emptyList()
        val unique = mutableMapOf<Int, BroopMindDay>()
        days.forEach { d -> VitalityWindow.epochDay(d.day)?.takeIf { it <= end && it > end - length }?.let { unique[it] = d } }
        return unique.toSortedMap().values.toList()
    }
    // Swift twin `MindEngine.shift(_:by:)`.
    fun shift(day: String, offset: Int): String? = VitalityWindow.epochDay(day)?.let { LocalDate.ofEpochDay(it.toLong() + offset).toString() }
    // Swift twin `CumulativeStressEngine.mean(_:)`.
    private fun mean(values: List<Double>): Double? = if (values.isEmpty()) null else values.sum() / values.size
    // Swift twin `MindEngine.trend(now:before:threshold:higherIsBetter:)`.
    private fun trend(now: Double, before: Double?, threshold: Double, higherBetter: Boolean): Trend? {
        if (before == null) return null
        val delta = if (higherBetter) now - before else before - now
        return if (delta > threshold) Trend.IMPROVING else if (delta < -threshold) Trend.WORSENING else Trend.STEADY
    }
    // Swift twin `ResilienceEngine.level(for:)`.
    fun resilienceLevel(score: Double): String = when {
        score >= 75 -> "Exceptional"; score >= 60 -> "Strong"; score >= 45 -> "Solid"; score >= 30 -> "Adequate"; else -> "Limited"
    }
    // Swift twin `CumulativeStressEngine.level(for:)`.
    fun cumulativeLevel(score: Double): String = when {
        score >= 60 -> "High"; score >= 40 -> "Elevated"; score >= 20 -> "Moderate"; else -> "Low"
    }
    // Swift twin `ResilienceEngine.core(days:asOf:)`.
    private fun resilienceCore(days: List<BroopMindDay>, asOf: String): Resilience? {
        val win = window(days, asOf, 14)
        val stress = win.filter { it.hasDaytimeStress }
        if (stress.size < 7) return null
        val scored = stress.sumOf { it.scoredMin ?: 0.0 }
        if (scored <= 0) return null
        val high = stress.sumOf { maxOf(0.0, it.highStressMin ?: 0.0) } / scored
        val low = stress.sumOf { maxOf(0.0, it.lowStressMin ?: 0.0) } / scored
        val nightValues = win.mapNotNull { d -> mean(listOfNotNull(validPercent(d.rest), validPercent(d.charge)).map { (it / 100).coerceIn(0.0, 1.0) }) }
        val nightMean = if (nightValues.size >= 4) mean(nightValues) else null
        val load = 1 - (high / 0.35).coerceIn(0.0, 1.0)
        val daytime = (low / 0.5).coerceIn(0.0, 1.0)
        val night = nightMean?.let { ((it - 0.30) / (0.85 - 0.30)).coerceIn(0.0, 1.0) }
        var num = 0.30 * load + 0.30 * daytime; var den = 0.30 + 0.30
        if (night != null) { num += 0.40 * night; den += 0.40 }
        val score = 100 * num / den
        return Resilience(score, resilienceLevel(score), high, low, nightMean, load, daytime, night, stress.size, nightValues.size)
    }
    // Swift twin `ResilienceEngine.compute(days:asOf:)`.
    fun resilience(days: List<BroopMindDay>, asOf: String): Resilience? {
        val now = resilienceCore(days, asOf) ?: return null
        val before = shift(asOf, -7)?.let { resilienceCore(days, it)?.score }
        return now.copy(trend = trend(now.score, before, 4.0, true))
    }
    // Swift twin `CumulativeStressEngine.dayLoad(_:)`.
    fun dayLoad(d: BroopMindDay): Load? {
        val daytime = if (d.hasDaytimeStress) ((maxOf(0.0, d.highStressMin ?: 0.0) / (d.scoredMin ?: 1.0)) / 0.40).coerceIn(0.0, 1.0) else null
        val sleep = validPercent(d.sleepStressPct)?.let { (it / 40.0).coerceIn(0.0, 1.0) }
        if (daytime == null && sleep == null) return null
        val recovery = validPercent(d.charge)?.let { ((70.0 - it) / (70.0 - 20.0)).coerceIn(0.0, 1.0) }
        var num = 0.0; var den = 0.0
        if (daytime != null) { num += 0.50 * daytime; den += 0.50 }
        if (sleep != null) { num += 0.25 * sleep; den += 0.25 }
        if (recovery != null) { num += 0.25 * recovery; den += 0.25 }
        return Load(num / den, daytime, sleep, recovery)
    }
    // Swift twin `CumulativeStressEngine.core(days:asOf:)`.
    private fun cumulativeCore(days: List<BroopMindDay>, asOf: String): Cumulative? {
        val loads = window(days, asOf, 31).mapNotNull(::dayLoad)
        if (loads.size < 21) return null
        val score = 100 * (mean(loads.map { it.load }) ?: 0.0)
        return Cumulative(score, cumulativeLevel(score), loads.size, mean(loads.mapNotNull { it.daytime }),
            mean(loads.mapNotNull { it.sleep }), mean(loads.mapNotNull { it.recovery }))
    }
    // Swift twin `CumulativeStressEngine.compute(days:asOf:)`.
    fun cumulative(days: List<BroopMindDay>, asOf: String): Cumulative? {
        val now = cumulativeCore(days, asOf) ?: return null
        val before = shift(asOf, -7)?.let { cumulativeCore(days, it)?.score }
        return now.copy(trend = trend(now.score, before, 3.0, false))
    }
    fun history(days: List<BroopMindDay>, asOf: String, span: Int, resilience: Boolean): List<Pair<String, Double>> =
        (0 until maxOf(0, span)).reversed().mapNotNull { back ->
            val day = shift(asOf, -back) ?: return@mapNotNull null
            val score = if (resilience) resilienceCore(days, day)?.score else cumulativeCore(days, day)?.score
            score?.let { day to it }
        }
    // Swift twin `MindCheckIn.score(_:answers:)`.
    fun score(form: Form, answers: List<Int>): Int? {
        if (answers.size != form.count || answers.any { it !in 0..form.range }) return null
        return answers.mapIndexed { i, value -> if (form == Form.PSS4 && i in 1..2) form.range - value else value }.sum()
    }
    // Swift twin `MindCheckIn.isDue(lastCheckInDay:today:)`.
    fun isDue(lastDay: String?, today: String): Boolean {
        val last = lastDay?.let(VitalityWindow::epochDay) ?: return true
        val now = VitalityWindow.epochDay(today) ?: return false
        return now - last >= 28
    }
    data class Correlation(val r: Double, val n: Int)
    // Swift twin `MindCheckIn.correlate(scores:signal:windowDays:)`.
    fun correlate(scores: List<Pair<String, Double>>, signal: List<Pair<String, Double>>, windowDays: Int): Correlation? {
        if (windowDays <= 0) return null
        val dated = signal.filter { it.second.isFinite() }.toMap().mapNotNull { (day, value) -> VitalityWindow.epochDay(day)?.let { it to value } }
        val pairs = scores.filter { it.second.isFinite() }.toMap().toSortedMap().mapNotNull { (day, value) ->
            val end = VitalityWindow.epochDay(day) ?: return@mapNotNull null
            val xs = dated.filter { it.first <= end && it.first > end - windowDays }.map { it.second }
            mean(xs)?.let { value to it }
        }
        if (pairs.size < 5) return null
        val xMean = pairs.sumOf { it.first } / pairs.size
        val yMean = pairs.sumOf { it.second } / pairs.size
        var xx = 0.0; var yy = 0.0; var xy = 0.0
        pairs.forEach { (x, y) -> xx += (x - xMean) * (x - xMean); yy += (y - yMean) * (y - yMean); xy += (x - xMean) * (y - yMean) }
        if (xx <= 0 || yy <= 0) return null
        return Correlation((xy / (sqrt(xx) * sqrt(yy))).coerceIn(-1.0, 1.0), pairs.size)
    }
}

