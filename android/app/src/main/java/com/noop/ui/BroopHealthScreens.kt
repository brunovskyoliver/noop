package com.noop.ui

import com.noop.R

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Timeline
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.HRVStatus
import com.noop.analytics.VitalBands
import com.noop.analytics.VitalityEngine
import com.noop.analytics.VitalityWindow
import com.noop.data.DailyMetric
import com.noop.data.healthspanSnapshot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Health navigation follows the iOS Broop tab and reads the native Android resolvers. */
@Composable
fun BroopHealthHubScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val today by vm.today.collectAsStateWithLifecycle()
    val candidates by vm.spo2CandidateByDay.collectAsStateWithLifecycle()
    val overCount by vm.hrvOverCountByDay.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val vitals = remember(today, days, candidates, overCount) {
        vitalsFor(today, days, spo2CandidateByDay = candidates,
            spo2ToggleOn = NoopPrefs.spo2CandidateDisplay(context), hrvOverCountByDay = overCount)
            .filter { it.key != "spo2raw" }
    }
    val healthspan = rememberBroopHealthspan(vm, days)
    val showEnergy = NoopPrefs.of(context).getBoolean("noop.showEnergy", true)
    BroopPage(uiString(R.string.explore_category_health)) {
        BroopHealthLiveCard(vm) { onNavigate("live") }
        BroopCard(onClick = { onNavigate("healthspan") }) {
            BroopCaps(uiString(R.string.broop_body_healthspan_ec666c6))
            Text(healthspan.bodyAge?.let(::broopOne) ?: "--", style = BroopType.largeNumber, color = BroopPalette.textPrimary)
            Text(healthspan.bodyAge?.let { uiString(R.string.broop_body_broop_age_1_s_931a771, (broopAgeDifference(it - healthspan.age)).toString()) }
                ?: uiString(R.string.broop_body_keep_wearing_your_strap_your_weekly_age_estim_a0a116d),
                style = BroopType.body, color = BroopPalette.textBody)
            healthspan.pace?.let { BroopBodyValue(uiString(R.string.broop_body_pace_of_aging_adbe8ba), "${broopOne(it)}x") }
        }
        BroopCard(onClick = { onNavigate("health") }) {
            BroopCaps(uiString(R.string.broop_body_health_monitor_96eb6a7))
            val available = vitals.filter { it.value != null }
            val inRange = available.count { it.banding.band == VitalBands.Band.IN_RANGE }
            Text(if (available.isEmpty()) uiString(R.string.broop_body_wear_your_strap_overnight_to_see_your_vitals_4e719cf)
                else uiString(R.string.broop_body_1_s_2_s_metrics_within_range_1d40e15, (inRange).toString(), (available.size).toString()), style = BroopType.demi,
                color = BroopPalette.textPrimary)
            vitals.forEach { vital ->
                BroopBodyValue(vital.label, vital.formattedValue ?: "--",
                    if (vital.banding.band == VitalBands.Band.OUT_OF_RANGE) BroopPalette.warning else BroopPalette.textBody)
            }
        }
        BroopHealthStressTile(vm) { onNavigate("stress") }
        BroopRow(uiString(R.string.explore_category_mind), uiString(R.string.broop_body_resilience_cumulative_stress_and_monthly_chec_5b360bb), Icons.Filled.Psychology) { onNavigate("mind") }
        if (showEnergy) BroopEnergyCard(vm) { onNavigate("energy") }
        BroopSection(uiString(R.string.broop_body_heart_fitness_d60602c))
        BroopCard(onClick = { onNavigate("vital_detail/hrv") }) {
            BroopCaps(uiString(R.string.broop_body_hrv_status_8361e80))
            val hrv = days.lastOrNull { it.avgHrv != null }?.avgHrv
            Text(hrv?.let { uiString(R.string.l10n_live_screen_rmssd_roundtoint_ms_9e6c0887, it.roundToInt()) } ?: "--", style = BroopType.number, color = BroopPalette.textPrimary)
            Text(uiString(R.string.broop_body_your_overnight_heart_rate_variability_compare_f15b140),
                style = BroopType.body, color = BroopPalette.textBody)
            BroopBodyChart(days.mapNotNull { it.avgHrv }, BroopPalette.teal, uiString(R.string.broop_body_overnight_hrv_history_2c1939b))
        }
        BroopRow(uiString(R.string.broop_body_fitness_age_vo_max_c9ec47f), uiString(R.string.broop_body_fitness_estimates_and_the_inputs_behind_them_fa5c86b), Icons.Filled.FitnessCenter) { onNavigate("healthspan") }
        BroopSection(uiString(R.string.more_group_body))
        BroopRow(uiString(R.string.broop_body_lab_book_3f372f6), uiString(R.string.broop_body_bloods_blood_pressure_and_body_numbers_628ff74), Icons.Filled.Science) { onNavigate("lab_book") }
        BroopRow(uiString(R.string.today_card_hydration), uiString(R.string.broop_body_log_water_and_review_your_daily_total_79ba81a), Icons.Filled.WaterDrop) { onNavigate("hydration") }
        BroopRow(uiString(R.string.l10n_rhythm_screen_rhythm_c715bb28), uiString(R.string.broop_body_beat_to_beat_regularity_experimental_ec622dc), Icons.Filled.MonitorHeart) { onNavigate("rhythm") }
        BroopRow(uiString(R.string.broop_body_jet_lag_planner_eb451ff), uiString(R.string.broop_body_light_and_sleep_timing_before_travel_9caed8f), Icons.Filled.Timeline) { onNavigate("jet_lag") }
        BroopSection(uiString(R.string.nav_trends))
        BroopRow(uiString(R.string.broop_body_my_dashboard_a95750e), uiString(R.string.broop_body_every_metric_over_weeks_and_months_e424ca9), Icons.AutoMirrored.Filled.TrendingUp) { onNavigate("trends") }
        BroopRow(uiString(R.string.broop_body_metric_explorer_a8d483a), uiString(R.string.broop_body_inspect_your_locally_stored_signals_59c0a01), Icons.Filled.MonitorHeart) { onNavigate("explore") }
        BroopRow(uiString(R.string.l10n_compare_screen_compare_8d105cf4), uiString(R.string.broop_body_find_relationships_between_your_metrics_720561b), Icons.AutoMirrored.Filled.CompareArrows) { onNavigate("compare") }
        BroopRow(uiString(R.string.broop_body_your_data_fused_d90d77f), uiString(R.string.broop_body_sources_and_records_behind_your_daily_scores_807d45f), Icons.Filled.Science) { onNavigate("fused_record") }
        Text(uiString(R.string.broop_body_health_and_stress_estimates_are_wellness_tool_d68aa58),
            style = BroopType.caption, color = BroopPalette.textSecondary)
    }
}

