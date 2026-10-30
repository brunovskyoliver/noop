package com.noop.analytics

import com.noop.data.GravitySample
import com.noop.data.HrSample
import com.noop.data.RrInterval
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.round
import kotlin.math.sqrt

/** Kotlin twin of StrandAnalytics/StressMonitor.swift. Nocturnal HRV is never used to score waking stress. */
object StressMonitor {
    const val epochSeconds = 300L
    const val minEpochHRSamples = 60
    const val baselineWindowDays = 14
    const val minBaselineDays = 4
    const val mediumFloor = 1.0
    const val highFloor = 2.0
    const val wakeHighMarginBPM = 15.0
    const val minNightEpochs = 12
    const val minNightHRSpread = 2.0
    const val minNightLnRMSSDSpread = 0.10
    const val minWakingScoredMinutes = 30
    const val postActivityShadowEpochs = 3
    const val wakeFloorKey = "stress_wake_floor_hr"
    val aggregateKeys = listOf(wakeFloorKey, "stress_night_hr", "stress_night_hr_sd", "stress_night_lnrmssd", "stress_night_lnrmssd_sd")

    data class Interval(val start: Long, val end: Long) {
        // Swift twin `Interval.contains(_:)`.
        fun contains(ts: Long) = ts >= start && ts < end
        val duration get() = max(0L, end - start)
    }
    enum class EpochState { WAKING, SLEEP, ACTIVITY, NO_DATA }
    data class Epoch(val startTs: Long, val state: EpochState, val level: Double?, val meanHR: Double?, val rmssd: Double?, val inMainSleep: Boolean)
    data class WakeReference(val floorHR: Double, val personal: Boolean, val days: Int)
    data class NightAggregate(val hr: Double, val hrSpread: Double, val lnRMSSD: Double?, val lnRMSSDSpread: Double?) {
        fun storedPairs(): Map<String, Double> = buildMap {
            put("stress_night_hr", hr)
            put("stress_night_hr_sd", hrSpread)
            if (lnRMSSD != null && lnRMSSDSpread != null) {
                put("stress_night_lnrmssd", lnRMSSD)
                put("stress_night_lnrmssd_sd", lnRMSSDSpread)
            }
        }
        companion object {
            // Swift twin `NightAggregate.fromStored(_:)`.
            fun fromStored(values: Map<String, Double>): NightAggregate? {
                val hr = values["stress_night_hr"] ?: return null
                val spread = values["stress_night_hr_sd"] ?: return null
                return NightAggregate(hr, spread, values["stress_night_lnrmssd"], values["stress_night_lnrmssd_sd"])
            }
        }
    }
    data class SleepReference(val night: NightAggregate, val personal: Boolean, val nights: Int)
    data class DayInput(
        val day: String, val dayStart: Long, val dayEnd: Long, val tzOffsetSeconds: Long,
        val hr: List<HrSample>, val rr: List<RrInterval>, val gravity: List<GravitySample>,
        val sleepWindows: List<Interval>, val mainSleep: Interval?, val activityWindows: List<Interval>,
    )
    data class DayResult(
        val day: String, val epochs: List<Epoch>, val wake: WakeReference?, val sleep: SleepReference?,
        val summary: StressDaySummary, val wakeFloorAggregate: Double?, val nightAggregate: NightAggregate?,
    ) {
        val latest get() = epochs.lastOrNull { it.level != null }
        fun storedPairs(): Map<String, Double> = buildMap {
            putAll(summary.storedPairs())
            wakeFloorAggregate?.let { put(wakeFloorKey, it) }
            nightAggregate?.let { putAll(it.storedPairs()) }
        }
    }

