package com.noop.ui

import com.noop.analytics.RestScorer
import com.noop.analytics.SleepDebt
import com.noop.data.DailyMetric
import com.noop.data.SleepSession
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.TimeZone

/** Twin of iOS `TonightPlanInputsTests`: the planner reads the Sleep tab's own need and debt. */
class TonightPlanInputsTest {

    @Test fun inputsFollowTheSleepTabLedger() {
        val days = (1..20).map { d ->
            DailyMetric(deviceId = "t", day = "2026-09-%02d".format(d), totalSleepMin = 420.0, efficiency = 0.9)
        }
        val utc = TimeZone.getTimeZone("UTC")
        val base = 1_790_000_000L - (1_790_000_000L % 86_400L)
        val sleeps = (0 until 3).map { i ->
            SleepSession(deviceId = "t", startTs = base + i * 86_400L + 23 * 3600 + 1800,
                endTs = base + (i + 1) * 86_400L + 7 * 3600)
        }
        val inputs = tonightPlanInputs(days, sleeps, null, "2026-09-20", 420, utc)
        val need = RestScorer.personalizedNeedHours(days.map { 7.0 }, null)
        val ledger = SleepDebt.ledger(days.map { it.day to 420.0 }, needHours = need)
        assertEquals(ledger.needMin / 60.0, inputs.baseNeedHours, 1e-12)
        assertEquals(if (ledger.isDebt) ledger.magnitudeMin else 0.0, inputs.debtMin, 1e-9)
        assertEquals(14, inputs.efficiencies.size)
        assertEquals(420, inputs.wakeMinute)
    }
}
