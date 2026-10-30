package com.noop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.DayCycleIntelligenceIntegration
import com.noop.analytics.DayCycleMode
import com.noop.analytics.StrainScorer
import com.noop.analytics.StrainTarget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import kotlin.math.ceil

/** Swift BroopActivityStrainCoach: pre-workout raw TRIMP plus the live window, floored once by stored day. */
@Composable
internal fun BroopActivityStrainCoach(vm: AppViewModel) {
    val workout by vm.activeWorkout.collectAsStateWithLifecycle()
    val active = workout ?: return
    val today by vm.today.collectAsStateWithLifecycle()
    val debt by vm.strainTargetDebtMin.collectAsStateWithLifecycle()
    val alert by vm.healthAlert.collectAsStateWithLifecycle()
    val bpm by vm.bpm.collectAsStateWithLifecycle()
    val sync by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val profile = ProfileStore.from(context)
    val maxHR = profile.hrMax.toDouble()
    val restingHR = vm.workoutRestingHR()
    val method = NoopPrefs.effortMethod(context)
    val goal = StrainTarget.Goal.fromRaw(NoopPrefs.of(context).getString("noop.strainTargetGoal", null))
    val band = StrainTarget.band(StrainTarget.Inputs(today?.recovery, debt, alert != null, goal))
    val scale = UnitPrefs.effortScale(context)
    val mode = NoopPrefs.dayCycleMode(context)
    var before by remember(vm.activeStrapId, active.startMs, maxHR, restingHR, method, profile.sex) { mutableStateOf<Double?>(null) }
    LaunchedEffect(vm.activeStrapId, active.startMs, sync, maxHR, restingHR, method, profile.sex, mode) {
        before = null
        try {
            before = withContext(Dispatchers.Default) {
                val zone = ZoneId.systemDefault()
                val date = logicalDay(Instant.ofEpochMilli(active.startMs).atZone(zone))
                val marker = if (mode == DayCycleMode.SLEEP_ONSET) vm.repo.resolvedSeries(DayCycleIntelligenceIntegration.ONSET_KEY,
                    "my-whoop", date.toString(), date.toString(), strapDeviceId = vm.activeStrapId).values.lastOrNull()?.second?.toLong() else null
                val from = marker ?: date.atStartOfDay(zone).toEpochSecond()
                val to = active.startMs / 1000 - 1
                val hr = if (to > from) vm.repo.hrSamplesUnion(vm.activeStrapId, from, to, 200_000) else emptyList()
                StrainScorer.strain(hr, maxHR, restingHR, method, profile.sex) ?: 0.0
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { before = null }
    }
    val effort = before?.let { prior -> StrainScorer.effectiveEffort(
        StrainScorer.trimpToStrain(StrainScorer.strainToTrimp(prior) + StrainScorer.strainToTrimp(active.liveStrain)), today?.strain) }
    val zone = if (band != null && effort != null) band.zone(effort) else null
    val zoneColor = when (zone) { StrainTarget.Zone.OPTIMAL -> BroopPalette.effort; StrainTarget.Zone.OVERREACHING -> BroopPalette.warning; else -> BroopPalette.textSecondary }
    BroopCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            BroopCaps(stringResource(R.string.broop_coach_title))
            zone?.let { BroopCaps(stringResource(when (it) {
                StrainTarget.Zone.RESTORING -> R.string.broop_coach_restoring
                StrainTarget.Zone.OPTIMAL -> R.string.broop_coach_optimal
                StrainTarget.Zone.OVERREACHING -> R.string.broop_coach_overreaching
            }), zoneColor) }
        }
        BroopBodyValue(stringResource(R.string.broop_coach_day_effort), effort?.let { UnitFormatter.effortDisplay(it, scale) } ?: "--")
        band?.let { BroopBodyValue(stringResource(R.string.broop_coach_target), UnitFormatter.effortDisplay(it.lower, scale) + "–" + UnitFormatter.effortDisplay(it.upper, scale)) }
        Canvas(Modifier.fillMaxWidth().height(BroopMetrics.sectionGap)) {
            val height = size.height / 3; val top = (size.height - height) / 2
            drawRoundRect(BroopPalette.track, Offset(0f, top), Size(size.width, height), CornerRadius(height / 2))
            band?.let { drawRoundRect(BroopPalette.effort.copy(alpha = 0.45f), Offset(size.width * (it.lower / 100).toFloat(), top),
                Size(size.width * ((it.upper - it.lower) / 100).toFloat(), height), CornerRadius(height / 2)) }
            effort?.let { val width = BroopMetrics.ringStroke.toPx() / 2; drawRoundRect(BroopPalette.textPrimary,
                Offset((size.width * (it / 100).toFloat() - width / 2).coerceIn(0f, maxOf(0f, size.width - width)), 0f), Size(width, size.height), CornerRadius(width / 2)) }
        }
        val message = when {
            band == null -> stringResource(R.string.broop_coach_needs_charge)
            effort == null -> stringResource(R.string.broop_coach_loading)
            zone == StrainTarget.Zone.OPTIMAL -> stringResource(R.string.broop_coach_reached)
            zone == StrainTarget.Zone.OVERREACHING -> stringResource(R.string.broop_coach_above)
            method != StrainScorer.Method.EDWARDS -> stringResource(R.string.broop_coach_below)
            else -> {
                val rate = bpm?.let { StrainTarget.edwardsTrimpPerMinute(it.toDouble(), restingHR, maxHR) } ?: 0.0
                val minutes = StrainTarget.minutesToReach(band.lower, effort, rate)
                if (rate > 0 && minutes != null) stringResource(R.string.broop_coach_minutes, ceil(minutes).toInt())
                else StrainTarget.minutesToReach(band.lower, effort, 2.0)?.let { stringResource(R.string.broop_coach_zone_two_minutes, ceil(it).toInt()) }
                    ?: stringResource(R.string.broop_coach_below)
            }
        }
        Text(message, style = BroopType.body, color = BroopPalette.textBody)
    }
}
