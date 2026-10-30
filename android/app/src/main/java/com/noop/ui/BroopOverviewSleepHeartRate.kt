package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.DetectedSleep
import com.noop.analytics.PreSleepHeartRateFeedback
import com.noop.analytics.SleepHeartRateContrast
import com.noop.data.SleepSession
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal data class BroopOverviewHeartRateNight(
    val day: String,
    val preSleep: PreSleepHeartRateFeedback.Feedback?,
    val contrast: SleepHeartRateContrast.Result?,
)

/** The same full five-minute epochs as Repository+SleepHeartRate.swift; naps are removed from wake. */
internal fun broopSleepHeartRateGrid(from: Long, to: Long, buckets: Map<Long, Double>, excluding: List<LongRange> = emptyList()): List<Double?> {
    val cadence = 300L
    val first = ((from + cadence - 1) / cadence) * cadence
    if (to - first < cadence) return emptyList()
    val output = mutableListOf<Double?>()
    var timestamp = first
    while (timestamp <= to - cadence) {
        if (excluding.none { range -> range.first < timestamp + cadence && range.last + 1 > timestamp }) output += buckets[timestamp]
        timestamp += cadence
    }
    return output
}

private suspend fun broopSleepHeartRateHistory(vm: AppViewModel, day: String, enabled: Boolean): List<BroopOverviewHeartRateNight> {
    val endDay = LocalDate.parse(day)
    val zone = ZoneId.systemDefault()
    val end = endDay.plusDays(1).atStartOfDay(zone).toEpochSecond()
    val start = endDay.minusDays(70).atStartOfDay(zone).toEpochSecond()
    val imported = vm.repo.sleepSessionsUnion(vm.activeStrapId, start, end)
    val computed = vm.repo.computedSleepSessionsUnion(vm.activeStrapId, start, end)
    val importedDays = imported.mapTo(HashSet()) { localDayString(it.endTs) }
    val sessions = imported + computed.filter { localDayString(it.endTs) !in importedDays }
    val habitual = vm.repo.habitualMidsleepSec(vm.activeStrapId)
    data class Night(val day: String, val start: Long, val end: Long)
    val nights = sessions.groupBy { localDayString(it.endTs) }.values.mapNotNull { blocks ->
        val group = mainSleepGroup(blocks, habitual)
        val first = group.minOfOrNull(SleepSession::effectiveStartTs) ?: return@mapNotNull null
        val last = group.maxOfOrNull(SleepSession::endTs) ?: return@mapNotNull null
        Night(localDayString(last), first, last).takeIf { last > first }
    }.filter { it.day <= day }.sortedBy { it.start }.takeLast(65)
    val first = nights.firstOrNull() ?: return emptyList()
    val last = nights.last()
    val buckets = vm.repo.hrBucketsUnion(vm.activeStrapId, first.start - 86400, last.end, 300).associate { it.bucket to it.avgBpm }
    val sleepRanges = sessions.filter { it.endTs > it.effectiveStartTs }.map { it.effectiveStartTs until it.endTs }
    val history = mutableListOf<PreSleepHeartRateFeedback.HistoricalReading>()
    val output = mutableListOf<BroopOverviewHeartRateNight>()
    nights.forEachIndexed { index, night ->
        currentCoroutineContext().ensureActive()
        val raw = if (enabled) vm.repo.hrSamplesUnion(vm.activeStrapId, night.start - 1800, night.start - 1, 10_000)
            .map { com.noop.protocol.HrSample(it.ts.toInt(), it.bpm) } else emptyList()
        val feedback = if (enabled) PreSleepHeartRateFeedback.evaluate(true,
            listOf(DetectedSleep(night.start, night.end, 0.0, emptyList(), null, null)), raw, history,
            emptyList(), night.day) else null
        val previous = nights.getOrNull(index - 1)
        val contrast = if (previous != null && previous.end < night.start && night.start - previous.end <= 86400) {
            SleepHeartRateContrast.evaluate(broopSleepHeartRateGrid(previous.end, night.start, buckets, sleepRanges),
                broopSleepHeartRateGrid(night.start, night.end, buckets))
        } else null
        feedback?.observation?.let { history += PreSleepHeartRateFeedback.HistoricalReading(night.day, it.meanBpm) }
        if (LocalDate.parse(night.day) > endDay.minusDays(30)) output += BroopOverviewHeartRateNight(night.day, feedback, contrast)
    }
    return output
}

