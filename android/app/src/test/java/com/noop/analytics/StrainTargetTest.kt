package com.noop.analytics

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StrainTargetTest {
    /** Literal stdout from the actual Swift StrainTarget.swift, compiled standalone with exact scorer dependencies. */
    @Test fun targetBandsAndMinutesMatchSwiftOracle() {
        val output = mutableListOf<String>()
        for (goal in StrainTarget.Goal.entries) for (charge in listOf(17.0, 50.0, 83.0)) for (context in 0..3) {
            val debt = if (context == 0) null else listOf(0.0, 60.0, 180.0, 480.0)[context]
            val band = StrainTarget.band(StrainTarget.Inputs(charge, debt, context == 3, goal))!!
            output += String.format(Locale.US, "%s|%.0f|%d|%.12f|%.12f", goal.raw, charge, context, band.lower, band.upper)
        }
        for (charge in listOf(-100.0, 0.0, 100.0, 200.0)) {
            val band = StrainTarget.band(StrainTarget.Inputs(charge))!!
            output += String.format(Locale.US, "edge|%.0f|%.12f|%.12f", charge, band.lower, band.upper)
        }
        for (rate in listOf(0.0, 1.0, 3.0, 5.0)) {
            val value = StrainTarget.minutesToReach(50.0, 25.0, rate)
            output += "minutes|${rate.toInt()}|" + (value?.let { String.format(Locale.US, "%.9f", it) } ?: "nil")
        }
        for (bpm in listOf(60.0, 109.0, 110.0, 120.0, 130.0, 140.0, 150.0, 160.0, 170.0, 180.0)) {
            output += "rate|${bpm.toInt()}|${StrainTarget.edwardsTrimpPerMinute(bpm, 60.0, 180.0).toInt()}"
        }
        assertEquals(SWIFT_ORACLE.trimIndent(), output.joinToString("\n"))
    }

    @Test fun unknownChargeNeverInventsTargetAndEveryIntegerChargeHasMonotonicPositiveBand() {
        assertNull(StrainTarget.band(StrainTarget.Inputs(null)))
        assertNull(StrainTarget.band(StrainTarget.Inputs(Double.NaN)))
        assertNull(StrainTarget.band(StrainTarget.Inputs(Double.POSITIVE_INFINITY)))
        for (goal in StrainTarget.Goal.entries) {
            val bands = (0..100).map { StrainTarget.band(StrainTarget.Inputs(it.toDouble(), goal = goal))!! }
            assertTrue(bands.all { it.lower > 0 && it.upper <= 100 && it.upper - it.lower >= 100.0 / 21 - 1e-12 })
            assertTrue(bands.zipWithNext().all { (a, b) -> b.lower >= a.lower && b.upper >= a.upper })
            bands.forEach { band ->
                assertEquals(StrainTarget.Zone.OPTIMAL, band.zone(band.lower))
                assertEquals(StrainTarget.Zone.OPTIMAL, band.zone(band.upper))
                assertEquals(StrainTarget.Zone.RESTORING, band.zone(band.lower - 1))
                assertEquals(StrainTarget.Zone.OVERREACHING, band.zone(band.upper + 1))
            }
        }
        assertEquals(0.0, StrainTarget.minutesToReach(25.0, 50.0, 0.0)!!, 0.0)
    }

    companion object {
        private val SWIFT_ORACLE = """
            restore|17|0|6.190476190476|33.523809523810
            restore|17|1|6.190476190476|33.523809523810
            restore|17|2|4.761904761905|28.761904761905
            restore|17|3|4.761904761905|24.000000000000
            restore|50|0|29.761904761905|52.380952380952
            restore|50|1|29.761904761905|52.380952380952
            restore|50|2|25.000000000000|47.619047619048
            restore|50|3|4.761904761905|33.333333333333
            restore|83|0|53.333333333333|71.238095238095
            restore|83|1|53.333333333333|71.238095238095
            restore|83|2|48.571428571429|66.476190476190
            restore|83|3|4.761904761905|33.333333333333
            maintain|17|0|20.476190476190|47.809523809524
            maintain|17|1|20.476190476190|47.809523809524
            maintain|17|2|15.714285714286|43.047619047619
            maintain|17|3|10.952380952381|38.285714285714
            maintain|50|0|44.047619047619|66.666666666667
            maintain|50|1|44.047619047619|66.666666666667
            maintain|50|2|39.285714285714|61.904761904762
            maintain|50|3|19.047619047619|47.619047619048
            maintain|83|0|67.619047619048|85.523809523810
            maintain|83|1|67.619047619048|85.523809523810
            maintain|83|2|62.857142857143|80.761904761905
            maintain|83|3|19.047619047619|47.619047619048
            build|17|0|30.000000000000|57.333333333333
            build|17|1|30.000000000000|57.333333333333
            build|17|2|25.238095238095|52.571428571429
            build|17|3|20.476190476190|47.809523809524
            build|50|0|53.571428571429|76.190476190476
            build|50|1|53.571428571429|76.190476190476
            build|50|2|48.809523809524|71.428571428571
            build|50|3|28.571428571429|57.142857142857
            build|83|0|77.142857142857|95.047619047619
            build|83|1|77.142857142857|95.047619047619
            build|83|2|72.380952380952|90.285714285714
            build|83|3|28.571428571429|57.142857142857
            edge|-100|8.333333333333|38.095238095238
            edge|0|8.333333333333|38.095238095238
            edge|100|79.761904761905|95.238095238095
            edge|200|79.761904761905|95.238095238095
            minutes|0|nil
            minutes|1|75.646827562
            minutes|3|25.215609187
            minutes|5|15.129365512
            rate|60|0
            rate|109|0
            rate|110|0
            rate|120|1
            rate|130|1
            rate|140|2
            rate|150|3
            rate|160|4
            rate|170|5
            rate|180|5
        """
    }
}
