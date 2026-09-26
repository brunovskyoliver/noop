package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Twin of the Swift `VitalityWindowTests`. The oracle values are pasted verbatim from the Swift run. */
class VitalityWindowTest {

    private fun day(epoch: Int): String = LocalDate.ofEpochDay(epoch.toLong()).toString()

    @Test fun expectedVO2maxFollowsPublishedTable() {
        assertEquals(46.0, VitalityEngine.expectedVO2max(20.0, "male"), 0.0)
        assertEquals(38.0, VitalityEngine.expectedVO2max(30.0, "female"), 0.0)
        assertEquals(36.5, VitalityEngine.expectedVO2max(47.5, "male"), 1e-12)
        assertEquals(46.0, VitalityEngine.expectedVO2max(15.0, "male"), 0.0)
        assertEquals(18.0, VitalityEngine.expectedVO2max(110.0, "female"), 0.0)
        assertEquals(41.0, VitalityEngine.expectedVO2max(30.0, "nonbinary"), 0.0)
    }

    @Test fun zoneTimeCurve() {
        fun zones(z13: Double, z45: Double) = VitalityEngine.contributions(
            VitalityEngine.Inputs(chronoAge = 40.0, zone13MinPerWeek = z13, zone45MinPerWeek = z45),
        ).first { it.key == "zones" }.lnHazard
        assertEquals(0.0, zones(150.0, 0.0), 1e-12)
        assertEquals(0.0, zones(100.0, 25.0), 1e-12)
        assertEquals(0.2971036163525209, zones(0.0, 0.0), 1e-12)
        assertEquals(zones(2000.0, 0.0), zones(600.0, 0.0), 1e-12)
        assertTrue(zones(300.0, 30.0) < 0)
    }

    @Test fun zoneMinutesFromJson() {
        val a = VitalityWindow.zoneMinutes("""{"z1":10,"z2":20,"z3":30,"z4":30,"z5":10}""", 3600.0)!!
        assertEquals(36.0, a.first, 1e-9)
        assertEquals(24.0, a.second, 1e-9)
        val b = VitalityWindow.zoneMinutes("""{"zone1":50,"zone4":50}""", 1200.0)!!
        assertEquals(10.0, b.first, 1e-9)
        assertEquals(10.0, b.second, 1e-9)
        assertNull(VitalityWindow.zoneMinutes(null, 600.0))
        assertNull(VitalityWindow.zoneMinutes("""{"z1":0}""", 600.0))
        assertNull(VitalityWindow.zoneMinutes("not json", 600.0))
    }

    @Test fun domainWeights() {
        val w = VitalityEngine.contributions(VitalityEngine.Inputs(
            chronoAge = 40.0, restingHR = 75.0, vo2max = 38.0, expectedVO2max = 45.0, sleepHours = 7.5,
            steps = 9000.0, zone13MinPerWeek = 0.0, zone45MinPerWeek = 0.0,
        )).associate { it.key to it.weight }
        assertEquals(1.0, w["vo2max"]!!, 0.0)
        assertEquals(0.5, w["rhr"]!!, 0.0)
        assertEquals(1.0, w["zones"]!!, 0.0)
        assertEquals(0.5, w["steps"]!!, 0.0)
        assertEquals(1.0, w["sleep"]!!, 0.0)
    }

    @Test fun epochDay() {
        assertEquals(0, VitalityWindow.epochDay("1970-01-01"))
        assertEquals(11_017, VitalityWindow.epochDay("2000-03-01"))
        assertEquals(20_720, VitalityWindow.epochDay("2026-09-24"))
        assertNull(VitalityWindow.epochDay("2026-13-01"))
        assertNull(VitalityWindow.epochDay("garbage"))
        assertEquals("2026-03-29", VitalityWindow.windowStart("2026-09-24"))
    }

    private fun steady(i: Int) = VitalityWindow.Day(
        day = "", restingHR = 60.0, sleepHours = if (i % 2 == 0) 7.2 else 7.8, rmssd = 40.0, steps = 8000.0,
        vo2max = if (i % 7 == 0) 44.0 else null, zone13Min = if (i % 2 == 0) 30.0 else 0.0,
        zone45Min = if (i % 10 == 0) 10.0 else 0.0,
    )

    private fun days(n: Int, end: String, make: (Int) -> VitalityWindow.Day): List<VitalityWindow.Day> {
        val e = VitalityWindow.epochDay(end)!!
        return (0 until n).map { i -> make(i).copy(day = day(e - (n - 1) + i)) }
    }

    @Test fun steadyHabitsPaceOne() {
        val h = VitalityWindow.healthspan(days(180, "2026-09-24", ::steady), "2026-09-24", 35.0, "male")!!
        assertEquals(180, h.coveredDays)
        assertEquals(30, h.recentCoveredDays)
        assertEquals(1.0, h.paceOfAging!!, 1e-6)
        assertEquals(7, h.bodyAge.factorsUsed)
    }