    // Swift twin `StressMonitor.wakeLevel(meanHR:floorHR:)`.
    fun wakeLevel(meanHR: Double, floorHR: Double): Double {
        val x = ln(2.0) * (2.0 * (meanHR - floorHR) / wakeHighMarginBPM - 1.0)
        return (3.0 / (1.0 + exp(-x))).coerceIn(0.0, 3.0)
    }
    // Swift twin `StressMonitor.sleepZ(meanHR:rmssd:ref:)`.
    fun sleepZ(meanHR: Double, rmssd: Double?, ref: NightAggregate): Double {
        val zHR = (meanHR - ref.hr) / max(ref.hrSpread, minNightHRSpread)
        if (rmssd == null || rmssd <= 0 || ref.lnRMSSD == null || ref.lnRMSSDSpread == null) return zHR
        val zHRV = (ref.lnRMSSD - ln(rmssd)) / max(ref.lnRMSSDSpread, minNightLnRMSSDSpread)
        return (zHR + zHRV) / sqrt(2.0)
    }
    // Swift twin `StressMonitor.sleepLevel(z:)`.
    fun sleepLevel(z: Double): Double {
        val lo = ln(3.0 / 0.4 - 1.0)
        val hi = ln(3.0 / (3.0 - highFloor) - 1.0)
        return (3.0 / (1.0 + exp(-(-lo + (lo + hi) * z / 3.0)))).coerceIn(0.0, 3.0)
    }
    // Swift twin `StressMonitor.wakeReference(priorFloors:todayFloor:)`.
    fun wakeReference(priorFloors: List<Double?>, todayFloor: Double?): WakeReference? {
        val window = priorFloors.takeLast(baselineWindowDays).filterNotNull()
        return if (window.size >= minBaselineDays) WakeReference(median(window), true, window.size)
        else todayFloor?.let { WakeReference(it, false, 0) }
    }
    // Swift twin `StressMonitor.sleepReference(priorNights:tonight:)`.
    fun sleepReference(priorNights: List<NightAggregate?>, tonight: NightAggregate?): SleepReference? {
        val window = priorNights.takeLast(baselineWindowDays).filterNotNull()
        if (window.size < minBaselineDays) return tonight?.let { SleepReference(it, false, 0) }
        val hrv = window.filter { it.lnRMSSD != null && it.lnRMSSDSpread != null }
        val aggregate = NightAggregate(
            median(window.map { it.hr }), median(window.map { it.hrSpread }),
            if (hrv.size >= minBaselineDays) median(hrv.mapNotNull { it.lnRMSSD }) else null,
            if (hrv.size >= minBaselineDays) median(hrv.mapNotNull { it.lnRMSSDSpread }) else null,
        )
        return SleepReference(aggregate, true, window.size)
    }
    private data class Bucket(var sum: Double = 0.0, var count: Int = 0, val rr: MutableList<Double> = ArrayList())
    // Swift twin `StressMonitor.bucket(hr:rr:anchor:range:withRR:)`.
    private fun buckets(hr: List<HrSample>, rr: List<RrInterval>, anchor: Long, range: Interval): Map<Long, Bucket> {
        val out = LinkedHashMap<Long, Bucket>()
        for (s in hr) if (range.contains(s.ts)) {
            val b = out.getOrPut(Math.floorDiv(s.ts - anchor, epochSeconds)) { Bucket() }
            b.sum += s.bpm
            b.count++
        }
        for (r in rr) if (range.contains(r.ts)) {
            out.getOrPut(Math.floorDiv(r.ts - anchor, epochSeconds)) { Bucket() }.rr.add(r.rrMs.toDouble())
        }
        return out
    }
    // Swift twin `StressMonitor.nightAggregate(hr:rr:mainSleep:anchor:)`.
    fun nightAggregate(hr: List<HrSample>, rr: List<RrInterval>, mainSleep: Interval, anchor: Long = mainSleep.start): NightAggregate? {
        val hrs = ArrayList<Double>()
        val lnR = ArrayList<Double>()
        for (b in buckets(hr, rr, anchor, mainSleep).values) if (b.count >= minEpochHRSamples) {
            hrs.add(b.sum / b.count)
            HrvAnalyzer.analyzeRaw(b.rr).rmssd?.takeIf { it > 0 }?.let { lnR.add(ln(it)) }
        }
        if (hrs.size < minNightEpochs) return null
        val hrMed = median(hrs)
        val hrSd = max(1.4826 * median(hrs.map { abs(it - hrMed) }), minNightHRSpread)
        val lnMed = if (lnR.size >= minNightEpochs) median(lnR) else null
        val lnSd = lnMed?.let { m -> max(1.4826 * median(lnR.map { abs(it - m) }), minNightLnRMSSDSpread) }
        return NightAggregate(hrMed, hrSd, lnMed, lnSd)
    }
    // Swift twin `StressMonitor.analyzeDay(_:priorFloors:priorNights:)`.
    fun analyzeDay(input: DayInput, priorFloors: List<Double?>, priorNights: List<NightAggregate?>): DayResult {
        val range = Interval(input.dayStart, max(input.dayStart, input.dayEnd))
        val dayHR = input.hr.filter { range.contains(it.ts) }
        val dayRR = input.rr.filter { range.contains(it.ts) }
        val activity = WorkoutDetector.activitySeries(input.gravity)
        val moving = activity.filter { it.intensity > WorkoutDetector.motionThreshold }
            .map { Math.floorDiv(it.ts - input.dayStart, epochSeconds) }.toSet()
        val calmHR = dayHR.filter { sample ->
            input.sleepWindows.none { it.contains(sample.ts) } && input.mainSleep?.contains(sample.ts) != true &&
                input.activityWindows.none { it.contains(sample.ts) } && Math.floorDiv(sample.ts - input.dayStart, epochSeconds) !in moving
        }
        val floor = DaytimeBaselines.dayDaytimeAggregate(calmHR, dayRR, input.tzOffsetSeconds).hr
        val night = input.mainSleep?.let { nightAggregate(input.hr, input.rr, it, input.dayStart) }
        val wake = wakeReference(priorFloors, floor)
        val sleep = sleepReference(priorNights, night)
        val activeFraction = activity.filter { range.contains(it.ts) }.groupBy { Math.floorDiv(it.ts - input.dayStart, epochSeconds) }
            .mapValues { (_, values) -> values.count { it.intensity > WorkoutDetector.motionThreshold }.toDouble() / values.size }
        val n = ((range.duration + epochSeconds - 1) / epochSeconds).toInt()
        val buckets = buckets(input.hr, input.rr, input.dayStart, range)
        val epochs = ArrayList<Epoch>(n)
        var lastActive: Int? = null
        for (k in 0 until n) {
            val start = input.dayStart + k * epochSeconds
            val mid = start + epochSeconds / 2
            val b = buckets[k.toLong()]
            val mean = b?.takeIf { it.count >= minEpochHRSamples }?.let { it.sum / it.count }
            val inMain = input.mainSleep?.contains(mid) == true
            if (inMain || input.sleepWindows.any { it.contains(mid) }) {
                val rmssd = if (mean != null && sleep != null) HrvAnalyzer.analyzeRaw(b?.rr ?: emptyList()).rmssd else null
                val level = if (mean != null && sleep != null) sleepLevel(sleepZ(mean, rmssd, sleep.night)) else null
                epochs.add(Epoch(start, EpochState.SLEEP, level, mean, rmssd, inMain))
                continue
            }
            val workout = input.activityWindows.any { it.start < start + epochSeconds && it.end > start }
            val ambulatory = (activeFraction[k.toLong()] ?: 0.0) >= DaytimeStress.activityMaskFraction
            if (workout || ambulatory) lastActive = k
            val shadow = !workout && !ambulatory && lastActive != null && k - lastActive <= postActivityShadowEpochs &&
                mean != null && wake != null && mean > wake.floorHR + DaytimeStress.postActivityShadowBpm
            when {
                mean == null -> epochs.add(Epoch(start, EpochState.NO_DATA, null, null, null, false))
                workout || ambulatory || shadow -> epochs.add(Epoch(start, EpochState.ACTIVITY, null, mean, null, false))
                else -> epochs.add(Epoch(start, EpochState.WAKING, wake?.let { wakeLevel(mean, it.floorHR) }, mean, null, false))
            }
        }
        var sleepStress: Double? = null
        if (input.mainSleep != null && sleep != null) {
            val levels = buckets(input.hr, input.rr, input.dayStart, input.mainSleep).values
                .filter { it.count >= minEpochHRSamples }
                .map { sleepLevel(sleepZ(it.sum / it.count, HrvAnalyzer.analyzeRaw(it.rr).rmssd, sleep.night)) }
            if (levels.size >= minNightEpochs && levels.size * epochSeconds * 2 >= input.mainSleep.duration) {
                sleepStress = 100.0 * levels.count { it >= highFloor } / levels.size
            }
        }
        return DayResult(input.day, epochs, wake, sleep, summarize(input.day, epochs, sleepStress), floor, night)
    }
    // Swift twin `StressMonitor.summarize(day:epochs:sleepStressPct:)`.
    fun summarize(day: String, epochs: List<Epoch>, sleepStressPct: Double?): StressDaySummary {
        val levels = epochs.filter { it.state == EpochState.WAKING }.mapNotNull { it.level }
        val enough = levels.size * 5 >= minWakingScoredMinutes
        return StressDaySummary(
            day, if (enough) levels.average() else null,
            if (enough) levels.count { it >= highFloor } * 5 else 0,
            if (enough) levels.count { it >= mediumFloor && it < highFloor } * 5 else 0,
            if (enough) levels.count { it < mediumFloor } * 5 else 0,
            if (enough) levels.size * 5 else 0, sleepStressPct,
        )
    }
    sealed interface LiveReading {
        data class Level(val value: Double) : LiveReading
        data object Active : LiveReading
    }
    // Swift twin `StressMonitor.liveReading(hrWindow:wake:)`.
    fun liveReading(hrWindow: List<Double>, wake: WakeReference): LiveReading? {
        val xs = hrWindow.takeLast(60).filter { it in 30.0..220.0 }
        if (xs.size < 30) return null
        val mean = xs.average()
        return if (mean - wake.floorHR >= 35.0) LiveReading.Active else LiveReading.Level(wakeLevel(mean, wake.floorHR))
    }
    class LiveWindow {
        private val samples = ArrayList<Pair<Long, Double>>()
        private var lastPacket: Long? = null
        // Swift twin `LiveWindow.reset`.
        fun reset() { samples.clear(); lastPacket = null }
        // Swift twin `LiveWindow.expire(at:)`.
        fun expire(ts: Long) {
            lastPacket?.let { if (ts < it || ts - it >= 15) reset() }
            samples.removeAll { ts - it.first >= 60 }
        }
        // Swift twin `LiveWindow.receive(bpm:at:)`.
        fun receive(bpm: Double, ts: Long) {
            if (!bpm.isFinite() || bpm !in 30.0..220.0) return
            expire(ts)
            lastPacket = ts
            if (samples.lastOrNull()?.first == ts) samples.removeAt(samples.lastIndex)
            samples.add(ts to bpm)
        }
        val meanHR get() = samples.takeIf { it.isNotEmpty() }?.map { it.second }?.average()
        // Swift twin `LiveWindow.reading(wake:)`.
        fun reading(wake: WakeReference) = liveReading(samples.map { it.second }, wake)
    }
    // Swift twin `StressMonitor.median(_:)`.
    private fun median(xs: List<Double>): Double {
        if (xs.isEmpty()) return 0.0
        val s = xs.sorted()
        return if (s.size % 2 == 1) s[s.size / 2] else (s[s.size / 2 - 1] + s[s.size / 2]) / 2
    }
}

data class StressDaySummary(
    val day: String, val meanLevel: Double?, val highMin: Int, val medMin: Int, val lowMin: Int,
    val scoredMin: Int, val sleepStressPct: Double?,
) {
    fun storedPairs(): Map<String, Double> = buildMap {
        if (meanLevel != null) {
            put("stress_day", roundSwift(meanLevel * 100) / 100)
            put("stress_high_min", highMin.toDouble())
            put("stress_med_min", medMin.toDouble())
            put("stress_low_min", lowMin.toDouble())
            put("stress_scored_min", scoredMin.toDouble())
        }
        sleepStressPct?.let { put("sleep_stress_pct", roundSwift(it * 10) / 10) }
    }
    companion object {
        val keys = listOf("stress_day", "stress_high_min", "stress_med_min", "stress_low_min", "stress_scored_min", "sleep_stress_pct")
        private fun roundSwift(value: Double) = if (value >= 0) kotlin.math.floor(value + 0.5) else kotlin.math.ceil(value - 0.5)
    }
}
