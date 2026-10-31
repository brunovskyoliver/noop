package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.noop.R
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.noop.analytics.DaytimeStress
import com.noop.analytics.StressMonitor
import com.noop.data.StressAnalysisStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor

internal data class BroopStressLoad(val day: String, val result: StressMonitor.DayResult? = null, val loading: Boolean = true, val failed: Boolean = false)

@Composable
internal fun rememberBroopStressDay(vm: AppViewModel, day: String): State<BroopStressLoad> {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val sync by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val workouts by vm.workouts.collectAsStateWithLifecycle()
    val device = vm.activeStrapId
    return androidx.compose.runtime.key(vm, device, day) {
        produceState(BroopStressLoad(day), days, sync, workouts) {
        value = BroopStressLoad(day)
        do {
            try {
                val result = withContext(Dispatchers.Default) { StressAnalysisStore.analyzeDay(vm.repo, device, day) }
                value = BroopStressLoad(day, result, loading = false)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { value = BroopStressLoad(day, loading = false, failed = true) }
            if (day != LocalDate.now().toString()) break
            delay(60_000)
        } while (isActive)
        }
    }
}

/** A single packet window per app model, shared by Home, Health and the Stress screen. */
internal class BroopStressLiveSampler(private val vm: AppViewModel) {
    var reading by mutableStateOf<StressMonitor.LiveReading?>(null)
        private set
    private val window = StressMonitor.LiveWindow()
    private var clients = 0
    private var wake: StressMonitor.WakeReference? = null
    private var scopeKey: String? = null
    private var job: Job? = null
    fun attach(reference: StressMonitor.WakeReference, day: String, device: String) {
        val key = "$day|$device"
        if (scopeKey != key) { window.reset(); reading = null }
        scopeKey = key
        wake = reference
        clients++
        if (job != null) return
        vm.requestRealtimeHr()
        job = vm.viewModelScope.launch {
            coroutineScope {
                launch {
                    vm.ble.heartRatePackets.collect { (ts, bpm) ->
                        if (vm.live.value.connected) { window.receive(bpm.toDouble(), ts); tick() }
                    }
                }
                launch {
                    vm.live.rrPackets().collect { rr ->
                        val valid = rr.filter { it in 273..2000 }
                        if (vm.live.value.connected && valid.isNotEmpty()) {
                            window.receive(60000.0 / valid.average(), System.currentTimeMillis() / 1000)
                            tick()
                        }
                    }
                }
                while (isActive) { tick(); delay(1000) }
            }
        }
    }
    fun detach() {
        clients = (clients - 1).coerceAtLeast(0)
        if (clients > 0) return
        job?.cancel(); job = null
        vm.releaseRealtimeHr()
        window.reset(); reading = null; scopeKey = null; wake = null
    }
    private fun tick() {
        val now = System.currentTimeMillis() / 1000
        if (scopeKey?.startsWith(LocalDate.now().toString() + "|") != true || !vm.live.value.connected) {
            window.reset(); reading = null; return
        }
        window.expire(now)
        val ref = wake ?: return
        val latestWorkout = vm.workouts.value.maxByOrNull { it.endTs }
        val inShadow = latestWorkout != null && now - latestWorkout.endTs in 0..899 &&
            (window.meanHR ?: 0.0) > ref.floorHR + DaytimeStress.postActivityShadowBpm
        val next = if (window.meanHR == null) null else if (vm.activeWorkout.value != null || inShadow) StressMonitor.LiveReading.Active
            else window.reading(ref)
        reading = when (next) {
            is StressMonitor.LiveReading.Level -> StressMonitor.LiveReading.Level(floor(next.value * 10 + 0.5) / 10)
            else -> next
        }
    }
}

internal data class BroopStressNow(val level: Double?, val active: Boolean, val ts: Long, val live: Boolean)

@Composable
internal fun rememberBroopStressNow(vm: AppViewModel, result: StressMonitor.DayResult?): BroopStressNow? {
    val today = result?.day == LocalDate.now().toString()
    DisposableEffect(vm, result?.wake, today, vm.activeStrapId) {
        val ref = result?.wake
        if (today && ref != null) vm.broopStressLive.attach(ref, result.day, vm.activeStrapId)
        onDispose { if (today && ref != null) vm.broopStressLive.detach() }
    }
    val now = System.currentTimeMillis() / 1000
    if (today) when (val live = vm.broopStressLive.reading) {
        is StressMonitor.LiveReading.Level -> return BroopStressNow(live.value, false, now, true)
        StressMonitor.LiveReading.Active -> return BroopStressNow(null, true, now, true)
        null -> Unit
    }
    val latest = result?.latest ?: return null
    return BroopStressNow(latest.level, false, minOf(now, latest.startTs + StressMonitor.epochSeconds), false)
}

@Composable
fun BroopStressScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    var offset by rememberSaveable { mutableStateOf(0L) }
    val day = LocalDate.now().minusDays(offset).toString()
    val load by rememberBroopStressDay(vm, day)
    val result = load.result.takeIf { load.day == day }
    val current = rememberBroopStressNow(vm, result)
    val summary = result?.summary
    val lastScoredTime = current?.let {
        DateTimeFormatter.ofPattern(if (ClockPrefs.uses24Hour(context)) "HH:mm" else "h:mm a", Locale.getDefault())
            .withZone(ZoneId.systemDefault()).format(Instant.ofEpochSecond(it.ts))
    }
    BroopPage(stringResource(R.string.broop_stress_monitor)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { offset++ }) { Text(stringResource(R.string.broop_previous)) }
            Text(if (offset == 0L) stringResource(R.string.broop_today) else day, style = BroopType.demi, color = BroopPalette.textPrimary)
            TextButton(onClick = { offset-- }, enabled = offset > 0) { Text(stringResource(R.string.broop_next)) }
        }
        BroopCard {
            BroopCaps(stringResource(if (current?.live == true) R.string.broop_stress_live else R.string.broop_stress_latest))
            Text(if (current?.active == true) stringResource(R.string.broop_stress_active) else current?.level?.let(::broopOne) ?: "--",
                style = BroopType.largeNumber, color = BroopPalette.textPrimary)
            Text(when {
                load.loading -> stringResource(R.string.broop_stress_loading)
                load.failed -> stringResource(R.string.broop_stress_failed)
                current == null -> stringResource(R.string.broop_stress_empty)
                current.active -> stringResource(R.string.broop_stress_activity_excluded)
                current.live -> stringResource(R.string.broop_stress_live_detail)
                else -> stringResource(R.string.broop_stress_last_scored, lastScoredTime.orEmpty())
            }, style = BroopType.body, color = BroopPalette.textBody)
            val ref = result?.wake
            if (ref != null) Text(if (ref.personal) stringResource(R.string.broop_stress_personal_baseline, ref.days)
                else stringResource(R.string.broop_stress_calibrating), style = BroopType.caption, color = BroopPalette.textBody)
        }
        BroopSection(stringResource(R.string.broop_stress_your_day))
        if (result != null) {
            BroopStressTimeline(result.epochs)
            BroopCard {
                BroopBodyValue(stringResource(R.string.broop_stress_waking_average), summary?.meanLevel?.let(::broopOne) ?: "--")
                BroopBodyValue(stringResource(R.string.broop_stress_low), stringResource(R.string.broop_minutes, summary?.lowMin ?: 0))
                BroopBodyValue(stringResource(R.string.broop_stress_medium), stringResource(R.string.broop_minutes, summary?.medMin ?: 0))
                BroopBodyValue(stringResource(R.string.broop_stress_high), stringResource(R.string.broop_minutes, summary?.highMin ?: 0))
                BroopBodyValue(stringResource(R.string.broop_stress_scored_waking), stringResource(R.string.broop_minutes, summary?.scoredMin ?: 0))
                BroopBodyValue(stringResource(R.string.broop_stress_sleep_high), summary?.sleepStressPct?.let { "${broopOne(it)}%" } ?: "--")
            }
        }
        BroopRow(stringResource(R.string.nav_breathe), stringResource(R.string.broop_stress_breathe_detail)) { onNavigate("breathe") }
        BroopRow(stringResource(R.string.explore_category_mind), stringResource(R.string.broop_stress_mind_detail)) { onNavigate("mind") }
        BroopCard {
            BroopCaps(stringResource(R.string.broop_stress_method_title))
            Text(stringResource(R.string.broop_stress_method), style = BroopType.body, color = BroopPalette.textBody)
        }
    }
}

