package com.noop.ui

import com.noop.data.SleepSession
import java.time.LocalDate
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** SleepModel's UI adapter preserves the Swift-oracle SRI and its known-pair capture gate. */
class SleepConsistencyParityTest {
    private var savedZone = TimeZone.getDefault()
    private val dates = (0L..8L).map { LocalDate.parse("2026-01-01").plusDays(it).toString() }

    @Before fun forceUtc() { savedZone = TimeZone.getDefault(); TimeZone.setDefault(TimeZone.getTimeZone("UTC")) }
    @After fun restoreZone() { TimeZone.setDefault(savedZone) }

    private fun session(day: String, shiftMinutes: Int = 0): SleepSession {
        val start = LocalDate.parse(day).minusDays(1).atTime(23, 0).toEpochSecond(java.time.ZoneOffset.UTC) + shiftMinutes * 60
        return SleepSession("my-whoop", start, start + 8 * 3600)
    }

    @Test fun alternatingOneHourShiftMatchesActualSwiftOracle() {
        val sessions = dates.mapIndexed { index, day -> session(day, if (index % 2 == 0) 0 else 60) }
        val metric = consistencySeries(sessions, dates)
        assertEquals(4, metric.series.size)
        assertEquals(83.33333333333333, metric.latest!!, 1e-12)
        assertEquals(83.33333333333333, metric.typical!!, 1e-12)
    }

    @Test fun fiveNightsCannotMeetThe120HourKnownPairFloor() {
        val metric = consistencySeries(dates.take(5).map { session(it) }, dates.take(5))
        assertNull(metric.latest)
        assertEquals(emptyList<Double>(), metric.series)
    }

    @Test fun effectiveOnsetAndWakeSegmentsDriveTheSameTimelineAsSleep() {
        val sessions = dates.map { day ->
            val canonical = session(day)
            canonical.copy(startTs = canonical.startTs - 2 * 3600, startTsAdjusted = canonical.startTs)
        }.reversed()
        val metric = consistencySeries(sessions, dates)
        assertEquals(100.0, metric.latest!!, 1e-12)
        val target = sessions.first()
        val wakeStart = target.effectiveStartTs + 3 * 3600
        val withWake = sessions.map { if (it == target) it.copy(stagesJSON = """[{"start":$wakeStart,"end":${wakeStart + 3600},"stage":"awake"}]""") else it }
        assertEquals(98.61111111111111, consistencySeries(withWake, dates).latest!!, 1e-12)
    }
}
