package com.noop.ui

import com.noop.analytics.RestScorer
import com.noop.analytics.SleepDebt
import com.noop.analytics.SleepPlanner
import com.noop.data.DailyMetric
import com.noop.data.SleepSession
import java.util.TimeZone

/**
 * Planner inputs from stored data. Twin of iOS `AppModel.tonightPlanInputs`: base need and debt are the
 * Sleep tab's own (the 14-night ledger against `personalizedNeedHours`, with nap credit), so the plan and
 * the Sleep Debt card measure against one need; efficiency and usual bedtime come from the last 14 nights.
 */
internal fun tonightPlanInputs(
    days: List<DailyMetric>,
    sleeps: List<SleepSession>,
    habitualMidsleepSec: Long?,
    today: String,
    wakeMinute: Int,
    timeZone: TimeZone,
): SleepPlanner.Inputs {
    val naps = napSleepMinutesByDay(sleeps, habitualMidsleepSec)
    val needMin = RestScorer.personalizedNeedHours(days.mapNotNull { it.totalSleepMin?.let { m -> m / 60.0 } }, null) * 60.0
    val ledger = SleepDebt.ledger(
        series = days.map { d -> d.day to SleepDebt.creditedSleepMin(d.totalSleepMin, naps[d.day] ?: 0.0) },
        needHours = needMin / 60.0,
    )
    val recent = days.sortedBy { it.day }.takeLast(14)
    // One bedtime per night: the start of that wake-day's main sleep, the same selector the Sleep tab uses.
    val beds = sleeps.groupBy { localDayString(it.endTs) }.toSortedMap().values
        .mapNotNull { blocks -> mainSleepGroup(blocks, habitualMidsleepSec).minOfOrNull { it.effectiveStartTs } }
        .takeLast(14)
        .map { ts ->
            val local = ts + timeZone.getOffset(ts * 1000L) / 1000L
            (((local % 86_400L) + 86_400L) % 86_400L / 60L).toInt()
        }
    return SleepPlanner.Inputs(
        baseNeedHours = ledger.needMin / 60.0,
        debtMin = if (ledger.isDebt) ledger.magnitudeMin else 0.0,
        napMin = naps[today] ?: 0.0,
        efficiencies = recent.mapNotNull { it.efficiency },
        wakeMinute = wakeMinute,
        recentBedMinutes = beds,
    )
}
