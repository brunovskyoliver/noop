package com.noop.analytics

/** Direct port of EnergyReservoir.swift. Integration consumes calibrated Stress Monitor epochs. */
object BroopEnergyEngine {
    const val epochSeconds = 300L
    const val seedLevel = 50.0
    enum class State { SLEEP, WAKING, ACTIVITY, NO_DATA }
    enum class Kind { SLEEP, REST, AWAKE, STRESS, ACTIVITY, GAP }
    data class Epoch(val startTs: Long, val state: State, val level: Double?, val meanHR: Double?, val inMainSleep: Boolean)
    data class DayInput(val day: String, val epochs: List<Epoch>, val wakePersonal: Boolean, val sleepPersonal: Boolean)
    data class HeartProfile(val restingHR: Double, val maxHR: Double)
    data class Point(val ts: Long, val level: Double, val kind: Kind)
    data class Step(val level: Double, val kind: Kind, val charge: Double = 0.0,
        val stress: Double = 0.0, val activity: Double = 0.0, val baseline: Double = 0.0)
    data class Summary(val day: String, val start: Double, val end: Double, val wake: Double?,
        val peak: Double, val low: Double, val charged: Double, val drainStress: Double,
        val drainActivity: Double, val drainBaseline: Double, val seeded: Boolean) {
        val drained: Double get() = drainStress + drainActivity + drainBaseline
        fun storedPairs(): List<Pair<String, Double>> {
            // Swift .rounded() breaks exact half ties away from zero. All levels are non-negative.
            // Swift twin `EnergyDaySummary.r(_:)`.
            fun rounded(v: Double): Double = kotlin.math.floor(v * 100 + 0.5) / 100
            val result = mutableListOf("energy_start" to rounded(start), "energy_end" to rounded(end),
                "energy_peak" to rounded(peak), "energy_low" to rounded(low), "energy_charged" to rounded(charged),
                "energy_drain_stress" to rounded(drainStress), "energy_drain_activity" to rounded(drainActivity),
                "energy_drain_baseline" to rounded(drainBaseline), "energy_seeded" to if (seeded) 1.0 else 0.0)
            wake?.let { result += "energy_wake" to rounded(it) }
            return result
        }
    }
    data class DayResult(val day: String, val points: List<Point>, val summary: Summary) {
        val current: Double? get() = points.lastOrNull()?.level
    }
    data class Now(val level: Double, val live: Boolean)
    // Swift twin `EnergyNow.resolve(day:liveStress:heart:now:)`.
    fun now(day: DayResult?, liveStress: Double?, heart: HeartProfile, nowTs: Long): Now? {
        val last = day?.points?.lastOrNull() ?: return null
        val minutes = (nowTs - last.ts) / 60.0
        if (liveStress == null || minutes <= 0) return Now(last.level, false)
        return Now(projectNow(last.level, minutes, liveStress, heart), true)
    }
    val keys = listOf("energy_start", "energy_end", "energy_wake", "energy_peak", "energy_low", "energy_charged",
        "energy_drain_stress", "energy_drain_activity", "energy_drain_baseline", "energy_seeded")