@Composable
internal fun BroopOverviewSleepHeartRateCards(vm: AppViewModel, day: String) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val syncRevision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val enabled = NoopPrefs.of(LocalContext.current).getBoolean("broop.sleep.preSleepHeartRate", false)
    var nights by remember { mutableStateOf<List<BroopOverviewHeartRateNight>>(emptyList()) }
    var trendDays by remember { mutableIntStateOf(14) }
    var method by remember { mutableStateOf(false) }
    LaunchedEffect(days, day, enabled, vm.activeStrapId, syncRevision) {
        nights = emptyList()
        val result = runCatching { broopSleepHeartRateHistory(vm, day, enabled) }.getOrDefault(emptyList())
        currentCoroutineContext().ensureActive()
        nights = result
    }
    val latest = nights.firstOrNull { it.day == day } ?: return
    val observation = latest.preSleep?.observation
    val comparison = latest.preSleep?.comparison
    val contrast = latest.contrast
    if (observation == null && comparison == null && contrast == null) return
    val prior = nights.filter { LocalDate.parse(it.day) > LocalDate.parse(day).minusDays(trendDays.toLong()) }
    if (observation != null && comparison != null) {
        BroopSection(stringResource(R.string.broop_overview_pre_sleep_hr))
        BroopCard {
            Text(stringResource(R.string.broop_overview_pre_sleep_reading, observation.meanBpm.roundToInt()), style = BroopType.section, color = BroopPalette.textPrimary)
            Text(stringResource(R.string.broop_overview_pre_sleep_comparison, String.format(Locale.getDefault(), "%+.1f", comparison.deltaBpm)), style = BroopType.body, color = BroopPalette.textBody)
            if (latest.preSleep?.uncertainty?.isNotEmpty() == true) Text(stringResource(R.string.broop_overview_pre_sleep_building), style = BroopType.caption, color = BroopPalette.textSecondary)
            val points = prior.mapNotNull { row -> row.preSleep?.observation?.let { row.day to it.meanBpm } }
            if (points.size >= 2) LineChart(points.map { it.second }, Modifier.fillMaxWidth().height(BroopMetrics.tabBarClearance), BroopPalette.rest,
                selectionEnabled = true, selectionLabels = points.map { lastChargeDateLabel(it.first) })
        }
    }
    if (contrast != null) {
        BroopSection(stringResource(R.string.broop_overview_sleep_dip))
        BroopCard {
            Text(stringResource(R.string.broop_overview_sleep_dip_reading, String.format(Locale.getDefault(), "%.1f", contrast.sleepReductionPercent)), style = BroopType.section, color = BroopPalette.textPrimary)
            Text(stringResource(if (contrast.sleepReductionPercent >= 0) R.string.broop_overview_sleep_dip_lower else R.string.broop_overview_sleep_dip_higher), style = BroopType.body, color = BroopPalette.textBody)
            Text(stringResource(R.string.broop_overview_sleep_dip_means, contrast.wakeMeanBpm.roundToInt(), contrast.sleepMeanBpm.roundToInt()), style = BroopType.caption, color = BroopPalette.textSecondary)
            Text(stringResource(R.string.broop_overview_sleep_dip_coverage, (contrast.wakeCoverage * 100).roundToInt(), (contrast.sleepCoverage * 100).roundToInt()), style = BroopType.caption, color = BroopPalette.textSecondary)
            val points = prior.mapNotNull { row -> row.contrast?.let { row.day to it.sleepReductionPercent } }
            if (points.size >= 2) LineChart(points.map { it.second }, Modifier.fillMaxWidth().height(BroopMetrics.tabBarClearance), BroopPalette.rest,
                selectionEnabled = true, selectionLabels = points.map { lastChargeDateLabel(it.first) })
        }
    }
    if (comparison != null || contrast != null) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            TextButton(onClick = { trendDays = 14 }) { Text(stringResource(R.string.broop_overview_14_days), color = if (trendDays == 14) BroopPalette.textPrimary else BroopPalette.textSecondary) }
            TextButton(onClick = { trendDays = 30 }) { Text(stringResource(R.string.broop_overview_30_days), color = if (trendDays == 30) BroopPalette.textPrimary else BroopPalette.textSecondary) }
        }
        BroopRow(stringResource(R.string.broop_overview_hr_method_title)) { method = !method }
        if (method) BroopCard { Text(stringResource(R.string.broop_overview_hr_method), style = BroopType.body, color = BroopPalette.textBody) }
    }
}
