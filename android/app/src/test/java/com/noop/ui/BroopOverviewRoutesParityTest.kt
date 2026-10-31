package com.noop.ui

import com.noop.R
import com.noop.analytics.ChargeBaselines
import com.noop.analytics.ChargeDriverLabel
import com.noop.analytics.RestPerformanceV2
import com.noop.data.DailyMetric
import com.noop.data.SleepSession
import com.noop.data.WorkoutRow
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BroopOverviewRoutesParityTest {
    // stdout from swiftc -O broop_overview_final_oracle.swift, using the actual Swift Coupled body.
    @Test fun coupledSleepNeedUsesImportedPositiveThenPersonalMeanWithItsOwnFloor() {
        val cases = listOf(
            null to emptyList(), null to listOf(0.0, -2.0, null), null to listOf(300.0, 400.0),
            null to listOf(480.0, 600.0, null, 0.0), 350.0 to listOf(800.0),
            0.0 to listOf(480.0), -1.0 to listOf(420.0, 600.0),
        )
        val actual = cases.joinToString("\n") { (imported, totals) ->
            val days = totals.mapIndexed { i, sleep -> DailyMetric("my-whoop", "day-$i", totalSleepMin = sleep) }
            String.format(Locale.US, "%.3f", broopCoupledSleepNeed(imported, days))
        }
        assertEquals("""
            450.000
            450.000
            450.000
            540.000
            350.000
            480.000
            510.000
        """.trimIndent(), actual)
    }

    // Verbatim Swift stdout for strict sleep overlap, full duration, inclusive workout edges and ties.
    @Test fun timelineAnnotationsUseSwiftScopeAndStableTieRules() {
        val sleeps = listOf(
            Triple(-100L, 110L, "long"), Triple(100L, 200L, "main"), Triple(120L, 150L, "nap"),
            Triple(200L, 260L, "after"), Triple(0L, 100L, "edge"),
        ).map { (start, end, name) -> SleepSession(name, start, end) }
        val workouts = listOf(
            Triple(0L, 100L, "left"), Triple(100L, 200L, "inside"), Triple(200L, 250L, "right"), Triple(300L, 400L, "outside"),
        ).map { (start, end, name) -> WorkoutRow("my-whoop", start, end, name, "manual") }
        val windows = listOf(100L..200L, 0L..100L, 200L..300L, 101L..199L, -100L..0L, 300L..400L)
        val actual = windows.map { window ->
            (broopTimelineMainSleep(sleeps, window)?.deviceId ?: "nil") + "|" +
                broopTimelineWorkouts(workouts, window).joinToString(",") { it.sport }
        } + (broopTimelineMainSleep(listOf(SleepSession("first", 100, 150), SleepSession("second", 120, 170)), 100L..200L)?.deviceId ?: "nil")
        assertEquals("""
            long|left,inside,right
            long|left,inside
            after|inside,right,outside
            long|inside
            long|left
            nil|outside
            first
        """.trimIndent(), actual.joinToString("\n"))
    }

    @Test fun editedSleepOnsetControlsOverlapAndLength() {
        val shifted = SleepSession("edited", 220, 250, userEdited = true, startTsAdjusted = 80)
        assertEquals(shifted, broopTimelineMainSleep(listOf(SleepSession("short", 110, 150), shifted), 100L..200L))
        assertNull(broopTimelineMainSleep(listOf(SleepSession("ends-at-start", 0, 100), SleepSession("starts-at-end", 200, 250)), 100L..200L))
    }

    @Test fun restResolutionKeepsStoredSameDayAndUsesCurrentFormulaOnlyWhenUnstored() {
        val row = DailyMetric("my-whoop", "2026-10-20", totalSleepMin = 390.0, efficiency = 0.9)
        val stored = mapOf("2026-10-19" to 99.0, row.day to 55.0)
        assertEquals(55.0, broopRestForRow(row, stored, true)!!, 0.0)
        assertEquals(55.0, broopRestForRow(row, stored, false)!!, 0.0)
        assertEquals(RestPerformanceV2.composite(row), broopRestForRow(row, mapOf("2026-10-19" to 99.0), true))
        assertNull(broopRestForRow(null, stored, true))
    }

    @Test fun chargeBreakdownConsumesExplicitResolvedRestAndDoesNotInventSleepInput() {
        val history = (1..20).map { n -> DailyMetric("my-whoop", "2026-10-${n.toString().padStart(2, '0')}",
            avgHrv = 50.0 + n, restingHr = 60, respRateBpm = 15.0) }
        val baselines = ChargeBaselines.resolve(history, emptyList(), "2026-10-20", 0.0, 0.0)
        val row = history.last().copy(efficiency = 1.0, totalSleepMin = 600.0)
        val drivers = broopChargeDrivers(baselines, row, 55.0)
        // Swift's percent → fraction → driver percent conversion has this exact Double result.
        assertEquals(55.00000000000001, drivers.single { it.label == ChargeDriverLabel.SLEEP_QUALITY }.value, 0.0)
        assertTrue(broopChargeDrivers(baselines, row, null).none { it.label == ChargeDriverLabel.SLEEP_QUALITY })
        assertTrue(broopChargeDrivers(baselines, row.copy(avgHrv = null), 55.0).isEmpty())
    }

    // Verbatim Swift RecoveryScorer.skinTempRelative stdout at the inclusive typical boundaries.
    @Test fun relativeSkinTemperatureLabelsKeepTheSwiftTypicalBand() {
        val names = mapOf(R.string.broop_overview_skin_cooler to "cooler", R.string.broop_overview_skin_typical to "typical",
            R.string.broop_overview_skin_warmer to "warmer")
        assertEquals("""
            cooler
            typical
            typical
            typical
            warmer
        """.trimIndent(), listOf(-0.31, -0.3, 0.0, 0.3, 0.31).joinToString("\n") { names.getValue(broopSkinTemperatureTier(it)) })
    }
}
