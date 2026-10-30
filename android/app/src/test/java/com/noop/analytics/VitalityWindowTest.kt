package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.WorkoutRow
import org.junit.Assert.*
import org.junit.Test

class VitalityWindowTest {
    private val end = VitalityWindow.epochDay("2026-10-18")!!
    private fun day(offset: Int, recovery: Boolean = true) = VitalityWindow.Day(
        HRVStatus.dayString(end - offset), restingHR = 60.0, sleepHours = 7.0,
        steps = 8000.0, hasRecovery = recovery,
    )

    @Test fun gateCountsOnlyTwentyOneScoredRecoveriesWithinThirtyOneDays() {
        assertNull(VitalityWindow.healthspan((0 until 20).map { day(it) }, "2026-10-18", 40.0, "male"))
        assertNotNull(VitalityWindow.healthspan((0 until 21).map { day(it) }, "2026-10-18", 40.0, "male"))
        assertEquals(0, VitalityWindow.recoveries(listOf(day(-1), day(31), day(0, false)), "2026-10-18"))
        assertEquals(2, VitalityWindow.recoveries(listOf(day(0), day(30)), "2026-10-18"))
    }

    @Test fun weeklyRatesUseCalendarSpanIncludingGaps() {
        val days = (10..30).map { day(it).copy(zone13Min = 10.0) }
        val result = VitalityWindow.healthspan(days, "2026-10-18", 40.0, "male")!!
        assertEquals(210.0 * (7.0 / 31), result.longInputs.zone13MinPerWeek!!, 0.0)
        assertNull(result.longInputs.strengthMinPerWeek)
    }

    @Test fun measuredVo2DoesNotRewriteEarlierWindow() {
        val history = (0 until 180).map { day(it).copy(vo2max = 40.0) }
        val earlierDay = HRVStatus.dayString(end - 28)
        val before = VitalityWindow.healthspan(history, earlierDay, 40.0, "male")!!
        val changed = history.map { if (it.day == "2026-10-18") it.copy(measuredVO2max = 50.0) else it }
        assertEquals(before, VitalityWindow.healthspan(changed, earlierDay, 40.0, "male"))
        assertEquals(50.0, VitalityWindow.healthspan(changed, "2026-10-18", 40.0, "male")!!.longInputs.vo2max!!, 0.0)
    }

    @Test fun leanMassSourcePrecedenceAndPlausibility() {
        val points = VitalityWindow.leanMassPoints(
            labBodyFat = listOf("a" to 22.0, "d" to 95.0),
            bodyFat = listOf("a" to 30.0, "b" to 25.0),
            leanKg = listOf("a" to 60.0, "b" to 70.0, "c" to 60.0),
            weightKg = listOf("a" to 100.0, "b" to 100.0, "c" to 80.0),
        )
        assertEquals(listOf(VitalityWindow.LeanMassPoint("a", 78.0), VitalityWindow.LeanMassPoint("b", 75.0),
            VitalityWindow.LeanMassPoint("c", 75.0)), points)
    }

    @Test fun strengthWithoutZonesCountsAndPairedLiftDoesNotDoubleCount() {
        val workout = WorkoutRow(deviceId = "strap", startTs = 100L, endTs = 3700L,
            sport = "Strength Training", source = "manual", durationS = 3600.0)
        val result = VitalityWindow.days(
            dailies = listOf(DailyMetric("strap", "2026-10-18", recovery = 70.0, steps = 4000)),
            workouts = listOf(workout), vo2ByDay = mapOf("2026-10-18" to 42.0),
            lifts = listOf(VitalityWindow.Lift(100, 3700, "Strength Training"), VitalityWindow.Lift(4000, 5800, "strength")),
            measuredVO2ByDay = mapOf("2026-10-18" to 48.0), consistencyByDay = mapOf("2026-10-18" to 80.0),
            stepsByDay = mapOf("2026-10-18" to 9000.0), dayOf = { "2026-10-18" },
        ).single()
        assertEquals(90.0, result.strengthMin, 0.0)
        assertEquals(0.0, result.zone13Min, 0.0)
        assertEquals(48.0, result.measuredVO2max!!, 0.0)
        assertEquals(42.0, result.vo2max!!, 0.0)
        assertEquals(9000.0, result.steps!!, 0.0)
        assertEquals(80.0, result.sleepConsistency!!, 0.0)
        assertTrue(result.hasRecovery)
    }
}
