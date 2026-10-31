package com.noop.analytics

import java.time.LocalDate
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class SleepRegularityTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private fun days(first: String = "2026-01-01", count: Int = 9): List<String> =
        (0 until count).map { LocalDate.parse(first).plusDays(it.toLong()).toString() }

    private fun night(day: String, offset: Int = 0, length: Int = 480, zone: TimeZone = utc,
        wake: List<Pair<Int, Int>> = emptyList()): SleepRegularity.Session {
        val window = SleepRegularity.windowStart(day, zone)!!
        val start = window + (300 + offset) * 60
        return SleepRegularity.Session(start, start + length * 60, wake.map { (a, b) -> (window + a * 60) until (window + b * 60) })
    }

    /** Literal stdout from swiftc -O on the repository's unmodified SleepRegularity.swift and vocabulary.
     * Cases span 1-minute to 12-hour shifts, missing capture, threshold capture, naps, WASO and DST. */
    @Test fun matchesSwiftOracleAcrossSchedulesAndTimeZones() {
        val output = mutableListOf<String>()
        fun emit(label: String, dates: List<String>, sessions: List<SleepRegularity.Session>, zone: TimeZone = utc) {
            val sri = SleepRegularity.sri(dates, sessions, zone)
            val rest = SleepRegularity.restConsistency(dates, sessions, zone)
            fun format(value: Double?) = value?.let { String.format(Locale.US, "%.12f", it) } ?: "nil"
            dates.takeLast(3).forEach { day -> output += "$label|$day|${format(sri[day])}|${format(rest[day])}" }
        }
        val d = days()
        listOf(0, 1, 15, 30, 60, 120, 180, 360, 720).forEach { shift ->
            emit("shift$shift", d, d.mapIndexed { index, day -> night(day, if (index % 2 == 0) 0 else shift) })
        }
        emit("missing", d, d.mapIndexedNotNull { index, day -> if (index in listOf(2, 5)) null else night(day) })
        emit("short", d, d.mapIndexed { index, day -> night(day, length = if (index in listOf(3, 6)) 119 else 480) })
        emit("threshold", d, d.mapIndexed { index, day -> night(day, length = if (index in listOf(3, 6)) 120 else 480) })
        emit("nap", d, d.map { night(it) } + night(d[6], 900, 60))
        emit("wake", d, d.mapIndexed { index, day -> night(day, wake = if (index == 6) listOf(480 to 540) else emptyList()) })
        emit("duplicate", d, d.map { night(it) } + d.map { night(it, wake = listOf(480 to 540)) })
        emit("cold", d.take(2), d.take(2).map { night(it) })
        listOf("Europe/Bratislava" to "2026-03-24", "Europe/Bratislava" to "2026-10-21",
            "America/New_York" to "2026-03-04", "Asia/Kathmandu" to "2026-01-01").forEach { (id, first) ->
            val zone = TimeZone.getTimeZone(id)
            val dates = days(first)
            emit(id + first, dates, dates.map { night(it, zone = zone) }, zone)
        }
        for (i in -2..2) {
            val value = i * 60.0
            output += "percent|${value.toInt()}|${SleepRegularity.consistencyPercent(value)}"
        }
        assertEquals(SWIFT_ORACLE.trimIndent(), output.joinToString("\n"))
    }

    @Test fun wakeIntervalsClipToSessionAndOverrideOverlappingDuplicates() {
        val json = """[{"start":0,"end":300,"stage":" AWAKE "},{"start":400,"end":1000,"stage":"Wake"},{"start":200,"end":250,"stage":"light"}]"""
        assertEquals(listOf(100L until 300L, 400L until 900L), SleepRegularity.Session(100, 900, json).wake)
        assertEquals(emptyList<LongRange>(), SleepRegularity.Session(100, 900, "{\"light\":200}").wake)
        val day = days().last()
        val regular = days().map { night(it) }
        val noWake = SleepRegularity.sri(listOf(day), regular, utc)[day]
        val wake = night(day, wake = listOf(480 to 540))
        val withWake = SleepRegularity.sri(listOf(day), regular + wake, utc)[day]!!
        assertEquals(100.0, noWake!!, 1e-12)
        assertEquals(98.61111111111111, withWake, 1e-12)
    }

    @Test fun importedNewestDayWinsAndOtherwiseSRIProvidesClampedPercent() {
        val dates = listOf("2026-09-01", "2026-09-02")
        val sri = mapOf(dates[0] to 80.0, dates[1] to -20.0)
        assertEquals(listOf(dates[0] to 80.0, dates[1] to 0.0), SleepRegularity.resolve(dates, emptyMap(), sri))
        assertEquals(listOf(dates[1] to 61.0), SleepRegularity.resolve(dates, mapOf(dates[1] to 61.0), sri))
        assertEquals(listOf(dates[0] to 80.0, dates[1] to 0.0), SleepRegularity.resolve(dates, mapOf(dates[0] to 61.0), sri))
    }

    companion object {
        private val SWIFT_ORACLE = """
            shift0|2026-01-07|100.000000000000|1.000000000000
            shift0|2026-01-08|100.000000000000|1.000000000000
            shift0|2026-01-09|100.000000000000|1.000000000000
            shift1|2026-01-07|99.722222222222|0.998611111111
            shift1|2026-01-08|99.722222222222|0.998611111111
            shift1|2026-01-09|99.722222222222|0.998611111111
            shift15|2026-01-07|95.833333333333|0.979166666667
            shift15|2026-01-08|95.833333333333|0.979166666667
            shift15|2026-01-09|95.833333333333|0.979166666667
            shift30|2026-01-07|91.666666666667|0.958333333333
            shift30|2026-01-08|91.666666666667|0.958333333333
            shift30|2026-01-09|91.666666666667|0.958333333333
            shift60|2026-01-07|83.333333333333|0.916666666667
            shift60|2026-01-08|83.333333333333|0.916666666667
            shift60|2026-01-09|83.333333333333|0.916666666667
            shift120|2026-01-07|66.666666666667|0.833333333333
            shift120|2026-01-08|66.666666666667|0.833333333333
            shift120|2026-01-09|66.666666666667|0.833333333333
            shift180|2026-01-07|50.000000000000|0.750000000000
            shift180|2026-01-08|50.000000000000|0.750000000000
            shift180|2026-01-09|50.000000000000|0.750000000000
            shift360|2026-01-07|0.000000000000|0.500000000000
            shift360|2026-01-08|0.000000000000|0.500000000000
            shift360|2026-01-09|0.000000000000|0.500000000000
            shift720|2026-01-07|-31.944444444444|0.500000000000
            shift720|2026-01-08|-33.333333333333|0.500000000000
            shift720|2026-01-09|-33.333333333333|0.500000000000
            missing|2026-01-07|nil|1.000000000000
            missing|2026-01-08|nil|1.000000000000
            missing|2026-01-09|nil|1.000000000000
            short|2026-01-07|nil|nil
            short|2026-01-08|nil|1.000000000000
            short|2026-01-09|nil|1.000000000000
            threshold|2026-01-07|75.000000000000|0.625000000000
            threshold|2026-01-08|66.666666666667|0.750000000000
            threshold|2026-01-09|66.666666666667|0.875000000000
            nap|2026-01-07|98.611111111111|0.916666666667
            nap|2026-01-08|97.222222222222|0.979166666667
            nap|2026-01-09|97.222222222222|0.979166666667
            wake|2026-01-07|98.611111111111|0.916666666667
            wake|2026-01-08|97.222222222222|0.979166666667
            wake|2026-01-09|97.222222222222|0.979166666667
            duplicate|2026-01-07|100.000000000000|1.000000000000
            duplicate|2026-01-08|100.000000000000|1.000000000000
            duplicate|2026-01-09|100.000000000000|1.000000000000
            cold|2026-01-01|nil|nil
            cold|2026-01-02|nil|nil
            Europe/Bratislava2026-03-24|2026-03-30|97.202797202797|0.833333333333
            Europe/Bratislava2026-03-24|2026-03-31|97.202797202797|0.875000000000
            Europe/Bratislava2026-03-24|2026-04-01|97.202797202797|0.916666666667
            Europe/Bratislava2026-10-21|2026-10-27|97.241379310345|0.875000000000
            Europe/Bratislava2026-10-21|2026-10-28|97.241379310345|0.916666666667
            Europe/Bratislava2026-10-21|2026-10-29|97.241379310345|0.958333333333
            America/New_York2026-03-04|2026-03-10|97.202797202797|0.875000000000
            America/New_York2026-03-04|2026-03-11|97.202797202797|0.916666666667
            America/New_York2026-03-04|2026-03-12|97.202797202797|0.958333333333
            Asia/Kathmandu2026-01-01|2026-01-07|100.000000000000|1.000000000000
            Asia/Kathmandu2026-01-01|2026-01-08|100.000000000000|1.000000000000
            Asia/Kathmandu2026-01-01|2026-01-09|100.000000000000|1.000000000000
            percent|-120|0.0
            percent|-60|0.0
            percent|0|0.0
            percent|60|60.0
            percent|120|100.0
        """
    }
}
