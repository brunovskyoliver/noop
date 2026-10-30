package com.noop.analytics

import com.noop.data.DailyMetric
import com.noop.data.MetricSeriesRow
import org.junit.Assert.*
import org.junit.Test

class StressRestHistoryTest {
    @Test fun windowIncludesEveryCalendarDayWithoutNeedingASleepNight() {
        assertEquals(listOf("2026-03-28", "2026-03-29", "2026-03-30"), StressRestPass.windowDays("2026-03-28", "2026-03-30"))
        assertTrue(StressRestPass.windowDays("2026-03-30", "2026-03-28").isEmpty())
    }

    @Test fun expiredRawRetainsDerivedHistoryButPresentSparseRawClearsIt() {
        val old = mapOf("stress_day" to 1.8, "sleep_stress_pct" to 15.0, "energy_end" to 42.0, "unrelated" to 99.0)
        assertEquals(old - "unrelated", StressRestPass.retainedOrFresh(false, old, emptyMap()))
        assertEquals(emptyMap<String, Double>(), StressRestPass.retainedOrFresh(true, old, emptyMap()))
        assertEquals(mapOf("stress_day" to 0.5), StressRestPass.retainedOrFresh(true, old, mapOf("stress_day" to 0.5)))
    }

    @Test fun retainedSleepStressFeedsTheSameRestResolver() {
        val d = DailyMetric("s", "2026-03-29", totalSleepMin = 420.0, efficiency = 0.9)
        val r = StressRestPass.Result(emptyList(), mapOf(d.day to 0.8), mapOf(d.day to 15.0))
        assertEquals(RestPerformanceV2.composite(d, 8.0, 0.8, 15.0), r.rest(d, 8.0))
        assertNotEquals(RestPerformanceV2.composite(d, 8.0, 0.8, null), r.rest(d, 8.0))
    }

    @Test fun wakingOnlyPersistenceNeverWidensDailyOrUnrelatedMetricWrites() {
        val source = "s-noop"
        val window = IntelligencePersistence.ComputedWindow(source, "2026-03-28", "2026-03-30",
            listOf(DailyMetric(source, "2026-03-28", totalSleepMin = 420.0)),
            listOf(MetricSeriesRow(source, "2026-03-28", "sleep_performance", 90.0),
                MetricSeriesRow(source, "2026-03-29", "stress_day", 0.8),
                MetricSeriesRow(source, "2026-03-29", "unrelated", 4.0)), emptyList(), listOf(source), independentMetricDays = listOf("2026-03-30"))
        val parts = IntelligencePersistence.byScoredDay(window)
        assertEquals(listOf("2026-03-28", "2026-03-29", "2026-03-30"), parts.map { it.from })
        val waking = parts[1]
        assertEquals(waking.from, waking.to)
        assertTrue(waking.dailies.isEmpty())
        assertEquals(listOf("stress_day"), waking.metricRows.map { it.key })
        assertTrue(parts.last().dailies.isEmpty())
        assertTrue(parts.last().metricRows.isEmpty())
    }
}
