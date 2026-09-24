package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Twin of Swift `HRVStatusTests`; oracle values pasted from the Swift run. */
class HRVStatusTest {

    private val asOf = "2026-09-24"

    private fun series(recent: Double?, recentNights: Int = 7, usualNights: Int = 60): List<HRVStatus.Night> {
        val end = VitalityWindow.epochDay(asOf)!!
        return (0 until 67).map { i ->
            val day = HRVStatus.dayString(end - 66 + i)
            if (i < 60) HRVStatus.Night(day, if (i >= 60 - usualNights) (if (i % 2 == 0) 45.0 else 55.0) else null)
            else HRVStatus.Night(day, if (66 - i < recentNights) recent else null)
        }
    }

    private fun band(o: HRVStatus.Outcome) = (o as? HRVStatus.Outcome.Status)?.reading?.band

    @Test fun stepChangesLandInTheirBands() {
        assertEquals(HRVStatus.Band.BALANCED, band(HRVStatus.evaluate(series(50.0), asOf)))
        assertEquals(HRVStatus.Band.ABOVE, band(HRVStatus.evaluate(series(55.0), asOf)))
        assertEquals(HRVStatus.Band.BELOW, band(HRVStatus.evaluate(series(46.0), asOf)))
        assertEquals(HRVStatus.Band.LOW, band(HRVStatus.evaluate(series(42.0), asOf)))
    }

    @Test fun calibratingAndStale() {
        assertEquals(HRVStatus.Outcome.Calibrating(20), HRVStatus.evaluate(series(50.0, usualNights = 20), asOf))
        assertEquals(HRVStatus.Outcome.NoRecentData, HRVStatus.evaluate(series(50.0, recentNights = 2), asOf))
        val later = HRVStatus.dayString(VitalityWindow.epochDay(asOf)!! + 4)
        assertEquals(HRVStatus.Outcome.NoRecentData, HRVStatus.evaluate(series(50.0, recentNights = 3), later))
    }

    @Test fun flaggedDays() {
        val r = (HRVStatus.evaluate(series(50.0), asOf, setOf(asOf)) as HRVStatus.Outcome.Status).reading
        assertTrue(r.mayReflectFlaggedDays)
    }

    @Test fun oracle() {
        val end = VitalityWindow.epochDay(asOf)!!
        val nights = (0 until 70).map { i ->
            val v: Double? = if (i % 9 == 4) null else 38 + ((i * 7) % 23).toDouble() + (if (i >= 63) -6 else 0)
            HRVStatus.Night(HRVStatus.dayString(end - 69 + i), if (i == 20) 400.0 else v)
        }
        val r = (HRVStatus.evaluate(nights, asOf) as HRVStatus.Outcome.Status).reading
        assertEquals(HRVStatus.Band.LOW, r.band)
        assertEquals(39.911849096666415, r.mean7Ms, 0.0)
        assertEquals(45.53189199366618, r.usualLowMs, 0.0)
        assertEquals(52.226802964407376, r.usualHighMs, 0.0)
        assertEquals(42.513496495352065, r.lowMs, 0.0)
        assertEquals(6, r.shortNights)
        assertEquals(52, r.baselineNights)
    }
}
