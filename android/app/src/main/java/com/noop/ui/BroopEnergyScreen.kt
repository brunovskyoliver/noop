package com.noop.ui

import com.noop.R

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.BroopEnergyEngine
import com.noop.analytics.StrainScorer
import com.noop.analytics.StressMonitor
import com.noop.data.StressAnalysisStore
import com.noop.data.MetricSeriesRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import kotlin.math.roundToInt

/** One day resolver for the chart and current level; raw-data retention never rewrites a stored day. */
internal suspend fun readBroopEnergyDay(vm: AppViewModel, dayKey: String): BroopEnergyEngine.DayResult? {
    val stress = StressAnalysisStore.analyzeDay(vm.repo, vm.activeStrapId, dayKey) ?: return null
    val previous = LocalDate.parse(dayKey).minusDays(1).toString()
    val start = StressAnalysisStore.storedValues(vm.repo, vm.activeStrapId, BroopEnergyEngine.keys, previous, previous)[previous]?.get("energy_end")
    val profile = ProfileStore.from(vm.getApplication<android.app.Application>())
    val resting = vm.repo.daysMerged(vm.activeStrapId).firstOrNull { it.day == dayKey }?.restingHr?.toDouble() ?: StrainScorer.defaultRestingHR
    val maxHR = profile.hrMaxOverride.takeIf { it > 0 }?.toDouble() ?: StrainScorer.tanakaHRmax(profile.age.toDouble())
    return BroopEnergyEngine.fromStress(stress, start, BroopEnergyEngine.HeartProfile(resting, maxHR))
}

internal data class BroopEnergyLoad(val result: BroopEnergyEngine.DayResult?, val summary: BroopEnergyEngine.Summary?,
    val now: BroopEnergyEngine.Now?, val points: List<BroopEnergyEngine.Point>, val loading: Boolean, val failed: Boolean)

private data class BroopEnergyInputs(val heart: BroopEnergyEngine.HeartProfile, val values: Map<String, Map<String, Double>>)

/** Home, Health and Energy share this day resolver and the same live stress sampler. */
@Composable
internal fun rememberBroopEnergyDay(vm: AppViewModel, dayKey: String): BroopEnergyLoad {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val sync by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val stress by rememberBroopStressDay(vm, dayKey)
    val stressResult = stress.result.takeIf { stress.day == dayKey }
    val stressNow = rememberBroopStressNow(vm, stressResult)
    val context = LocalContext.current
    val profile = ProfileStore.from(context.applicationContext)
    val maxHR = profile.hrMaxOverride.takeIf { it > 0 }?.toDouble() ?: StrainScorer.tanakaHRmax(profile.age.toDouble())
    var inputs by remember(vm.activeStrapId, dayKey) { mutableStateOf<BroopEnergyInputs?>(null) }
    var loading by remember(vm.activeStrapId, dayKey) { mutableStateOf(true) }
    var failed by remember(vm.activeStrapId, dayKey) { mutableStateOf(false) }
    val previous = LocalDate.parse(dayKey).minusDays(1).toString()
    LaunchedEffect(vm.activeStrapId, dayKey, days, sync, maxHR) {
        loading = true; failed = false; inputs = null
        try { inputs = withContext(Dispatchers.IO) {
            val resting = vm.repo.daysMerged(vm.activeStrapId).firstOrNull { it.day == dayKey }?.restingHr?.toDouble()
                ?: StrainScorer.defaultRestingHR
            BroopEnergyInputs(BroopEnergyEngine.HeartProfile(resting, maxHR),
                StressAnalysisStore.storedValues(vm.repo, vm.activeStrapId, BroopEnergyEngine.keys, previous, dayKey))
        } }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { failed = true }
        loading = false
    }
    val result = remember(stressResult, inputs, loading) {
        val loaded = inputs
        if (loading || loaded == null) null else stressResult?.let {
            BroopEnergyEngine.fromStress(it, loaded.values[previous]?.get("energy_end"), loaded.heart)
        }
    }
    val stored = inputs?.values?.get(dayKey)?.let { BroopEnergyEngine.fromStored(dayKey, it) }
    val isToday = dayKey == LocalDate.now().toString()
    val summary = if (isToday) result?.summary ?: stored else stored ?: result?.summary
    val now = if (isToday) inputs?.heart?.let { BroopEnergyEngine.now(result, stressNow?.takeIf { it.live }?.level, it, System.currentTimeMillis() / 1000) } else null
    val points = result?.takeIf { fresh -> summary?.let { kotlin.math.abs(fresh.summary.end - it.end) < 0.5 &&
        kotlin.math.abs(fresh.summary.charged - it.charged) < 0.5 && kotlin.math.abs(fresh.summary.drained - it.drained) < 0.5 } == true }?.points.orEmpty()
    return BroopEnergyLoad(result, summary, now, points, loading || stress.loading, failed || stress.failed)
}


@Composable
internal fun BroopEnergyCard(vm: AppViewModel, day: String = LocalDate.now().toString(), onClick: () -> Unit) {
    BroopEnergyCard(rememberBroopEnergyDay(vm, day), onClick)
}