    // Swift twin `EnergyReservoir.step(level:epoch:restRun:heart:minutes:)`.
    fun step(e: Double, epoch: Epoch, restRun: Int, heart: HeartProfile, minutes: Double = 5.0): Step {
        val h = minutes / 60
        return when (epoch.state) {
            State.SLEEP -> {
                val l = epoch.level ?: return Step(e, Kind.GAP)
                val q = ((2.0 - l) / (2.0 - 0.4)).coerceIn(0.0, 1.0)
                val gain = 0.25 * q * (100 - e) * h
                Step(minOf(100.0, e + gain), Kind.SLEEP, charge = gain)
            }
            State.WAKING -> {
                val l = epoch.level ?: return Step(e, Kind.GAP)
                val base = 2.0 * h
                val stress = 6.0 * maxOf(0.0, l - 1) * h
                val gain = if (l < 1.0 && restRun >= 2) 0.08 * (100 - e) * h else 0.0
                val kind = if (gain > 0) Kind.REST else if (l >= 1.0) Kind.STRESS else Kind.AWAKE
                Step((e + gain - base - stress).coerceIn(0.0, 100.0), kind, gain, stress, baseline = base)
            }
            State.ACTIVITY -> {
                val hr = epoch.meanHR ?: return Step(e, Kind.GAP)
                if (heart.maxHR <= heart.restingHR) return Step(e, Kind.GAP)
                val weight = com.noop.analytics.StrainScorer.zoneWeight(hr, heart.restingHR, heart.maxHR - heart.restingHR).toDouble()
                val activity = 0.1 * weight * minutes
                val base = 2.0 * h
                Step((e - activity - base).coerceIn(0.0, 100.0), Kind.ACTIVITY, activity = activity, baseline = base)
            }
            State.NO_DATA -> Step(e, Kind.GAP)
        }
    }

    // Swift twin `EnergyReservoir.day(_:startLevel:heart:)`.
    fun day(stress: DayInput, startLevel: Double?, heart: HeartProfile): DayResult? {
        if (!stress.wakePersonal || !stress.sleepPersonal) return null
        val start = (startLevel ?: seedLevel).coerceIn(0.0, 100.0)
        var e = start
        var charged = 0.0; var dStress = 0.0; var dAct = 0.0; var dBase = 0.0
        var peak = start; var low = start; var restRun = 0; var wake: Double? = null; var sawMain = false
        val points = stress.epochs.map { epoch ->
            restRun = if (epoch.state == State.WAKING && epoch.level?.let { it < 1.0 } == true) restRun + 1 else 0
            val before = e
            val step = step(e, epoch, restRun, heart)
            e = step.level
            val delta = e - before
            if (delta > 0) charged += delta
            val spent = step.stress + step.activity + step.baseline
            if (delta < 0 && spent > 0) {
                val f = -delta / spent
                dStress += step.stress * f; dAct += step.activity * f; dBase += step.baseline * f
            }
            if (epoch.inMainSleep) sawMain = true else if (sawMain && wake == null) wake = before
            peak = maxOf(peak, e); low = minOf(low, e)
            Point(epoch.startTs + epochSeconds, e, step.kind)
        }
        if (sawMain && wake == null) wake = e
        return DayResult(stress.day, points, Summary(stress.day, start, e, wake, peak, low, charged,
            dStress, dAct, dBase, startLevel == null))
    }

    // Swift twin `EnergyReservoir.projectNow(level:minutesSinceLastEpoch:liveLevel:heart:)`.
    fun projectNow(level: Double, minutesSinceLastEpoch: Double, liveLevel: Double?, heart: HeartProfile): Double {
        if (liveLevel == null || minutesSinceLastEpoch <= 0) return level
        return step(level, Epoch(0, State.WAKING, liveLevel, null, false), 0, heart,
            minOf(minutesSinceLastEpoch, 30.0)).level
    }

    // Swift twin `EnergyDaySummary.fromStored(day:values:)`.
    fun fromStored(day: String, values: Map<String, Double>): Summary? {
        return Summary(day,
        values["energy_start"] ?: return null, values["energy_end"] ?: return null,
        values["energy_wake"], values["energy_peak"] ?: return null, values["energy_low"] ?: return null,
        values["energy_charged"] ?: return null, values["energy_drain_stress"] ?: 0.0,
        values["energy_drain_activity"] ?: 0.0, values["energy_drain_baseline"] ?: 0.0,
        (values["energy_seeded"] ?: 0.0) > 0)
    }

    fun fromStress(stress: StressMonitor.DayResult, startLevel: Double?, heart: HeartProfile): DayResult? = day(
        DayInput(stress.day, stress.epochs.map { epoch ->
            Epoch(epoch.startTs, State.valueOf(epoch.state.name), epoch.level, epoch.meanHR, epoch.inMainSleep)
        }, stress.wake?.personal == true, stress.sleep?.personal == true), startLevel, heart,
    )
}

