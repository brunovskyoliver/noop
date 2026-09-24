package com.noop.analytics

import kotlin.math.abs

// VitalityEngine.kt — 0–100 "Vitality" wellness score + optional "Body Age in years".
// Byte-for-byte mirror of Strand/Packages/StrandAnalytics/Sources/StrandAnalytics/VitalityEngine.swift.
//
// INDEPENDENT implementation of the published method WHOOP's "Healthspan / WHOOP Age" also uses (NOT
// medical advice; a wellness comparison, never a clinical biological age): map each wearable input to its
// published all-cause-mortality hazard ratio vs a population reference, sum the log-hazards with an
// overlap correction (correlated inputs), and convert to a "years of aging" offset via the Gompertz
// mortality-rate doubling time (~8 years per doubling). Body Age = chronological age + Δage; average =
// own age, healthier = younger. Presented with a ±band and a hard "wellness, not a clinical age" rule.
object VitalityEngine {

    const val lnHazardPerYear = 0.6931471805599453 / 8.0   // ln(2)/8 ≈ 0.0866
    const val overlapShrink = 0.75
    const val minBodyAge = 20.0
    const val maxBodyAge = 90.0
    private const val vitalityPerYear = 2.5
    const val minFactors = 3
    const val bandYears = 5.0

    data class Inputs(
        val chronoAge: Double,
        val restingHR: Double? = null,
        val vo2max: Double? = null,
        val expectedVO2max: Double? = null,
        val sleepHours: Double? = null,
        val sleepConsistency: Double? = null,
        val rmssd: Double? = null,
        val rmssdNorm: Double? = null,
        val steps: Double? = null,
        val zone13MinPerWeek: Double? = null,   // workout minutes in HR zones 1–3 (%HRR), per week
        val zone45MinPerWeek: Double? = null,   // workout minutes in HR zones 4–5 (%HRR), per week
    )

    /** [weight] is the within-domain overlap weight (1 for a domain's dominant factor, 0.5 otherwise). */
    data class Contribution(val key: String, val label: String, val lnHazard: Double, val weight: Double = 1.0) {
        /** Years this factor adds to (+) or takes off (−) Body Age after both overlap corrections. */
        val ageImpactYears: Double get() = lnHazard * weight * overlapShrink / lnHazardPerYear
    }

    data class Result(
        val vitality: Double,
        val bodyAge: Double,
        val chronoAge: Double,
        val deltaYears: Double,
        val bandYears: Double,
        val contributions: List<Contribution>,
        val factorsUsed: Int,
    )

    /** Nocturnal RMSSD ~50th-pct by age (ms), piecewise-linear between decade anchors (WHOOP-window
     *  norms). The reference for the HRV factor — a person at the age norm contributes 0. */
    fun rmssdNorm(forAge: Double): Double {
        val anchors = listOf(20.0 to 47.0, 30.0 to 40.0, 40.0 to 33.0, 50.0 to 29.0, 60.0 to 25.0, 70.0 to 22.0, 80.0 to 20.0)
        if (forAge <= anchors.first().first) return anchors.first().second
        if (forAge >= anchors.last().first) return anchors.last().second
        for (i in 1 until anchors.size) {
            if (forAge <= anchors[i].first) {
                val (a0, v0) = anchors[i - 1]; val (a1, v1) = anchors[i]
                return v0 + (v1 - v0) * (forAge - a0) / (a1 - a0)
            }
        }
        return anchors.last().second
    }

    /** Sleep regularity (0–1) from nightly sleep durations (hours): 1 − coefficient of variation,
     *  clamped. < 3 nights → null. */
    fun sleepConsistency(nightlyHours: List<Double>): Double? {
        val xs = nightlyHours.filter { it > 0 }
        if (xs.size < 3) return null
        val mean = xs.sum() / xs.size
        if (mean <= 0) return null
        val variance = xs.sumOf { (it - mean) * (it - mean) } / xs.size
        val cv = kotlin.math.sqrt(variance) / mean
        return (1 - cv).coerceIn(0.0, 1.0)
    }

    /** WHOOP's published minimum-recommended VO₂max by age 20…100 (5-year steps), Healthspan white paper
     *  rev. Sep 2025, Figure 4. Linear between anchors, flat outside; other sex values read the mean. */
    private val vo2RecFemale = doubleArrayOf(40.0, 40.0, 38.0, 36.0, 34.0, 32.0, 30.0, 29.0, 27.0, 26.0, 25.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0)
    private val vo2RecMale = doubleArrayOf(46.0, 46.0, 44.0, 42.0, 40.0, 37.0, 36.0, 34.0, 32.0, 30.0, 29.0, 27.0, 26.0, 25.0, 23.0, 22.0, 21.0)