@Composable
private fun BroopHealthStressTile(vm: AppViewModel, onClick: () -> Unit) {
    val load by rememberBroopStressDay(vm, LocalDate.now().toString())
    val now = rememberBroopStressNow(vm, load.result)
    BroopCard(onClick = onClick) {
        BroopCaps(if (now?.live == true) uiString(R.string.broop_body_stress_monitor_live_0fce8a0) else uiString(R.string.broop_body_stress_monitor_98ead1a))
        Text(now?.level?.let(::broopOne) ?: "--", style = BroopType.number, color = BroopPalette.textPrimary)
        Text(when {
            now?.active == true -> uiString(R.string.broop_body_activity_detected_movement_is_excluded_from_s_542b41e)
            now?.level != null -> uiString(R.string.broop_body_1_s_0_3_scale_0e2a168, (if (now.level < 1) uiString(R.string.hrv_status_low) else if (now.level < 2) uiString(R.string.broop_body_medium_d404968) else uiString(R.string.broop_body_high_b1a5954)).toString())
            load.loading -> uiString(R.string.broop_body_reading_stress_e29d07d)
            load.failed -> uiString(R.string.broop_body_stress_data_could_not_be_read_d1f586e)
            else -> uiString(R.string.broop_body_wear_your_strap_to_build_your_personal_stress_a6b9a51)
        }, style = BroopType.body, color = BroopPalette.textBody)
    }
}

@Composable
private fun BroopHealthLiveCard(vm: AppViewModel, onClick: () -> Unit) {
    val live by vm.live.collectAsStateWithLifecycle()
    val bpm by vm.bpm.collectAsStateWithLifecycle()
    DisposableEffect(vm) {
        vm.requestRealtimeHr()
        onDispose { vm.releaseRealtimeHr() }
    }
    val hr = displayHr(bpm, live)
    BroopCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            Icon(Icons.Filled.FavoriteBorder, contentDescription = null, tint = BroopPalette.effort)
            BroopCaps(if (live.connected || live.streamingLiveHR) uiString(R.string.broop_body_live_heart_rate_1359395) else uiString(R.string.l10n_noop_glance_widget_heart_rate_410aa15c))
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            Text(hr?.toString() ?: "--", style = BroopType.largeNumber, color = BroopPalette.textPrimary)
            Text("BPM", style = BroopType.caps, color = BroopPalette.textSecondary)
        }
        Text(if (hr != null) uiString(R.string.broop_body_streaming_from_your_connected_device_18d3430) else uiString(R.string.broop_body_connect_your_device_to_see_a_live_reading_c244fa6),
            style = BroopType.body, color = BroopPalette.textBody)
    }
}

