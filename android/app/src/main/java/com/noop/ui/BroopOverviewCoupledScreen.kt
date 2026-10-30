package com.noop.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.data.DailyMetric
import com.noop.data.StressAnalysisStore
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** Coupled's own 7.5-hour floor intentionally differs from the age-floored Rest planner. */
internal fun broopCoupledSleepNeed(imported: Double?, days: List<DailyMetric>): Double {
    if (imported != null && imported > 0) return imported
    val banked = days.mapNotNull { it.totalSleepMin }.filter { it > 0 }
    return maxOf(450.0, if (banked.isEmpty()) 450.0 else banked.sum() / banked.size)
}

/** Today-only classic score semantics in Broop's static page and shared score design. */
@Composable
fun BroopOverviewCoupledScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val state = rememberBroopOverview(vm, independentToday = true)
    val snap = state.snapshot
    val baselines by vm.chargeBaselines.collectAsStateWithLifecycle()
    val revision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    var importedNeed by remember { mutableStateOf<Double?>(null) }
    var span by remember { mutableStateOf<Pair<Long, Long>?>(null) }
    var breakdown by remember { mutableStateOf(false) }
    var guide by remember { mutableStateOf(false) }
    val dayKey = snap?.dayKey ?: logicalDayKeyNow()
    val context = LocalContext.current
    LaunchedEffect(dayKey, snap?.days, snap?.habitualMidsleepSec, vm.activeStrapId, revision) {
        importedNeed = null
        span = null
        try {
            val need = vm.repo.resolvedSeries("sleep_need_min", "my-whoop", dayKey, dayKey,
                strapDeviceId = vm.activeStrapId).values.lastOrNull()?.second
            val start = logicalDayNow().atStartOfDay(ZoneId.systemDefault()).toEpochSecond()
            val sessions = StressAnalysisStore.allSleepSessions(vm.repo, vm.activeStrapId, start - 3 * 86_400,
                System.currentTimeMillis() / 1000 + 86_400).filter { it.endTs > start }
            val group = mainSleepGroup(sessions, snap?.habitualMidsleepSec)
            val first = group.minOfOrNull { it.effectiveStartTs }
            val last = group.maxOfOrNull { it.endTs }
            currentCoroutineContext().ensureActive()
            importedNeed = need
            span = if (first != null && last != null && last > first) first to last else null
        } catch (e: kotlinx.coroutines.CancellationException) { throw e
        } catch (_: Exception) { importedNeed = null; span = null }
    }
    val recovery = snap?.charge
    val strain = snap?.day?.strain?.let { UnitFormatter.effortValue(it, EffortScale.WHOOP) }
    val performance = broopRestForRow(snap?.day, snap?.restSeries.orEmpty(),
        NoopPrefs.of(context).getBoolean(com.noop.analytics.RestPerformanceV2.enabledKey, true))
    val target = snap?.effortTarget
    val openSleep = { broopSelectOverviewToday(vm); onNavigate("sleep") }
    BroopPage(stringResource(R.string.broop_overview_today)) {
        Box(Modifier.fillMaxWidth().clickable { breakdown = true }) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                BroopOverviewHero(recovery, color = recovery?.let(BroopPalette::band) ?: BroopPalette.textSecondary,
                    title = stringResource(R.string.l10n_coupled_screen_recovery_b668d988))
                snap?.readiness?.level?.let(::readinessWord)?.let { word ->
                    BroopCaps(stringResource(word), recovery?.let(BroopPalette::band) ?: BroopPalette.textSecondary)
                }
                snap?.carriedChargeDay?.let {
                    Text(carriedCaption(it.day, dayKey).localized(), style = BroopType.caption, color = BroopPalette.textSecondary)
                }
                if (recovery == null) snap?.calibrationNights?.let {
                    Text(stringResource(R.string.broop_overview_calibrating, it), style = BroopType.caption, color = BroopPalette.textSecondary)
                }
                BroopCaps(stringResource(R.string.today_what_shaped_it), BroopPalette.textSecondary)
            }
        }
        BroopCard {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                BroopCaps(stringResource(R.string.broop_overview_coupled_day_strain))
                strain?.let { BroopCaps(stringResource(when {
                    it < 6 -> R.string.broop_overview_coupled_light
                    it < 10 -> R.string.broop_overview_coupled_moderate
                    it < 14 -> R.string.broop_overview_coupled_strenuous
                    else -> R.string.broop_overview_coupled_high
                }), BroopPalette.effort) }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(BroopMetrics.page)) {
                BroopRing(strain, 21.0, BroopPalette.effort, stringResource(R.string.broop_overview_effort), "",
                    target = target?.let { (it.lower * 21 / 100)..(it.upper * 21 / 100) }) { onNavigate("score/effort") }
                Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                    BroopCoupledStat(stringResource(R.string.broop_overview_coupled_optimal), target?.let {
                        stringResource(R.string.broop_overview_coupled_range,
                            String.format(Locale.getDefault(), "%.1f", it.lower * 21 / 100), String.format(Locale.getDefault(), "%.1f", it.upper * 21 / 100))
                    } ?: "—")
                    BroopCoupledStat(stringResource(R.string.broop_overview_calories), snap?.activeKcal?.let { "${it.roundToInt()} kcal" } ?: "—")
                    BroopCoupledStat(stringResource(R.string.nav_workouts), (snap?.day?.exerciseCount ?: 0).toString())
                }
            }
        }
        BroopCard(onClick = openSleep) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(BroopMetrics.page)) {
                BroopRing(performance, color = BroopPalette.rest, label = stringResource(R.string.broop_overview_rest), onClick = openSleep)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
                    BroopCaps(stringResource(R.string.broop_overview_sleep_performance))
                    val asleep = snap?.day?.totalSleepMin
                    val needed = broopCoupledSleepNeed(importedNeed, snap?.days.orEmpty())
                    Text(if (asleep != null && asleep > 0) stringResource(R.string.broop_overview_coupled_slept_needed,
                        hoursMinutes(asleep), hoursMinutes(needed))
                        else stringResource(R.string.l10n_coupled_screen_no_sleep_tracked_last_night_cd0dd79e),
                        style = BroopType.body, color = BroopPalette.textBody)
                    span?.let { (bed, wake) -> Text(stringResource(R.string.broop_overview_clock_span,
                        clockTimeLabel(bed, ClockPrefs.uses24Hour(context)), clockTimeLabel(wake, ClockPrefs.uses24Hour(context))),
                        style = BroopType.caption, color = BroopPalette.textSecondary) }
                }
            }
        }
        Text(stringResource(R.string.broop_overview_coupled_note), style = BroopType.caption, color = BroopPalette.textTertiary)
    }
    if (breakdown) Dialog(onDismissRequest = { breakdown = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopOverviewChargeBreakdown(snap, baselines, performance,
            onClose = { breakdown = false }, onHowCalculated = { breakdown = false; guide = true })
    }
    if (guide) Dialog(onDismissRequest = { guide = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        ScoringGuideScreen(onClose = { guide = false })
    }
}

@Composable
private fun BroopCoupledStat(label: String, value: String) {
    Column {
        BroopCaps(label, BroopPalette.textSecondary)
        Text(value, style = BroopType.demi, color = BroopPalette.textPrimary)
    }
}