    fun expectedVO2max(age: Double, sex: String): Double {
        fun interp(row: DoubleArray): Double {
            val pos = ((age - 20) / 5).coerceIn(0.0, (row.size - 1).toDouble())
            val i = kotlin.math.floor(pos).toInt()
            if (i >= row.size - 1) return row[row.size - 1]
            val f = pos - i
            return row[i] + (row[i + 1] - row[i]) * f
        }
        return when (sex.lowercase()) {
            "male" -> interp(vo2RecMale)
            "female" -> interp(vo2RecFemale)
            else -> (interp(vo2RecMale) + interp(vo2RecFemale)) / 2
        }
    }

    /** ln(HR) of activity volume vs none (Arem 2015 JAMA IM), knots at bin midpoints in moderate-equivalent
     *  min/week; linear between, flat past the last. See the Swift twin for the bins. */
    private val activityKnots = listOf(
        0.0 to 0.0, 75.0 to -0.2231435513142097, 225.0 to -0.37106368139083207,
        375.0 to -0.4620354595965587, 600.0 to -0.4942963218147801,
    )
    private const val activityReferenceMin = 150.0

    internal fun activityLnHazard(moderateEquivalentMin: Double): Double {
        val x = maxOf(0.0, moderateEquivalentMin)
        val k = activityKnots
        if (x >= k.last().first) return k.last().second
        for (i in 1 until k.size) {
            if (x <= k[i].first) {
                val (x0, y0) = k[i - 1]; val (x1, y1) = k[i]
                return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
            }
        }
        return k.last().second
    }

    /** Overlapping factors: the largest-magnitude member of a domain counts in full, the rest at half. */
    private val overlapDomains = listOf(listOf("rhr", "vo2max"), listOf("steps", "zones"))

    private fun domainWeighted(contribs: List<Contribution>): List<Contribution> {
        val weights = HashMap<String, Double>()
        for (domain in overlapDomains) {
            val members = contribs.filter { it.key in domain }.sortedWith { a, b ->
                val aa = abs(a.lnHazard); val bb = abs(b.lnHazard)
                if (aa != bb) bb.compareTo(aa) else a.key.compareTo(b.key)
            }
            members.forEachIndexed { i, c -> weights[c.key] = if (i == 0) 1.0 else 0.5 }
        }
        return contribs.map { it.copy(weight = weights[it.key] ?: 1.0) }
    }

    /** Per-factor signed log-hazard vs the population reference (positive ages you, negative protective).
     *  Conservative published per-unit hazard ratios — see the Swift file for citations. */
    fun contributions(inputs: Inputs): List<Contribution> {
        val out = ArrayList<Contribution>()
        inputs.restingHR?.let {
            out.add(Contribution("rhr", "Resting heart rate", ((it - 65) / 10) * 0.100))
        }
        val vo2 = inputs.vo2max; val exp = inputs.expectedVO2max
        if (vo2 != null && exp != null && exp > 0) {
            out.add(Contribution("vo2max", "Cardio fitness", ((exp - vo2) / 3.5).coerceIn(-4.0, 4.0) * 0.130))
        }
        inputs.sleepHours?.let {
            val dev = maxOf(0.0, abs(it - 7.5) - 0.5)
            out.add(Contribution("sleep", "Sleep duration", dev.coerceIn(0.0, 3.0) * 0.110))
        }
        inputs.sleepConsistency?.let {
            out.add(Contribution("consistency", "Sleep regularity", (0.75 - it.coerceIn(0.0, 1.0)) * 0.450))
        }
        val h = inputs.rmssd; val norm = inputs.rmssdNorm
        if (h != null && norm != null && norm > 0) {
            out.add(Contribution("hrv", "Heart-rate variability", ((norm - h) / norm).coerceIn(-1.0, 1.0) * 0.160))
        }
        inputs.steps?.let {
            val deficit = (7000 - it.coerceIn(0.0, 11000.0)) / 1000
            out.add(Contribution("steps", "Daily steps", deficit.coerceIn(-4.0, 4.0) * 0.064))
        }
        val z13 = inputs.zone13MinPerWeek; val z45 = inputs.zone45MinPerWeek
        if (z13 != null && z45 != null) {
            val m = maxOf(0.0, z13) + 2 * maxOf(0.0, z45)
            out.add(Contribution("zones", "Heart-rate zone time",
                activityLnHazard(m) - activityLnHazard(activityReferenceMin)))
        }
        return domainWeighted(out)
    }

    /** Full Vitality + Body Age. Returns null until at least [minFactors] inputs are present. */
    fun compute(inputs: Inputs): Result? {
        if (inputs.chronoAge <= 0) return null
        val contribs = contributions(inputs)
        if (contribs.size < minFactors) return null
        var sum = 0.0
        for (c in contribs) sum += c.lnHazard * c.weight
        val sumLn = sum * overlapShrink
        val deltaAge = sumLn / lnHazardPerYear
        val bodyAge = (inputs.chronoAge + deltaAge).coerceIn(minBodyAge, maxBodyAge)
        val delta = inputs.chronoAge - bodyAge
        val vitality = (50 + delta * vitalityPerYear).coerceIn(0.0, 100.0)
        return Result(vitality, bodyAge, inputs.chronoAge, delta, bandYears, contribs, contribs.size)
    }
}