internal data class BroopHealthspanData(
    val age: Double = 0.0,
    val bodyAge: Double? = null,
    val pace: Double? = null,
    val fitnessAge: Double? = null,
    val vo2: Double? = null,
    val updated: String? = null,
    val trend: List<Double> = emptyList(),
    val contributions: List<VitalityEngine.Contribution> = emptyList(),
    val impacts: List<VitalityEngine.Impact> = emptyList(),
    val recoveries: Int = 0,
    val stale: Boolean = false,
    val loaded: Boolean = false,
    val failure: Boolean = false,
)

@Composable
internal fun rememberBroopHealthspan(vm: AppViewModel, days: List<DailyMetric>): BroopHealthspanData {
    val context = LocalContext.current
    val profile = remember(context) { ProfileStore.from(context.applicationContext) }
    var data by remember { mutableStateOf(BroopHealthspanData(age = profile.age.toDouble())) }
    LaunchedEffect(vm.activeStrapId, days, profile.age, profile.sex) {
        data = try {
            withContext(Dispatchers.IO) {
                val snapshot = vm.repo.healthspanSnapshot(vm.activeStrapId, profile.age, profile.sex)
                val fitness = vm.repo.latestMetricComputedUnion(vm.activeStrapId, "fitness_age")
                val vo2 = vm.repo.resolvedSeries("vo2max_est", "my-whoop", "0000-01-01", "9999-12-31", strapDeviceId = vm.activeStrapId)
                BroopHealthspanData(age = snapshot.chronoAge, bodyAge = snapshot.bodyAge, pace = snapshot.pace,
                    fitnessAge = fitness?.value, vo2 = vo2.points.lastOrNull()?.value, updated = snapshot.shownDay,
                    trend = snapshot.trend.map { it.second }, contributions = snapshot.result?.current?.contributions.orEmpty(),
                    impacts = snapshot.result?.current?.impacts.orEmpty(), recoveries = snapshot.recoveriesLast31,
                    stale = snapshot.isStale, loaded = true)
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { data.copy(loaded = true, failure = true) }
    }
    return data
}

@Composable
fun BroopHealthspanScreen(vm: AppViewModel, onNavigate: (String) -> Unit = {}, onBack: (() -> Unit)? = null) {
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val data = rememberBroopHealthspan(vm, days)
    BroopPage(uiString(R.string.broop_body_healthspan_ec666c6), onBack) {
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_broop_age_eb53618))
            Text(data.bodyAge?.let(::broopOne) ?: "--", style = BroopType.largeNumber, color = BroopPalette.textPrimary)
            Text(data.bodyAge?.let { broopAgeDifference(it - data.age) }
                ?: if (!data.loaded) uiString(R.string.broop_body_reading_your_healthspan_ace8846) else uiString(R.string.broop_body_log_21_recoveries_in_a_month_to_unlock_your_b_107ccfe, (data.recoveries).toString()),
                style = BroopType.body, color = BroopPalette.textBody)
            BroopBodyValue(uiString(R.string.broop_body_calendar_age_6438efc), uiString(R.string.broop_body_1_s_years_8d37c91, (data.age.roundToInt()).toString()))
            data.updated?.let { BroopBodyValue(uiString(R.string.broop_body_last_update_cf1b916), it) }
            if (data.stale) Text(uiString(R.string.broop_body_not_updated_this_week_broop_age_needs_21_reco_c222564, (data.recoveries).toString()), style = BroopType.body, color = BroopPalette.textBody)
            if (data.failure) Text(uiString(R.string.broop_body_healthspan_could_not_be_read_open_this_screen_2a60513), style = BroopType.caption, color = BroopPalette.warning)
        }
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_pace_of_aging_adbe8ba))
            Text(data.pace?.let { broopOne(it) + "x" } ?: "--", style = BroopType.number, color = BroopPalette.textPrimary)
            Text(uiString(R.string.broop_body_projects_your_recent_habits_six_months_ahead__b8fceba), style = BroopType.body, color = BroopPalette.textBody)
        }
        if (data.impacts.isNotEmpty()) {
            BroopSection(uiString(R.string.broop_body_what_shapes_your_age_f95d335))
            BroopCard {
                data.impacts.forEach { impact ->
                    BroopBodyValue(broopHealthFactorLabel(impact.factor), if (impact.isMissing) uiString(R.string.today_no_data) else uiString(R.string.broop_body_1_s_years_8d37c91, (String.format(Locale.US, "%+.1f", impact.years)).toString()),
                        if (impact.isMissing) BroopPalette.textSecondary else if (impact.years < 0) BroopPalette.teal else BroopPalette.warning)
                }
            }
        }
        if (data.trend.size >= 2) {
            BroopSection(uiString(R.string.broop_body_broop_age_trend_e024288))
            BroopCard { BroopBodyChart(data.trend, BroopPalette.teal, uiString(R.string.broop_body_weekly_broop_age_trend_b6c8bcd)) }
        }
        BroopSection(uiString(R.string.broop_body_fitness_aae59f9))
        BroopCard {
            BroopBodyValue(uiString(R.string.broop_body_fitness_age_3832db1), data.fitnessAge?.let { uiString(R.string.broop_body_1_s_2_s_years_a7d4844, (fitnessAgeBoundSymbol(it)).toString(), (it.roundToInt()).toString()) } ?: "--")
            BroopBodyValue(uiString(R.string.broop_body_vo_max_42c1d95), data.vo2?.let { "${broopOne(it)} mL/kg/min" } ?: "--")
            Text(uiString(R.string.broop_body_fitness_age_uses_resting_heart_rate_and_recen_cb13690),
                style = BroopType.body, color = BroopPalette.textBody)
            BroopBodyButton(uiString(R.string.broop_body_review_profile_dfa922a)) { onNavigate("settings") }
        }
        Text(uiString(R.string.broop_body_an_independent_wellness_estimate_from_your_ha_daba501),
            style = BroopType.caption, color = BroopPalette.textSecondary)
    }
}