@Composable
internal fun BroopEnergyCard(energy: BroopEnergyLoad, onClick: () -> Unit) {
    val level = energy.now?.level ?: energy.summary?.end
    BroopCard(onClick = onClick) {
        BroopCaps(listOfNotNull(uiString(R.string.broop_body_energy_437bcb1),
            if (energy.now?.live == true) uiString(R.string.nav_live) else null).joinToString(" · "))
        Text(level?.roundToInt()?.toString() ?: "--", style = BroopType.number,
            color = level?.let(BroopPalette::band) ?: BroopPalette.textPrimary)
        energy.summary?.let { summary ->
            BroopBodyValue(uiString(R.string.broop_body_charged_deb41ca), "+" + summary.charged.roundToInt(), BroopPalette.teal)
            BroopBodyValue(uiString(R.string.broop_body_drained_117ea07), "−" + summary.drained.roundToInt())
        }
        if (level == null) Text(when {
            energy.loading -> uiString(R.string.broop_body_reading_energy_30ff16c)
            energy.failed -> uiString(R.string.broop_body_your_energy_data_could_not_be_read_open_this__720f2c4)
            else -> uiString(R.string.broop_body_energy_is_calibrating_it_needs_about_4_days_o_d3c87f5)
        }, style = BroopType.body, color = BroopPalette.textBody)
    }
}


@Composable
fun BroopEnergyScreen(vm: AppViewModel, onBack: (() -> Unit)? = null) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val sync by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    var offset by remember { mutableStateOf(0L) }
    var history by remember { mutableStateOf<List<BroopEnergyEngine.Summary>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val date = LocalDate.now().minusDays(offset)
    val energy = rememberBroopEnergyDay(vm, date.toString())
    LaunchedEffect(vm.activeStrapId, days, sync, offset) {
        loaded = false; failed = false; history = emptyList()
        try {
            history = withContext(Dispatchers.IO) {
                val values = StressAnalysisStore.storedValues(vm.repo, vm.activeStrapId, BroopEnergyEngine.keys,
                    date.minusDays(30).toString(), LocalDate.now().toString())
                values.toSortedMap().mapNotNull { (day, values) -> BroopEnergyEngine.fromStored(day, values) }
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { failed = true }
        loaded = true
    }
    val summary = energy.summary
    val energyNow = energy.now
    val displayLevel = energyNow?.level ?: summary?.end
    val displayHistory = if (offset == 0L && summary != null) history.filter { it.day != date.toString() } + summary else history
    val points = energy.points
    BroopPage(uiString(R.string.broop_body_energy_437bcb1), onBack) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { offset++ }, enabled = offset < 180) { Text(uiString(R.string.broop_body_previous_50f9428), color = BroopPalette.textBody) }
            Text(if (offset == 0L) uiString(R.string.today_day_today) else date.toString(), style = BroopType.demi, color = BroopPalette.textPrimary)
            TextButton(onClick = { offset-- }, enabled = offset > 0) { Text(uiString(R.string.broop_body_next_bc98198), color = BroopPalette.textBody) }
        }
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_energy_level_e5587f8))
            Text(displayLevel?.roundToInt()?.toString() ?: "--", style = BroopType.largeNumber,
                color = displayLevel?.let(BroopPalette::band) ?: BroopPalette.textPrimary)
            Text(when {
                !loaded || energy.loading -> uiString(R.string.broop_body_reading_energy_30ff16c)
                failed || energy.failed -> uiString(R.string.broop_body_your_energy_data_could_not_be_read_open_this__720f2c4)
                summary == null -> uiString(R.string.broop_body_energy_is_calibrating_it_needs_about_4_days_o_d3c87f5)
                else -> listOf(if ((displayLevel ?: 0.0) >= 67) uiString(R.string.broop_body_high_b1a5954) else if ((displayLevel ?: 0.0) >= 34) uiString(R.string.broop_body_medium_d404968) else uiString(R.string.hrv_status_low),
                    if (energyNow?.live == true) uiString(R.string.nav_live) else uiString(R.string.broop_body_end_of_recorded_data_4835093)).joinToString(" · ")
            }, style = BroopType.body, color = BroopPalette.textBody)
            if (summary?.seeded == true) Text(uiString(R.string.broop_body_this_is_your_first_calibrated_day_energy_star_80bf2ae), style = BroopType.caption, color = BroopPalette.textSecondary)
        }
        if (summary != null) {
            if (points.isNotEmpty()) BroopCard { BroopBodyChart(points.map { it.level }, BroopPalette.teal, uiString(R.string.broop_body_energy_through_the_day_abc5167)) }
            BroopCard {
                BroopBodyValue(uiString(R.string.broop_body_charged_deb41ca), "+${summary.charged.roundToInt()}", BroopPalette.teal)
                BroopBodyValue(uiString(R.string.broop_body_drained_117ea07), "−${summary.drained.roundToInt()}")
                BroopBodyValue(uiString(R.string.today_card_stress), "−${summary.drainStress.roundToInt()}")
                BroopBodyValue(uiString(R.string.today_workouts_activity), "−${summary.drainActivity.roundToInt()}")
                BroopBodyValue(uiString(R.string.broop_body_being_awake_195d8c7), "−${summary.drainBaseline.roundToInt()}")
                summary.wake?.let { BroopBodyValue(uiString(R.string.broop_body_at_wake_09eb35c), it.roundToInt().toString()) }
                BroopBodyValue(uiString(R.string.broop_body_peak_low_64df5ba), "${summary.peak.roundToInt()} / ${summary.low.roundToInt()}")
            }
        }
        if (displayHistory.size >= 2) {
            BroopSection(uiString(R.string.broop_body_last_30_days_6b32985))
            BroopCard { BroopBodyChart(displayHistory.takeLast(30).map { it.end }, BroopPalette.teal, uiString(R.string.broop_body_daily_ending_energy_d336dd7)) }
        }
        BroopSection(uiString(R.string.broop_body_how_energy_works_5f4fc90))
        BroopCard {
            Text(uiString(R.string.broop_body_restful_sleep_and_calm_rest_charge_energy_bei_5157fca),
                style = BroopType.body, color = BroopPalette.textBody)
            Text(uiString(R.string.broop_body_gaps_in_heart_rate_data_hold_the_level_this_i_13ada4c),
                style = BroopType.caption, color = BroopPalette.textSecondary)
        }
    }
}
