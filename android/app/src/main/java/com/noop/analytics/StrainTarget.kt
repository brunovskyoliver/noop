package com.noop.analytics

/** Exact target-band and minutes-to-target twin of StrandAnalytics/StrainTarget.swift. */
object StrainTarget {
    enum class Goal(val raw: String, val shift21: Double) {
        RESTORE("restore", -3.0), MAINTAIN("maintain", 0.0), BUILD("build", 2.0);
        companion object { fun fromRaw(raw: String?): Goal = entries.firstOrNull { it.raw == raw } ?: MAINTAIN }
    }
    enum class Zone { RESTORING, OPTIMAL, OVERREACHING }
    const val lowerIntercept21 = 1.75
    const val lowerSlope21 = 0.15
    const val upperIntercept21 = 8.0
    const val upperSlope21 = 0.12
    const val debtFreeMinutes = 60.0
    const val debtPerHour21 = 0.5
    const val maxDebtShift21 = 2.0
    val illnessCap21 = 4.0..10.0
    const val minWidth21 = 1.0
    const val minLower21 = 1.0
    private const val per21 = StrainScorer.maxStrain / 21

    data class Inputs(val charge: Double?, val sleepDebtMin: Double? = null, val illness: Boolean = false,
        val goal: Goal = Goal.MAINTAIN)
    data class Band(val lower: Double, val upper: Double) {
        // Swift twin `Band.zone(effort:)`.
        fun zone(effort: Double): Zone = if (effort < lower) Zone.RESTORING else if (effort > upper) Zone.OVERREACHING else Zone.OPTIMAL
    }
    // Swift twin `StrainTarget.band(_:)`.
    fun band(inputs: Inputs): Band? {
        val value = inputs.charge?.takeIf(Double::isFinite) ?: return null
        val charge = value.coerceIn(0.0, 100.0)
        var lo = lowerIntercept21 + lowerSlope21 * charge
        var hi = upperIntercept21 + upperSlope21 * charge
        val debt = inputs.sleepDebtMin
        if (debt != null && debt > debtFreeMinutes) {
            val shift = minOf(maxDebtShift21, (debt - debtFreeMinutes) / 60 * debtPerHour21)
            lo -= shift; hi -= shift
        }
        if (inputs.illness) { lo = minOf(lo, illnessCap21.start); hi = minOf(hi, illnessCap21.endInclusive) }
        lo += inputs.goal.shift21; hi += inputs.goal.shift21
        lo = minOf(maxOf(minLower21, lo), 21 - minWidth21)
        hi = minOf(21.0, maxOf(hi, lo + minWidth21))
        return Band(lo * per21, hi * per21)
    }
    // Swift twin `StrainTarget.minutesToReach(targetEffort:currentEffort:trimpPerMinute:denominator:)`.
    fun minutesToReach(targetEffort: Double, currentEffort: Double, trimpPerMinute: Double,
        denominator: Double = StrainScorer.strainDenominator): Double? {
        val needed = StrainScorer.strainToTrimp(targetEffort, denominator) - StrainScorer.strainToTrimp(currentEffort, denominator)
        if (needed <= 0) return 0.0
        if (trimpPerMinute <= 0 || !trimpPerMinute.isFinite()) return null
        return needed / trimpPerMinute
    }
    // Swift twin `StrainTarget.edwardsTrimpPerMinute(bpm:restingHR:maxHR:)`.
    fun edwardsTrimpPerMinute(bpm: Double, restingHR: Double, maxHR: Double): Double =
        if (maxHR > restingHR) StrainScorer.zoneWeight(bpm, restingHR, maxHR - restingHR).toDouble() else 0.0
}