@Composable
internal fun BroopBodyValue(label: String, value: String, color: Color = BroopPalette.textPrimary) {
    Row(modifier = Modifier.fillMaxWidth().heightIn(min = BroopMetrics.touch),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Text(label, modifier = Modifier.weight(1f), style = BroopType.body, color = BroopPalette.textBody)
        Text(value, style = BroopType.demi, color = color)
    }
}

@Composable
internal fun BroopBodyButton(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled,
        modifier = Modifier.fillMaxWidth().heightIn(min = BroopMetrics.touch),
        colors = ButtonDefaults.buttonColors(containerColor = BroopPalette.row, contentColor = BroopPalette.textPrimary)) {
        Text(title, style = BroopType.demi)
    }
}

@Composable
internal fun BroopBodyChart(values: List<Double>, color: Color, label: String) {
    val finite = values.filter { it.isFinite() }
    if (finite.size < 2) return
    val low = finite.min(); val high = finite.max(); val span = (high - low).coerceAtLeast(1.0)
    Canvas(Modifier.fillMaxWidth().height(BroopMetrics.touch * 2).semantics {
        contentDescription = uiString(R.string.broop_body_1_s_2_s_readings_latest_3_s_range_4_s_to_5_s_132e64e, (label).toString(), (finite.size).toString(), (broopOne(finite.last())).toString(), (broopOne(low)).toString(), (broopOne(high)).toString())
    }) {
        val inset = size.height * 0.08f
        val path = Path()
        finite.forEachIndexed { index, value ->
            val x = size.width * index / (finite.size - 1)
            val y = size.height - inset - ((value - low) / span).toFloat() * (size.height - inset * 2)
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color, style = Stroke(width = 2.5f, cap = StrokeCap.Round))
    }
}

internal fun broopOne(value: Double): String = String.format(Locale.US, "%.1f", value)

internal fun broopAgeDifference(delta: Double): String = when {
    abs(delta) < 0.05 -> uiString(R.string.broop_body_about_your_calendar_age_39b2394)
    delta < 0 -> uiString(R.string.broop_body_1_s_years_younger_8c8f844, (broopOne(abs(delta))).toString())
    else -> uiString(R.string.broop_body_1_s_years_older_a3ab484, (broopOne(delta)).toString())
}

private fun broopHealthFactorLabel(factor: VitalityEngine.Factor): String = uiString(when (factor) {
    VitalityEngine.Factor.SLEEP_HOURS -> R.string.broop_body_factor_sleep
    VitalityEngine.Factor.SLEEP_CONSISTENCY -> R.string.broop_body_factor_consistency
    VitalityEngine.Factor.ZONE13 -> R.string.broop_body_factor_zone13
    VitalityEngine.Factor.ZONE45 -> R.string.broop_body_factor_zone45
    VitalityEngine.Factor.STRENGTH -> R.string.broop_body_factor_strength
    VitalityEngine.Factor.STEPS -> R.string.broop_body_factor_steps
    VitalityEngine.Factor.VO2MAX -> R.string.broop_body_factor_vo2
    VitalityEngine.Factor.RHR -> R.string.broop_body_factor_rhr
    VitalityEngine.Factor.LEAN_MASS -> R.string.broop_body_factor_lean
})
