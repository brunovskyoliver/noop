package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import java.time.LocalDate
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

private data class BroopTrendMetric(val key: String, val title: Int)

/** Deep-dive metric/range controls and press-to-read, ending on the selected calendar day. */
@Composable
internal fun BroopOverviewTrendCard(vm: AppViewModel, snap: BroopOverviewSnapshot?, score: String, onNavigate: (String) -> Unit) {
    val metrics = remember(score) { when (score) {
        "rest" -> listOf(BroopTrendMetric("sleep_performance", R.string.broop_overview_sleep_performance),
            BroopTrendMetric("sleep_total_min", R.string.broop_overview_hours_sleep), BroopTrendMetric("sleep_efficiency", R.string.broop_overview_efficiency))
        "charge" -> listOf(BroopTrendMetric("recovery", R.string.broop_overview_charge), BroopTrendMetric("hrv", R.string.broop_overview_hrv),
            BroopTrendMetric("rhr", R.string.broop_overview_rhr), BroopTrendMetric("resp_rate", R.string.broop_overview_resp))
        else -> listOf(BroopTrendMetric("strain", R.string.broop_overview_effort), BroopTrendMetric("steps", R.string.broop_overview_steps),
            BroopTrendMetric("active_kcal", R.string.broop_overview_calories))
    } }
    var metricIndex by remember(score) { mutableIntStateOf(0) }
    var range by remember(score) { mutableIntStateOf(7) }
    var menu by remember { mutableStateOf(false) }
    var history by remember { mutableStateOf<List<Pair<String, Double>>?>(null) }
    val syncRevision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val scale = UnitPrefs.effortScale(LocalContext.current)
    val metric = metrics[metricIndex]
    val day = snap?.dayKey ?: logicalDayKeyNow()
    LaunchedEffect(metric.key, day, snap?.days, syncRevision, vm.activeStrapId, scale) {
        history = null
        val values = runCatching { vm.repo.resolvedSeries(metric.key, if (metric.key == "active_kcal") "apple-health" else "my-whoop", "0000-00-00", day,
            strapDeviceId = vm.activeStrapId).values.toMap() }.getOrDefault(emptyMap()).toMutableMap()
        if (metric.key == "sleep_performance") snap?.restSeries?.forEach { (d, v) -> if (d <= day) values.putIfAbsent(d, v) }
        snap?.days?.filter { it.day <= day }?.forEach { d ->
            val v = when (metric.key) {
                "sleep_total_min" -> d.totalSleepMin
                "sleep_efficiency" -> d.efficiency
                "recovery" -> d.recovery
                "hrv" -> d.avgHrv
                "rhr" -> d.restingHr?.toDouble()
                "resp_rate" -> d.respRateBpm
                "strain" -> d.strain
                "steps" -> d.steps?.toDouble()
                "active_kcal" -> null
                else -> null
            }
            if (v != null) values.putIfAbsent(d.day, v)
        }
        currentCoroutineContext().ensureActive()
        history = values.entries.filter { it.value.isFinite() && it.key <= day }.sortedBy { it.key }.map { (d, v) -> d to when {
            metric.key == "strain" -> UnitFormatter.effortValue(v, scale)
            metric.key == "sleep_efficiency" && v <= 1 -> v * 100
            else -> v
        } }
    }
    fun format(v: Double): String = when (metric.key) {
        "sleep_total_min" -> hoursMinutes(v)
        "sleep_performance", "sleep_efficiency", "recovery" -> "${v.roundToInt()}%"
        "strain", "resp_rate" -> String.format(Locale.getDefault(), "%.1f", v)
        else -> String.format(Locale.getDefault(), "%,d", v.roundToInt())
    }
    val end = LocalDate.parse(day)
    val first = end.minusDays(range.toLong() - 1).toString()
    val points = history.orEmpty().filter { it.first in first..day }
    val prior = history.orEmpty().filter { it.first >= end.minusDays(range.toLong() * 2 - 1).toString() && it.first < first }
    BroopSection(stringResource(R.string.broop_overview_trends))
    BroopCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { menu = true }) { Text(stringResource(metric.title), color = BroopPalette.textPrimary) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                metrics.forEachIndexed { index, item -> DropdownMenuItem(text = { Text(stringResource(item.title)) },
                    onClick = { metricIndex = index; menu = false }) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            listOf(7, 30, 182).forEach { count -> TextButton(onClick = { range = count }) {
                Text(stringResource(when (count) { 7 -> R.string.broop_overview_7_days; 30 -> R.string.broop_overview_30_days; else -> R.string.broop_overview_6_months }),
                    color = if (count == range) BroopPalette.textPrimary else BroopPalette.textSecondary)
            } }
        }
        if (points.isNotEmpty()) {
            val mean = points.map { it.second }.average()
            Text(stringResource(R.string.broop_overview_period_average, format(mean)), style = BroopType.section, color = BroopPalette.textPrimary)
            if (prior.isNotEmpty()) Text(stringResource(R.string.broop_overview_previous_period, format(prior.map { it.second }.average())),
                style = BroopType.caption, color = BroopPalette.textSecondary)
            if (points.size >= 2) LineChart(points.map { it.second }, Modifier.fillMaxWidth().height(BroopMetrics.ring * 1.5f),
                if (score == "effort") BroopPalette.effort else BroopPalette.rest, selectionEnabled = true,
                selectionLabels = points.map { lastChargeDateLabel(it.first) }, formatValue = ::format)
            else Text(format(points.single().second), style = BroopType.number, color = BroopPalette.textBody)
        } else Text(stringResource(R.string.broop_overview_baseline_building), style = BroopType.body, color = BroopPalette.textSecondary)
        BroopRow(stringResource(metric.title)) { onNavigate("vital_detail/${when (metric.key) {
            "steps" -> "steps_est"; "resp_rate" -> "resp"; else -> metric.key
        }}") }
    }
}
