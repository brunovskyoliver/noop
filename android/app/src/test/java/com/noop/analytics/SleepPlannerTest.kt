package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Twin of Swift `SleepPlannerTests`; oracle values pasted from the Swift run. */
class SleepPlannerTest {

    @Test fun baselinePlan() {
        val p = SleepPlanner.plan(SleepPlanner.Inputs(baseNeedHours = 8.0, wakeMinute = 7 * 60))
        assertEquals(480.0, p.needMin, 0.0)
        assertEquals(21 * 60 + 40, p.target.bedMinute)
        assertTrue(p.tiers.all { it.reachable })
    }

    @Test fun needBreakdownCaps() {
        val big = SleepPlanner.plan(SleepPlanner.Inputs(8.0, debtMin = 600.0, napMin = 200.0, wakeMinute = 420))
        assertEquals(90.0, big.debtAddMin, 0.0)
        assertEquals(60.0, big.napSubMin, 0.0)
    }

    @Test fun efficiencyAndUsualBedtime() {
        assertEquals(0.88, SleepPlanner.efficiency(listOf(0.9, 0.8)), 0.0)
        assertEquals(0.85, SleepPlanner.efficiency(listOf(90.0, 80.0, 85.0)), 1e-12)
        assertEquals(23 * 60 + 50, SleepPlanner.usualBedMinute(listOf(23 * 60 + 30, 10, 23 * 60 + 50)))
        assertEquals(0, SleepPlanner.usualBedMinute(listOf(23 * 60 + 30, 30)))
        assertNull(SleepPlanner.usualBedMinute(emptyList()))
    }

    @Test fun guardCapsTooEarlyBedtime() {
        val p = SleepPlanner.plan(SleepPlanner.Inputs(8.0, wakeMinute = 420, recentBedMinutes = listOf(30, 30, 30)))
        assertEquals(23 * 60, p.target.bedMinute)
        assertFalse(p.target.reachable)
        assertEquals(409.2, p.target.expectedSleepMin, 1e-9)
    }

    @Test fun earlyWakeWraps() {
        assertEquals(18 * 60 + 40, SleepPlanner.plan(SleepPlanner.Inputs(8.0, wakeMinute = 240)).target.bedMinute)
    }

    @Test fun oracle() {
        val p = SleepPlanner.plan(SleepPlanner.Inputs(
            baseNeedHours = 8.25, debtMin = 73.5, napMin = 12.0, efficiencies = listOf(0.91, 87.0, 0.84, 0.9, 0.86),
            latencyMin = 20.0, wakeMinute = 6 * 60 + 45,
            recentBedMinutes = listOf(23 * 60 + 10, 23 * 60 + 55, 22 * 60 + 40, 5, 23 * 60 + 20),
        ))
        assertEquals(507.255, p.needMin, 0.0)
        assertEquals(0.87, p.efficiency, 0.0)
        assertEquals(23 * 60 + 20, p.usualBedMinute)
        assertEquals(listOf(21 * 60 + 50, 22 * 60 + 10, 23 * 60 + 35), p.tiers.map { it.bedMinute })
        assertEquals(listOf(false, true, true), p.tiers.map { it.reachable })
        assertEquals(listOf(603.051724137931, 515.5939655172414, 428.1362068965517), p.tiers.map { it.inBedMin })
    }
}
