package com.noop.ui

import com.noop.data.DailyMetric
import com.noop.data.SleepSession
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BroopOverviewModelTest {
    @Test fun restCarryKeepsScoreAndNightOnSameDayAndRejectsFutureOutliers() {
        val points = mapOf("2026-10-17" to 76.0, "2026-10-20" to 99.0)
        assertEquals("2026-10-17", broopRestDayKey("2026-10-19", true, points))
        assertNull(broopRestDayKey("2026-10-19", false, points))
        assertNull(broopRestDayKey("2026-10-21", true, points.filterKeys { it == "2026-10-17" }))
        assertEquals("2026-10-19", broopRestDayKey("2026-10-19", true, points + ("2026-10-19" to 82.0)))
    }

    @Test fun changingDayInvalidatesLoadedSnapshotAndClampsAtRecordedBounds() {
        val state = BroopOverviewState()
        state.loadedKey = "previous"
        state.step(1, 10)
        assertEquals(1, state.dayOffset)
        assertNull(state.loadedKey)
        state.step(100, 10)
        assertEquals(10, state.dayOffset)
        state.step(-100, 10)
        assertEquals(0, state.dayOffset)
    }

    @Test fun dayNavigatorReachesEveryRecordedDayWithoutOfferingFutureDates() {
        val days = listOf(DailyMetric("my-whoop", "2026-10-01"), DailyMetric("my-whoop", "2026-10-17"))
        assertEquals(18, broopOverviewMaxOffset(days, LocalDate.parse("2026-10-19")))
        assertEquals(0, broopOverviewMaxOffset(emptyList(), LocalDate.parse("2026-10-19")))
    }

    @Test fun readingsKeepUnavailableDistinctFromZeroAndUsePriorWindow() {
        assertNull(broopOverviewReading("hrv", null, listOf(50.0)))
        val zero = broopOverviewReading("steps", 0.0, emptyList())!!
        assertEquals(0.0, zero.value, 0.0)
        assertNull(zero.inRange)
        val reading = broopOverviewReading("hrv", 55.0, listOf(40.0, 50.0, 60.0))!!
        assertEquals(50.0, reading.baseline!!, 1e-12)
        assertTrue(reading.inRange!!)
        assertFalse(broopOverviewReading("hrv", 70.0, listOf(40.0, 50.0, 60.0))!!.inRange!!)
    }

    @Test fun sleepHrGridKeepsUnknownEpochsAndExcludesEveryNapOverlap() {
        val buckets = mapOf(600L to 60.0, 1200L to 72.0)
        assertEquals(listOf(60.0, null, 72.0), broopSleepHeartRateGrid(330, 1501, buckets))
        assertEquals(listOf(72.0), broopSleepHeartRateGrid(330, 1501, buckets, listOf(801L until 901L)))
        assertEquals(emptyList<Double?>(), broopSleepHeartRateGrid(330, 899, buckets))
        assertEquals(listOf(60.0), broopSleepHeartRateGrid(600, 900, buckets, listOf(900L until 1200L)))
    }

    @Test fun nativeDetailsFindTheSelectedWakeDayAcrossMissingNights() {
        fun night(day: String): SleepSession {
            val wake = LocalDate.parse(day).atStartOfDay(ZoneId.systemDefault()).plusHours(8).toEpochSecond()
            return SleepSession("my-whoop-noop", wake - 8 * 3600, wake)
        }
        val groups = listOf(listOf(night("2026-03-08")), listOf(night("2026-03-06")), listOf(night("2026-03-01")))
        assertEquals(1, broopSleepNightIndex(groups, "2026-03-06"))
        assertNull(broopSleepNightIndex(groups, "2026-03-07"))
    }

    @Test fun deletingDisplayedMainNightCapturesEveryFragmentButNapDeleteStaysSeparate() {
        val main = SleepSession("whoop-new-noop", 1_000, 10_000)
        val sibling = SleepSession("whoop-new-noop", 10_300, 18_000)
        val nap = SleepSession("whoop-new-noop", 25_000, 27_000)
        val hero = HeroNight(main, "2026-03-08", null, "", napBlocks = listOf(nap), heroGroup = listOf(main, sibling))
        assertEquals(listOf(main, sibling), broopSleepDeleteGroup(hero, main))
        assertEquals(listOf(nap), broopSleepDeleteGroup(hero, nap))
        assertEquals(listOf(main), broopSleepDeleteGroup(hero.copy(heroGroup = emptyList()), main))
    }
}
