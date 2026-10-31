package com.noop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.data.SleepSession
import com.noop.data.StressAnalysisStore
import com.noop.data.WorkoutRow
import com.noop.protocol.DeviceFamily
import java.time.ZoneId
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive

/** Match OverviewHRChart: sleep uses strict overlap and full duration, workouts keep edge touches. */
internal fun broopTimelineMainSleep(candidates: List<SleepSession>, window: LongRange): SleepSession? =
    candidates.filter { it.endTs > window.first && it.effectiveStartTs < window.last }
        .maxByOrNull { it.endTs - it.effectiveStartTs }

internal fun broopTimelineWorkouts(candidates: List<WorkoutRow>, window: LongRange): List<WorkoutRow> =
    candidates.filter { it.endTs >= window.first && it.startTs <= window.last }

/** The Broop selected-day timeline shares the native raw/bucket reader and pinch/pan arithmetic. */
@Composable
fun BroopOverviewDayChartScreen(vm: AppViewModel) {
    val state = rememberBroopOverview(vm)
    val snap = state.snapshot
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val revision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val deviceId = vm.activeStrapId
    val context = LocalContext.current
    val dayStart = logicalDayNow().minusDays(state.dayOffset.toLong()).atStartOfDay(ZoneId.systemDefault()).toEpochSecond()
    val dayBounds = dayStart..(dayStart + 86_400)
    val panBounds = (dayStart - 2 * 86_400)..dayBounds.last
    var metric by remember { mutableStateOf(TimelineMetric.Hr) }
    var owned by remember { mutableStateOf(true) }
    var window by remember(dayStart) { mutableStateOf<LongRange?>(null) }
    val visible = window ?: dayBounds
    var sourceName by remember(deviceId) { mutableStateOf<String?>(null) }
    var unsupported by remember(deviceId, metric) { mutableStateOf(false) }
    var points by remember(dayStart, metric, deviceId) { mutableStateOf<List<TimelinePoint>>(emptyList()) }
    var loading by remember(dayStart, metric, deviceId) { mutableStateOf(true) }
    var failed by remember(dayStart, metric, deviceId) { mutableStateOf(false) }
    var sleep by remember(dayStart, deviceId) { mutableStateOf<SleepSession?>(null) }
    var workouts by remember(dayStart, deviceId) { mutableStateOf<List<WorkoutRow>>(emptyList()) }
    val bucket = timelineBucketSeconds(visible.last - visible.first, targetPoints = 600)
    val temperatureUnit = UnitPrefs.temperature(context)
    val displayPoints = remember(points, metric, temperatureUnit) {
        if (metric == TimelineMetric.SkinTemp && temperatureUnit == TemperatureUnit.FAHRENHEIT)
            points.map { it.copy(value = UnitFormatter.celsiusToFahrenheit(it.value)) } else points
    }
    val color = when (metric) {
        TimelineMetric.Hr, TimelineMetric.BandSleepState -> BroopPalette.rest
        TimelineMetric.Hrv, TimelineMetric.Spo2 -> BroopPalette.stageREM
        TimelineMetric.SkinTemp -> BroopPalette.warning
        else -> BroopPalette.textSecondary
    }
    val ticks = remember(visible) { chartTimeTicks(visible.first, visible.last, ZoneId.systemDefault(), deepZoom = true) }
    LaunchedEffect(deviceId, metric, revision) {
        try {
            val d = vm.pairedDevices().firstOrNull { it.id == deviceId }
            sourceName = d?.let(::displayName)
            val noStream = if (!DeviceFamily.isWhoop5Registry(d?.model, d?.brand)) false else when (metric) {
                TimelineMetric.Spo2 -> vm.repo.spo2Samples(deviceId, 0, System.currentTimeMillis() / 1000, 1).isEmpty()
                TimelineMetric.Respiration -> vm.repo.respSamples(deviceId, 0, System.currentTimeMillis() / 1000, 1).isEmpty()
                else -> false
            }
            currentCoroutineContext().ensureActive()
            unsupported = noStream
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (_: Exception) { unsupported = false }
    }
    LaunchedEffect(metric, owned, visible, revision, days, deviceId) {
        delay(130)
        loading = true
        failed = false
        try {
            val result = readTimeline(vm, deviceId, metric, visible.first, visible.last, bucket)
            currentCoroutineContext().ensureActive()
            points = result
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (_: Exception) { failed = true; points = emptyList() }
        loading = false
    }
    LaunchedEffect(dayStart, revision, days, deviceId) {
        try {
            val sessions = StressAnalysisStore.allSleepSessions(vm.repo, deviceId, dayStart - 3 * 86_400, dayBounds.last)
            val activities = StressAnalysisStore.allWorkouts(vm.repo, deviceId, dayStart - 3 * 86_400, dayBounds.last)
            currentCoroutineContext().ensureActive()
            sleep = broopTimelineMainSleep(sessions, dayBounds)
            workouts = broopTimelineWorkouts(activities, dayBounds)
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (_: Exception) { sleep = null; workouts = emptyList() }
    }
    Column(Modifier.fillMaxSize().background(BroopPalette.background)) {
        BroopOverviewDateNav(state, broopOverviewMaxOffset(days, logicalDayNow()), Modifier.fillMaxWidth())
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = BroopMetrics.page)
            .padding(bottom = BroopMetrics.tabBarClearance), verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                BroopCaps(metric.title)
                BroopTimelineSyncedLabel(vm)
            }
            BroopCard {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    BroopTimelineStat(stringResource(R.string.broop_overview_sleep), snap?.asleepMinutes?.let(::hoursMinutes) ?: "—")
                    BroopTimelineStat(stringResource(R.string.broop_overview_charge), snap?.charge?.let { "${it.roundToInt()}%" } ?: "—",
                        snap?.charge?.let(BroopPalette::band) ?: BroopPalette.textSecondary)
                    BroopTimelineStat(stringResource(R.string.broop_overview_effort), snap?.effort?.let {
                        String.format(Locale.getDefault(), "%.1f", it) } ?: "—", BroopPalette.effort)
                }
            }
            if (displayPoints.isEmpty()) Box(Modifier.fillMaxWidth().height(BroopMetrics.ring * 4f), contentAlignment = Alignment.Center) {
                if (loading) CircularProgressIndicator(color = BroopPalette.textSecondary) else BroopEmpty(
                    stringResource(R.string.broop_overview_no_data), stringResource(when {
                        failed -> R.string.broop_overview_chart_read_failed
                        owned && unsupported && metric == TimelineMetric.Spo2 -> R.string.timeline_spo2_not_on_whoop5
                        owned && unsupported && metric == TimelineMetric.Respiration -> R.string.timeline_resp_not_on_whoop5
                        owned -> R.string.timeline_nothing_offloaded
                        else -> R.string.timeline_other_sources_no_offload
                    }))
            } else {
                val is24h = ClockPrefs.uses24Hour(context)
                val format: (Double) -> String = { broopTimelineValue(metric, it, temperatureUnit) }
                BroopTimelinePlot(displayPoints, visible, panBounds, color, ticks, sleep, workouts,
                    snap?.charge?.let { charge -> snap.night?.session?.endTs?.let { ts -> BroopTimelineMarker(ts,
                        stringResource(R.string.broop_overview_chart_charge_marker, charge.roundToInt()), BroopPalette.band(charge)) } },
                    snap?.effort?.let { effort -> points.lastOrNull()?.let { BroopTimelineMarker(it.ts,
                        stringResource(R.string.broop_overview_chart_effort_marker, String.format(Locale.getDefault(), "%.1f", effort)), BroopPalette.effort) } },
                    format = format, time = { clockTimeLabel(it, is24h) }, onWindowChange = { window = it })
                TimelineTimeAxisLabels(ticks, visible.first, visible.last)
                val values = displayPoints.map { it.value }
                BroopCard {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        BroopTimelineStat(stringResource(R.string.timeline_min), format(values.min()))
                        BroopTimelineStat(stringResource(R.string.timeline_avg), format(values.average()))
                        BroopTimelineStat(stringResource(R.string.timeline_max), format(values.max()))
                        BroopTimelineStat(stringResource(R.string.broop_overview_chart_resolution),
                            stringResource(if (bucket >= 60) R.string.broop_overview_chart_minutes else R.string.broop_overview_chart_seconds,
                                if (bucket >= 60) bucket / 60 else bucket))
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(if (window == null) R.string.timeline_pinch_to_zoom else R.string.timeline_zoomed_in),
                    style = BroopType.caption, color = BroopPalette.textSecondary, modifier = Modifier.weight(1f))
                if (window != null) TextButton(onClick = { window = null }) { Text(stringResource(R.string.timeline_reset), color = BroopPalette.textPrimary) }
            }
            BroopCaps(stringResource(R.string.broop_overview_chart_metric), BroopPalette.textSecondary)
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                SegmentedPillControl(TimelineMetric.entries.toList(), metric, { it.title }, { metric = it })
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(sourceName ?: stringResource(R.string.timeline_my_whoop), style = BroopType.body,
                    color = BroopPalette.textBody, modifier = Modifier.weight(1f))
                val ownedLabel = stringResource(R.string.timeline_owned)
                val allLabel = stringResource(R.string.timeline_all)
                SegmentedPillControl(listOf(true, false), owned, { if (it) ownedLabel else allLabel }, { owned = it })
            }
        }
    }
}

