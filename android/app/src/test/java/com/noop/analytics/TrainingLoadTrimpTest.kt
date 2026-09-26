package com.noop.analytics

import com.noop.data.DailyMetric
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/** Twin of Swift `TrainingLoadTrimpTests`. */
class TrainingLoadTrimpTest {

    private fun day(offset: Int, strain: Double?) = DailyMetric(
        deviceId = "t", day = LocalDate.parse("2026-03-01").plusDays(offset.toLong()).toString(), strain = strain,
    )

    @Test fun strainToTrimpInvertsTheLogMap() {
        for (trimp in listOf(1.0, 37.5, 159.0, 868.0, 2024.0)) {
            val strain = StrainScorer.trimpToStrain(trimp)
            assertEquals(trimp, StrainScorer.strainToTrimp(strain), trimp * 0.003)
        }
        assertEquals(0.0, StrainScorer.strainToTrimp(0.0), 0.0)
        assertEquals(0.0, StrainScorer.strainToTrimp(-5.0), 0.0)
        assertEquals(7200.0, StrainScorer.strainToTrimp(100.0), 1e-6)
    }

    @Test fun doubledWeekReadsAsARealSpike() {
        val easy = StrainScorer.trimpToStrain(200.0); val hard = StrainScorer.trimpToStrain(400.0)
        val days = (0 until 28).map { day(it, if (it < 21) easy else hard) }
        val (acute, chronic) = ReadinessEngine.calendarLoads(days, days.last().day)
        assertEquals(1.6, acute.average() / chronic.average(), 0.01)
        assertTrue(hard / easy < 1.15)
    }

    @Test fun wearGapDoesNotStretchTheWindow() {
        val days = (0 until 20).map { day(it, 60.0) } + (50 until 55).map { day(it, 40.0) }
        val (acute, chronic) = ReadinessEngine.calendarLoads(days, days.last().day)
        assertEquals(5, acute.size)
        assertEquals(5, chronic.size)
        assertNull(ReadinessEngine.evaluate(days).acwr)
    }
}
