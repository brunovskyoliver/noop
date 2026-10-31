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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import java.time.LocalDate
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal fun broopOverviewSeriesKey(key: String): String = when (key) {
    "performance", "rest" -> "sleep_performance"
    "efficiency" -> "sleep_efficiency"
    "consistency" -> "sleep_consistency"
    "hours_vs_needed" -> "hours_vs_needed_pct"
    "restorative" -> "restorative_pct"
    "respiratory", "resp" -> "resp_rate"
    "sleep_debt" -> "sleep_debt_min"
    else -> key
}

/** Focused trend for the additional Broop sleep and HR-zone metrics, using stored per-day readings. */
@Composable
fun BroopOverviewMetricScreen(vm: AppViewModel, key: String, onBack: () -> Unit) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val syncRevision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    var points by remember(key) { mutableStateOf<List<Pair<String, Double>>>(emptyList()) }
    var range by remember(key) { mutableIntStateOf(30) }
    val resolvedKey = broopOverviewSeriesKey(key)
    val context = LocalContext.current
    LaunchedEffect(days, key, vm.activeStrapId, syncRevision) {
        val stored = runCatching {
            vm.repo.resolvedSeries(resolvedKey, "my-whoop", "0000-00-00", "9999-12-31", strapDeviceId = vm.activeStrapId).values
        }.getOrDefault(emptyList()).associate { it.first to it.second }.toMutableMap()
        if (resolvedKey == "sleep_consistency" && days.lastOrNull()?.day?.let { stored[it] } == null) {
            val now = System.currentTimeMillis() / 1000
            val imported = vm.repo.sleepSessionsUnion(vm.activeStrapId, 0, now)
            val computed = vm.repo.computedSleepSessionsUnion(vm.activeStrapId, 0, now)
            val importedDays = imported.mapTo(HashSet()) { localDayString(it.endTs) }
            val sessions = imported + computed.filter { localDayString(it.endTs) !in importedDays }
            val sri = withContext(Dispatchers.Default) {
                com.noop.analytics.SleepRegularity.sri(days.map { it.day }, sessions.map {
                    com.noop.analytics.SleepRegularity.Session(it.effectiveStartTs, it.endTs, it.stagesJSON)
                })
            }
            stored.clear()
            stored.putAll(sri.mapValues { com.noop.analytics.SleepRegularity.consistencyPercent(it.value) })
        }
        val needByDay = if (resolvedKey == "hours_vs_needed_pct") {
            vm.repo.resolvedSeries("sleep_need_min", "my-whoop", "0000-00-00", "9999-12-31", strapDeviceId = vm.activeStrapId).values.toMap()
        } else emptyMap()
        val hoursParts = if (resolvedKey == "hours_vs_needed_pct") {
            vm.repo.metricSeriesComputedUnion(vm.activeStrapId, com.noop.analytics.RestPerformanceV2.hoursVsNeedKey, "0000-00-00", "9999-12-31").associate { it.day to it.value }
        } else emptyMap()
        val need = if (resolvedKey == "hours_vs_needed_pct") com.noop.analytics.RestScorer.personalizedNeedHours(
            days.mapNotNull { it.totalSleepMin?.div(60) }, ProfileStore.from(context).age) * 60 else 0.0
        days.forEach { day ->
            if (day.day !in stored) {
                val value = when (resolvedKey) {
                    "sleep_efficiency" -> day.efficiency?.let { if (it <= 1) it * 100 else it }
                    "sleep_total_min" -> day.totalSleepMin
                    "resp_rate" -> day.respRateBpm
                    "restorative_pct" -> day.totalSleepMin?.takeIf { it > 0 }?.let { total ->
                        day.deepMin?.let { deep -> day.remMin?.let { rem -> (deep + rem) / total * 100 } }
                    }
                    "hours_vs_needed_pct" -> needByDay[day.day]?.takeIf { it > 0 }?.let { importedNeed ->
                        day.totalSleepMin?.let { it / importedNeed * 100 }
                    } ?: hoursParts[day.day] ?: day.totalSleepMin?.takeIf { it > 0 && need > 0 }?.let { it / need * 100 }
                    else -> null
                }
                if (value != null) stored[day.day] = value
            }
        }
        currentCoroutineContext().ensureActive()
        points = stored.entries.sortedBy { it.key }.map { it.key to it.value }
    }
    val title = stringResource(when (resolvedKey) {
        "sleep_performance" -> R.string.broop_overview_sleep_performance
        "sleep_total_min" -> R.string.broop_overview_hours_sleep
        "resp_rate" -> R.string.broop_overview_resp
        "sleep_efficiency" -> R.string.broop_overview_efficiency
        "sleep_consistency" -> R.string.broop_overview_consistency
        "restorative_pct" -> R.string.broop_overview_restorative
        "hours_vs_needed_pct" -> R.string.broop_overview_hours_needed
        "sleep_debt_min" -> R.string.l10n_sleep_screen_sleep_debt_ledger_8cc9a992
        "sleep_stress_pct" -> R.string.broop_overview_sleep_stress
        "hr_zones13_min" -> R.string.broop_overview_zones_low
        "hr_zones45_min" -> R.string.broop_overview_zones_high
        else -> R.string.broop_overview_trends
    })
    val minutes = resolvedKey.endsWith("_min")
    fun format(value: Double): String = when {
        minutes -> hoursMinutes(value)
        resolvedKey == "resp_rate" -> String.format(Locale.getDefault(), "%.1f rpm", value)
        else -> "${value.roundToInt()}%"
    }
    val end = points.lastOrNull()?.first?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: LocalDate.now()
    val filtered = if (range == 0) points else points.filter { it.first >= end.minusDays(range.toLong() - 1).toString() }
    BroopPage(title, onBack) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            listOf(14, 30, 0).forEach { count ->
                TextButton(onClick = { range = count }) {
                    Text(stringResource(when (count) { 14 -> R.string.broop_overview_14_days; 30 -> R.string.broop_overview_30_days; else -> R.string.broop_overview_all_days }),
                        color = if (range == count) BroopPalette.textPrimary else BroopPalette.textSecondary)
                }
            }
        }
        if (filtered.isEmpty()) BroopEmpty(stringResource(R.string.broop_overview_no_data), stringResource(R.string.broop_overview_metric_empty))
        else BroopCard {
            val latest = filtered.last()
            Text(format(latest.second), style = BroopType.largeNumber, color = BroopPalette.textPrimary)
            Text(lastChargeDateLabel(latest.first), style = BroopType.caption, color = BroopPalette.textSecondary)
            if (filtered.size >= 2) LineChart(filtered.map { it.second }, Modifier.fillMaxWidth().height(BroopMetrics.ring * 2),
                BroopPalette.rest, selectionEnabled = true, selectionLabels = filtered.map { lastChargeDateLabel(it.first) }, formatValue = ::format)
            Text(stringResource(R.string.broop_overview_period_average, format(filtered.map { it.second }.average())), style = BroopType.caption, color = BroopPalette.textBody)
        }
    }
}