@Composable
private fun BroopTimelineSyncedLabel(vm: AppViewModel) {
    val live by vm.live.collectAsStateWithLifecycle()
    val is24h = ClockPrefs.uses24Hour(LocalContext.current)
    live.lastSyncAt?.let { Text(stringResource(R.string.broop_overview_chart_synced, clockTimeLabel(it, is24h)),
        style = BroopType.caption, color = BroopPalette.textSecondary) }
}

@Composable
private fun BroopTimelineStat(label: String, value: String, color: Color = BroopPalette.textPrimary) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        BroopCaps(label, BroopPalette.textSecondary)
        Text(value, style = BroopType.demi, color = color, maxLines = 1)
    }
}

private fun broopTimelineValue(metric: TimelineMetric, value: Double, unit: TemperatureUnit): String = when (metric) {
    TimelineMetric.Hr, TimelineMetric.Respiration, TimelineMetric.Hrv, TimelineMetric.Movement -> value.roundToInt().toString()
    TimelineMetric.SkinTemp -> String.format(Locale.getDefault(), "%.1f", value) + UnitFormatter.temperatureUnit(unit)
    TimelineMetric.Spo2, TimelineMetric.Motion -> String.format(Locale.getDefault(), "%.2f", value)
    TimelineMetric.BandSleepState -> when (value.roundToInt()) {
        in 0..3 -> uiString(when (value.roundToInt()) {
        0 -> R.string.broop_overview_chart_band_wake
        1 -> R.string.broop_overview_chart_band_still
        2 -> R.string.broop_overview_chart_band_asleep
        else -> R.string.broop_overview_chart_band_up
        })
        else -> value.roundToInt().toString()
    }
}