    @Test fun recentChangeMovesPace() {
        val bad = VitalityWindow.Day(day = "", restingHR = 68.0, sleepHours = 6.0, rmssd = 32.0, steps = 4000.0)
        val worse = days(180, "2026-09-24") { i -> if (i < 150) steady(i) else bad }
        val better = days(180, "2026-09-24") { i -> if (i < 150) bad else steady(i) }
        val w = VitalityWindow.healthspan(worse, "2026-09-24", 35.0, "male")!!
        val b = VitalityWindow.healthspan(better, "2026-09-24", 35.0, "male")!!
        assertTrue(w.paceOfAging!! > 1)
        assertTrue(b.paceOfAging!! < 1)
    }

    @Test fun paceNeedsHistory() {
        val short = VitalityWindow.healthspan(days(40, "2026-09-24", ::steady), "2026-09-24", 35.0, "male")!!
        assertNull(short.paceOfAging)
        assertNull(VitalityWindow.healthspan(days(40, "2026-01-01", ::steady), "2026-09-24", 35.0, "male"))
    }

    @Test fun recentGapKeepsLongValue() {
        val d = days(180, "2026-09-24") { i -> if (i >= 150) steady(i).copy(vo2max = null) else steady(i) }
        val h = VitalityWindow.healthspan(d, "2026-09-24", 35.0, "male")!!
        assertEquals(h.bodyAge.factorsUsed, h.recentBodyAge!!.factorsUsed)
        assertEquals(1.0, h.paceOfAging!!, 1e-6)
    }

    @Test fun paceBands() {
        assertEquals(VitalityWindow.PaceBand.REVERSING, VitalityWindow.paceBand(-0.2))
        assertEquals(VitalityWindow.PaceBand.SLOWING, VitalityWindow.paceBand(0.0))
        assertEquals(VitalityWindow.PaceBand.SLOWING, VitalityWindow.paceBand(0.94))
        assertEquals(VitalityWindow.PaceBand.STEADY, VitalityWindow.paceBand(0.95))
        assertEquals(VitalityWindow.PaceBand.STEADY, VitalityWindow.paceBand(1.049))
        assertEquals(VitalityWindow.PaceBand.ACCELERATED, VitalityWindow.paceBand(1.05))
    }

    /** Same history as the Swift `VitalityWindowTests.oracleDays`; values pasted from the Swift run. */
    @Test fun oracleScenario() {
        val end = VitalityWindow.epochDay("2026-09-19")!!
        val days = ArrayList<VitalityWindow.Day>()
        for (i in 0 until 200) {
            if (i % 11 == 5) continue
            val late = i >= 170
            days.add(VitalityWindow.Day(
                day = day(end - 199 + i),
                restingHR = (55 + (i * 7) % 9).toDouble() + (if (late) 3 else 0),
                sleepHours = 6.1 + ((i * 5) % 13).toDouble() / 7.0 - (if (late) 0.4 else 0.0),
                rmssd = if (i % 4 == 0) null else 38 + ((i * 3) % 17).toDouble() / 3.0,
                steps = (6200 + (i * 347) % 5100).toDouble(),
                vo2max = if (i % 7 == 3) 41.3 + (i % 5).toDouble() * 0.37 else null,
                zone13Min = if (i % 3 == 0) 22.5 + (i % 4).toDouble() * 3.3 else 0.0,
                zone45Min = if (i % 5 == 0 && !late) 6.7 else 0.0,
            ))
        }
        val h = VitalityWindow.healthspan(days, "2026-09-19", 38.0, "female")!!
        assertEquals(33.91589056915685, h.bodyAge.bodyAge, 0.0)
        assertEquals(60.21027357710787, h.bodyAge.vitality, 0.0)
        assertEquals(34.42838703817101, h.recentBodyAge!!.bodyAge, 0.0)
        assertEquals(2.024992938028319, h.paceOfAging!!, 0.0)
        assertEquals(164, h.coveredDays)
        assertEquals(27, h.recentCoveredDays)
        val c = h.bodyAge.contributions.associateBy { it.key }
        assertEquals(-0.06, c["rhr"]!!.lnHazard, 0.0); assertEquals(0.5, c["rhr"]!!.weight, 0.0)
        assertEquals(-0.27070683229813625, c["vo2max"]!!.lnHazard, 0.0)
        assertEquals(0.012916376306620032, c["sleep"]!!.lnHazard, 0.0)
        assertEquals(-0.07605684646886696, c["consistency"]!!.lnHazard, 0.0)
        assertEquals(-0.029147286821705424, c["hrv"]!!.lnHazard, 0.0)
        assertEquals(-0.11368819512195116, c["steps"]!!.lnHazard, 0.0)
        assertEquals(0.06973592311234264, c["zones"]!!.lnHazard, 0.0); assertEquals(0.5, c["zones"]!!.weight, 0.0)
        val z = VitalityWindow.zoneMinutes("""{"z1":12.5,"z2":30.1,"z3":20,"z4":7.3,"z5":1.1}""", 2873.0)!!
        assertEquals(29.97496666666667, z.first, 0.0)
        assertEquals(4.022200000000001, z.second, 0.0)
        assertEquals(34.8, VitalityEngine.expectedVO2max(38.0, "female"), 0.0)
        assertEquals(28.509999999999998, VitalityEngine.expectedVO2max(63.3, ""), 0.0)
    }
}