@Composable
private fun BroopStressTimeline(epochs: List<StressMonitor.Epoch>) {
    val timelineDescription = stringResource(R.string.broop_stress_timeline_description, epochs.count { it.level != null })
    BroopCard {
        Canvas(Modifier.fillMaxWidth().height(Metrics.chartHeight).semantics {
            contentDescription = timelineDescription
        }) {
            if (epochs.isEmpty()) return@Canvas
            val start = epochs.first().startTs
            val date = Instant.ofEpochSecond(start).atZone(ZoneId.systemDefault()).toLocalDate()
            val end = date.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toEpochSecond()
            val span = (end - start).coerceAtLeast(1)
            val width = size.width * StressMonitor.epochSeconds / span
            for (epoch in epochs) {
                val x = (epoch.startTs - start).toFloat() / span * size.width
                val level = epoch.level
                val colour = when (epoch.state) {
                    StressMonitor.EpochState.SLEEP -> BroopPalette.rest
                    StressMonitor.EpochState.ACTIVITY -> BroopPalette.teal
                    else -> if (level == null) continue else if (level >= 2) BroopPalette.warning else if (level >= 1) BroopPalette.effort else BroopPalette.rest
                }
                val height = if (level != null) size.height * (level / 3).toFloat().coerceIn(0.02f, 1f) else size.height * 0.04f
                drawRect(colour, Offset(x, size.height - height), Size(width.coerceAtLeast(1f), height))
            }
        }
        Text(stringResource(R.string.broop_stress_legend),
            style = BroopType.caption, color = BroopPalette.textBody)
    }
}