private data class BroopTimelineMarker(val ts: Long, val label: String, val color: Color)

@Composable
private fun BroopTimelinePlot(
    points: List<TimelinePoint>, window: LongRange, bounds: LongRange, color: Color, ticks: List<Pair<Long, String>>,
    sleep: SleepSession?, workouts: List<WorkoutRow>, charge: BroopTimelineMarker?, effort: BroopTimelineMarker?,
    format: (Double) -> String, time: (Long) -> String, onWindowChange: (LongRange) -> Unit,
) {
    var selected by remember(points, window) { mutableStateOf<TimelinePoint?>(null) }
    val sleepLabel = stringResource(R.string.broop_overview_sleep)
    val workoutsLabel = stringResource(R.string.broop_overview_chart_workouts, workouts.size)
    val annotations = listOfNotNull(sleep?.let { stringResource(R.string.broop_overview_chart_sleep_span, sleepLabel,
        time(it.effectiveStartTs), time(it.endTs)) },
        workoutsLabel.takeIf { workouts.isNotEmpty() }, charge?.label, effort?.label).joinToString(". ")
    val span = (window.last - window.first).coerceAtLeast(1)
    val restColor = BroopPalette.rest
    val workoutColor = BroopPalette.effort
    val markerColor = BroopPalette.textPrimary
    Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
        Box(Modifier.fillMaxWidth().height(BroopMetrics.ring * 4f).clipToBounds()
            .semantics { contentDescription = annotations }
            .pointerInput(points, window) {
                fun select(x: Float) {
                    val ts = window.first + (x.coerceIn(0f, size.width.toFloat()) / size.width.coerceAtLeast(1) * span).toLong()
                    selected = points.minByOrNull { abs(it.ts - ts) }
                }
                detectDragGesturesAfterLongPress(onDragStart = { select(it.x) }, onDragEnd = { selected = null },
                    onDragCancel = { selected = null }, onDrag = { change, _ -> change.consume(); select(change.position.x) })
            }) {
            Canvas(Modifier.fillMaxSize()) {
                fun x(ts: Long) = (ts - window.first).toFloat() / span * size.width
                sleep?.let { s ->
                    val left = x(s.effectiveStartTs).coerceIn(0f, size.width)
                    val right = x(s.endTs).coerceIn(0f, size.width)
                    if (right > left) drawRect(restColor.copy(alpha = 0.14f), Offset(left, 0f), Size(right - left, size.height))
                }
            }
            TimelineChart(points, window.first, window.last, bounds, color, Modifier.fillMaxSize(), onWindowChange, ticks)
            Canvas(Modifier.fillMaxSize()) {
                fun x(ts: Long) = (ts - window.first).toFloat() / span * size.width
                val stroke = BroopMetrics.ringStroke.toPx() / 3
                workouts.forEach { w ->
                    val left = x(w.startTs).coerceIn(0f, size.width)
                    val right = x(w.endTs).coerceIn(0f, size.width)
                    if (w.endTs >= window.first && w.startTs <= window.last) {
                        drawLine(workoutColor, Offset(left, size.height - stroke), Offset(right, size.height - stroke), stroke * 2)
                        drawCircle(workoutColor, BroopMetrics.compactGap.toPx() / 2, Offset((left + right) / 2, size.height - stroke * 3))
                    }
                }
                listOfNotNull(charge, effort).filter { it.ts in window }.forEach { marker ->
                    val px = x(marker.ts)
                    drawLine(marker.color.copy(alpha = 0.65f), Offset(px, 0f), Offset(px, size.height), stroke,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(stroke * 3, stroke * 3)))
                    drawCircle(marker.color, BroopMetrics.compactGap.toPx(), Offset(px, BroopMetrics.gap.toPx()))
                }
                selected?.let { p -> drawLine(markerColor, Offset(x(p.ts), 0f), Offset(x(p.ts), size.height), stroke) }
            }
            selected?.let { p -> Text(stringResource(R.string.broop_overview_chart_readout, time(p.ts), format(p.value)), style = BroopType.demi, color = BroopPalette.textPrimary,
                modifier = Modifier.align(Alignment.TopCenter).background(BroopPalette.pillOuter).padding(BroopMetrics.gap)) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            charge?.takeIf { it.ts in window }?.let { Text(it.label, style = BroopType.caption, color = it.color) }
            Spacer(Modifier.weight(1f))
            effort?.takeIf { it.ts in window }?.let { Text(it.label, style = BroopType.caption, color = it.color) }
        }
        sleep?.takeIf { it.endTs > window.first && it.effectiveStartTs < window.last }?.let {
            Text(stringResource(R.string.broop_overview_chart_sleep_span, sleepLabel, time(it.effectiveStartTs), time(it.endTs)),
                style = BroopType.caption, color = BroopPalette.rest)
        }
        workouts.filter { it.endTs >= window.first && it.startTs <= window.last }.forEach {
            Text(stringResource(R.string.broop_overview_chart_activity_span, WorkoutEditing.displaySport(it), time(it.startTs), time(it.endTs)),
                style = BroopType.caption, color = BroopPalette.effort)
        }
    }
}
