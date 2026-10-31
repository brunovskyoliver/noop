package com.noop.data

import com.noop.analytics.VitalityWindow

/** First v2 pass backfills Sunday history; subsequent passes update the current Sunday only. */
suspend fun refreshBroopHealthspan(repo: WhoopRepository, strapId: String, newestDay: String, age: Int, sex: String, fresh: List<DailyMetric>) {
    val existing = repo.metricSeriesComputedUnion(strapId, "body_age", "0000-01-01", newestDay)
    val hasV2History = existing.any { VitalityWindow.sundayKey(it.day) == it.day }
    val first = if (hasV2History) null else repo.daysMerged(strapId).minOfOrNull { it.day }
    val rows = repo.healthspanWeeklyRows(strapId, newestDay, age, sex, fresh, backfillFrom = first)
    if (rows.isNotEmpty()) repo.upsertMetricSeries(rows)
}
