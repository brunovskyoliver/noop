package com.noop.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.StreakCalculator
import com.noop.data.SleepSession
import com.noop.data.WorkoutRow
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

@Composable
fun BroopHomeScreen(vm: AppViewModel, onNavigate: (String) -> Unit, onQuickActions: () -> Unit) {
    val state = rememberBroopOverview(vm)
    val snap = state.snapshot
    val live by vm.live.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coachEnabled = NoopPrefs.of(context).getBoolean("noop.coachEnabled", true)
    var outlook by remember { mutableStateOf(false) }
    var startWorkout by remember { mutableStateOf(false) }
    var addWorkout by remember { mutableStateOf(false) }
    val scroll = rememberScrollState()
    val collapsed by remember { derivedStateOf { scroll.value > 300 } }
    val evening = state.dayOffset > 0 || LocalTime.now().hour >= 17
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val maxOffset = broopOverviewMaxOffset(days, logicalDayNow())
    val streak = remember(days) { StreakCalculator.streaks(days.map { it.day }, days.map { it.recovery != null }, LocalDate.now().toString()).current }

    Box(Modifier.fillMaxSize().background(BroopPalette.background)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(scroll).broopDaySwipe(state, maxOffset)
                .padding(horizontal = BroopMetrics.page)
                .padding(bottom = BroopMetrics.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
        ) {
            Box(Modifier.fillMaxWidth().padding(top = BroopMetrics.compactGap)) {
                BroopOverviewDateNav(state, maxOffset, Modifier.align(Alignment.Center))
                Row(Modifier.align(Alignment.CenterStart), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { onNavigate("settings") }) {
                        Icon(Icons.Filled.Person, stringResource(R.string.broop_overview_profile), tint = BroopPalette.textPrimary,
                            modifier = Modifier.size(BroopMetrics.badge).clip(CircleShape).background(BroopPalette.pillInner).padding(BroopMetrics.compactGap))
                    }
                    if (streak > 0) Text(streak.toString(), style = BroopType.caption, color = BroopPalette.warning,
                        modifier = Modifier.semantics { contentDescription = context.getString(R.string.broop_overview_streak, streak) })
                }
                Row(Modifier.align(Alignment.CenterEnd).clip(RoundedCornerShape(BroopMetrics.rowRadius))
                    .clickable { onNavigate("devices") }.padding(BroopMetrics.gap), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Bluetooth, stringResource(R.string.broop_overview_devices),
                        tint = if (live.connected) BroopPalette.connected else BroopPalette.textSecondary,
                        modifier = Modifier.size(BroopMetrics.smallIcon))
                    live.batteryPct?.let { Text(stringResource(R.string.broop_overview_percent, it.roundToInt()), style = BroopType.caption, color = BroopPalette.textPrimary) }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = BroopMetrics.page), horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically) {
                BroopMark()
                Text(stringResource(R.string.broop_onboarding_brand), style = BroopType.wordmark, color = BroopPalette.textPrimary)
            }
            BroopOverviewRings(snap, onNavigate)
            Row(Modifier.fillMaxWidth().padding(top = BroopMetrics.page), horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                val vitals = snap?.vitals.orEmpty().filter { it.banding.band != com.noop.analytics.VitalBands.Band.NO_DATA }
                val outside = vitals.count { it.banding.band == com.noop.analytics.VitalBands.Band.OUT_OF_RANGE }
                BroopOverviewMonitor(stringResource(R.string.broop_overview_health_monitor),
                    if (vitals.isEmpty()) stringResource(R.string.broop_overview_no_data)
                    else stringResource(if (outside == 0) R.string.broop_overview_within_range else R.string.broop_overview_outside_range),
                    stringResource(R.string.broop_overview_metrics_count, vitals.size - outside, vitals.size),
                    if (outside > 0) BroopPalette.warning else BroopPalette.teal, Icons.Filled.MonitorHeart,
                    Modifier.weight(1f)) { onNavigate("health") }
                BroopOverviewStressMonitor(vm, logicalDayNow().minusDays(state.dayOffset.toLong()).toString(),
                    Modifier.weight(1f)) { onNavigate("stress") }
            }
            if (state.dayOffset == 0 && NoopPrefs.of(context).getBoolean("noop.showEnergy", true)) {
                BroopEnergyCard(vm, logicalDayNow().toString()) { onNavigate("energy") }
            }
            Row(Modifier.fillMaxWidth().padding(top = BroopMetrics.sectionGap), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.broop_overview_my_day), style = BroopType.section, color = BroopPalette.textPrimary, modifier = Modifier.weight(1f))
                IconButton(onClick = onQuickActions, modifier = Modifier.clip(RoundedCornerShape(BroopMetrics.rowRadius)).background(BroopPalette.textPrimary)) {
                    Icon(Icons.Filled.Add, stringResource(R.string.broop_overview_actions), tint = BroopPalette.bgBottom)
                }
            }
            BroopRow(stringResource(if (evening) R.string.broop_overview_review else R.string.broop_overview_outlook),
                icon = if (evening) Icons.Filled.Bedtime else Icons.Filled.Bolt) { outlook = true }
            if (coachEnabled && state.dayOffset == 0) BroopRow(stringResource(R.string.broop_overview_coach),
                snap?.readiness?.level?.let { readinessWord(it) }?.let { stringResource(it) }, Icons.Filled.Info) { onNavigate("coach") }
            BroopOverviewActivities(snap, state.dayOffset == 0, onNavigate,
                onAdd = { addWorkout = true }, onStart = { startWorkout = true })
            if (state.dayOffset == 0) BroopOverviewTonight(vm) { onNavigate("smart_alarm") }
            BroopOverviewJournal(snap, logicalDayNow().minusDays(state.dayOffset.toLong())) {
                vm.requestJournalDay(ChronoUnit.DAYS.between(logicalDayNow().minusDays(state.dayOffset.toLong()), LocalDate.now()))
                onNavigate("insights")
            }
            if (snap?.readings?.isNotEmpty() == true) {
                BroopSection(stringResource(R.string.broop_overview_dashboard))
                snap.readings.filter { it.key != "spo2" }.forEach { BroopOverviewReadingRow(it, onNavigate) }
            }
            BroopRow(stringResource(R.string.broop_overview_day_hr), icon = Icons.Filled.MonitorHeart) { onNavigate("full_day_chart") }
            BroopRow(stringResource(R.string.broop_overview_refresh), icon = Icons.Filled.Refresh) { state.reload(); vm.syncNow() }
        }
        if (collapsed) Row(Modifier.fillMaxWidth().background(BroopPalette.bgTop).padding(BroopMetrics.gap),
            horizontalArrangement = Arrangement.SpaceEvenly) {
            listOf("rest", "charge", "effort").forEach { score ->
                TextButton(onClick = { onNavigate("score/$score") }) {
                    BroopCaps(stringResource(broopScoreTitle(score)), color = broopScoreColor(score, snap))
                }
            }
        }
    }
    if (outlook) BroopOverviewDialog({ outlook = false }) {
        BroopPage(stringResource(if (evening) R.string.broop_overview_review else R.string.broop_overview_outlook), { outlook = false }) {
            BroopOverviewRings(snap) { outlook = false; onNavigate(it) }
            BroopOverviewReadinessDetails(snap)
            snap?.asleepMinutes?.let { asleep -> BroopCard {
                BroopOverviewContributorText(stringResource(R.string.broop_overview_hours_sleep), broopDurationText(asleep), Icons.Filled.Bedtime)
                BroopOverviewContributorText(stringResource(R.string.broop_overview_hours_needed), broopDurationText(snap.needMinutes), Icons.Filled.Schedule)
            } }
            if (state.dayOffset == 0) BroopOverviewTonight(vm) { outlook = false; onNavigate("smart_alarm") }
            if (coachEnabled) BroopRow(stringResource(R.string.broop_overview_ask_coach)) {
                CoachHandoff.pendingPrompt = context.getString(R.string.broop_overview_coach_question,
                    context.getString(if (evening) R.string.broop_overview_review else R.string.broop_overview_outlook), snap?.dayKey ?: logicalDayKeyNow())
                outlook = false; onNavigate("coach")
            }
        }
    }
    if (startWorkout) StartWorkoutSheet(vm) { startWorkout = false }
    if (addWorkout) ManualWorkoutDialog(editing = null, onDismiss = { addWorkout = false }, onSave = { row, replacing ->
        vm.saveManualWorkout(row, replacing); addWorkout = false; state.reload()
    })
}

@Composable
fun BroopSleepScreen(vm: AppViewModel, onNavigate: (String) -> Unit, onBack: (() -> Unit)? = null) {
    val context = LocalContext.current
    val state = rememberBroopOverview(vm)
    val snap = state.snapshot
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val live by vm.live.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val maxOffset = broopOverviewMaxOffset(days, logicalDayNow())
    var nativeDetails by remember { mutableStateOf(false) }
    var guide by remember { mutableStateOf(false) }
    var deleted by remember { mutableStateOf<List<SleepSession>>(emptyList()) }
    var sleepEdit by remember { mutableStateOf<BroopSleepEdit?>(null) }
    var customize by remember { mutableStateOf(false) }
    var layoutRevision by remember { mutableStateOf(0) }
    var metricDetail by remember { mutableStateOf<String?>(null) }
    BroopOverviewPage(state, maxOffset, onBack, { guide = true }) {
        if (state.dayOffset == 0) {
            val now = Instant.now().atZone(ZoneId.systemDefault())
            val freshness = resolveSleepFreshness(
                hasCurrentNight = snap?.night != null && snap.restDayKey == now.toLocalDate().toString(),
                morningReady = now.hour >= 6, syncing = live.backfilling, calculating = live.analyzingHistory,
                syncedSinceDayStart = (live.lastSyncAt ?: 0L) >= now.toLocalDate().atStartOfDay(now.zone).toEpochSecond(),
                syncFailed = live.lastSyncError != null)
            if (freshness != null) {
                val (title, detail) = when (freshness) {
                    SleepFreshnessStatus.SYNCING -> R.string.broop_overview_syncing to R.string.sleep_status_waiting_body
                    SleepFreshnessStatus.CALCULATING -> R.string.sleep_status_calculating_title to R.string.sleep_status_calculating_body
                    SleepFreshnessStatus.SYNC_FAILED -> R.string.sleep_status_sync_failed_title to R.string.sleep_status_sync_failed_body
                    SleepFreshnessStatus.AWAITING_SYNC -> R.string.sleep_status_waiting_title to R.string.sleep_status_waiting_body
                    SleepFreshnessStatus.NOT_DETECTED -> R.string.sleep_status_not_detected_title to R.string.sleep_status_not_detected_body
                }
                DataPendingNote(stringResource(title), stringResource(detail))
            }
        }
        BroopOverviewHero(snap?.rest, color = BroopPalette.rest, title = stringResource(R.string.broop_overview_sleep_performance))
        if (snap != null && snap.restDayKey != snap.dayKey && snap.rest != null) BroopCaps(stringResource(R.string.broop_overview_carried, lastChargeDateLabel(snap.restDayKey)), BroopPalette.textSecondary)
        BroopCard {
            BroopOverviewContributor(stringResource(R.string.broop_overview_hours_needed), snap?.hoursVsNeeded?.coerceAtMost(100.0), "%", Icons.Filled.Schedule) { onNavigate("vital_detail/hours_vs_needed_pct") }
            BroopOverviewContributor(stringResource(R.string.broop_overview_consistency), snap?.consistency, "%", Icons.Filled.Bedtime,
                action = snap?.consistency?.let { { onNavigate("vital_detail/sleep_consistency") } })
            BroopOverviewContributor(stringResource(R.string.broop_overview_efficiency), snap?.efficiency, "%", Icons.Filled.Bedtime) { onNavigate("vital_detail/sleep_efficiency") }
            if (NoopPrefs.of(LocalContext.current).getBoolean(com.noop.analytics.RestPerformanceV2.enabledKey, true)) {
                BroopOverviewContributor(stringResource(R.string.broop_overview_sleep_stress), snap?.sleepStressPct, "%", Icons.Filled.Bolt) { onNavigate("vital_detail/sleep_stress_pct") }
            } else BroopOverviewContributor(stringResource(R.string.broop_overview_restorative), snap?.restorativePct, "%", Icons.Filled.Bolt) { onNavigate("vital_detail/restorative_pct") }
        }
        BroopCard {
            Text(stringResource(when {
                snap?.rest == null -> R.string.broop_overview_no_performance
                snap.rest >= 85 -> R.string.broop_overview_sleep_optimal
                snap.rest >= 70 -> R.string.broop_overview_sleep_sufficient
                else -> R.string.broop_overview_sleep_poor
            }), style = BroopType.body, color = BroopPalette.textBody)
            BroopOverviewCoachLink(snap, "rest", onNavigate)
        }
        BroopSection(stringResource(if (state.dayOffset == 0) R.string.broop_overview_night else R.string.broop_overview_night_selected))
        if (deleted.isNotEmpty()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.broop_overview_deleted), color = BroopPalette.textBody, style = BroopType.body, modifier = Modifier.weight(1f))
                TextButton(onClick = { scope.launch {
                    if (vm.undoDeleteSleepSessions(deleted)) { deleted = emptyList(); state.reload() }
                    else android.widget.Toast.makeText(context, context.getString(R.string.broop_overview_sleep_save_failed), android.widget.Toast.LENGTH_SHORT).show()
                } }) { Text(stringResource(R.string.broop_overview_undo), color = BroopPalette.textPrimary) }
            }
        }
        if (snap?.night != null || snap?.asleepMinutes != null) {
            BroopOverviewNight(vm, snap)
            val night = snap.night
            if (night != null) NightNavHeader(offset = state.dayOffset, nightLabel = broopDayLabel(state.dayOffset),
                lastIndex = maxOffset, clock = night.clockLabel, onNavigate = { state.dayOffset = it },
                session = night.session, heroGroup = night.heroGroup,
                onUpdateTimes = { session, start, end -> scope.launch {
                    if (vm.updateSleepGroupTimes(night.heroGroup.ifEmpty { listOf(session) }, start, end)) state.reload()
                    else android.widget.Toast.makeText(context, context.getString(R.string.broop_overview_sleep_save_failed), android.widget.Toast.LENGTH_SHORT).show()
                } },
                onDeleteSession = { session -> scope.launch {
                    val group = broopSleepDeleteGroup(night, session)
                    if (vm.deleteSleepSessions(group)) { deleted = group; state.reload() }
                    else android.widget.Toast.makeText(context, context.getString(R.string.broop_overview_sleep_save_failed), android.widget.Toast.LENGTH_SHORT).show()
                } },
                onAddNap = { start, end -> scope.launch {
                    if (vm.addManualNap(start, end)) state.reload()
                    else android.widget.Toast.makeText(context, context.getString(R.string.broop_overview_sleep_save_failed), android.widget.Toast.LENGTH_SHORT).show()
                } })
            if (night?.napBlocks?.isNotEmpty() == true) {
                BroopSection(stringResource(R.string.broop_overview_naps))
                night.napBlocks.forEach { nap ->
                    BroopOverviewActivityRow(stringResource(R.string.broop_overview_sleep), broopDurationText((nap.endTs - nap.effectiveStartTs) / 60.0),
                        BroopPalette.rest, nap.effectiveStartTs, nap.endTs, Icons.Filled.Bedtime) {
                        sleepEdit = BroopSleepEdit(nap.effectiveStartTs, nap.endTs, nap, nap = true)
                    }
                }
            }
        } else BroopEmpty(stringResource(R.string.broop_overview_sleep_empty), stringResource(R.string.broop_overview_sleep_empty_detail))
        if (snap?.night == null) BroopRow(stringResource(R.string.broop_overview_add_sleep), icon = Icons.Filled.Add) {
            val wake = minOf(System.currentTimeMillis() / 1000,
                logicalDayNow().minusDays(state.dayOffset.toLong()).atStartOfDay(ZoneId.systemDefault()).plusHours(8).toEpochSecond())
            sleepEdit = BroopSleepEdit(wake - 8 * 3600, wake)
        }
        BroopOverviewSleepSections(vm, snap, state.dayOffset == 0, layoutRevision, onNavigate) { metricDetail = it }
        BroopRow(stringResource(R.string.broop_overview_sleep_details), stringResource(R.string.broop_overview_sleep_details_caption), Icons.Filled.Edit) { nativeDetails = true }
        BroopOverviewSleepHeartRateCards(vm, snap?.restDayKey ?: logicalDayKeyNow())
        BroopOverviewTrendCard(vm, snap, "rest", onNavigate)
        BroopRow(stringResource(R.string.broop_overview_jet_lag), icon = Icons.Filled.Schedule) { onNavigate("jet_lag") }
        BroopRow(stringResource(R.string.sleep_customize_title), stringResource(R.string.sleep_customize_description), Icons.Filled.Edit) { customize = true }
    }
    if (nativeDetails) BroopOverviewDialog({ nativeDetails = false; layoutRevision++; state.reload() }) {
        Column(Modifier.fillMaxSize().background(BroopPalette.bgBottom)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                IconButton(onClick = { nativeDetails = false; layoutRevision++; state.reload() }) { Icon(Icons.Filled.Close, stringResource(R.string.broop_overview_close), tint = BroopPalette.textPrimary) }
            }
            Box(Modifier.weight(1f)) { SleepScreen(vm, onOpenJournal = { nativeDetails = false; onNavigate("insights") }, onOpenAlarms = { nativeDetails = false; onNavigate("smart_alarm") }, initialDayKey = snap?.restDayKey) }
        }
    }
    if (guide) BroopOverviewDialog({ guide = false }) { ScoringGuideScreen(onClose = { guide = false }) }
    if (customize) SleepArrangeSheet(SleepLayoutPrefs.order(LocalContext.current), SleepLayoutPrefs.hidden(LocalContext.current),
        onDismiss = { customize = false }, onSave = { order, hidden ->
            SleepLayoutPrefs.setOrder(context, order); SleepLayoutPrefs.setHidden(context, hidden)
            layoutRevision++; customize = false
        })
    sleepEdit?.let { edit -> BroopOverviewSleepEditor(edit, { sleepEdit = null }, onSave = { start, end ->
        check(if (edit.session != null) vm.updateSleepSessionTimes(edit.session, start, end) else vm.addManualNap(start, end))
        state.reload()
    }, onDelete = if (edit.session == null) null else suspend {
        val session = requireNotNull(edit.session)
        check(vm.deleteSleepSessions(listOf(session))); deleted = listOf(session); state.reload()
    }) }
    metricDetail?.let { key -> BroopOverviewDialog({ metricDetail = null }) {
        BroopOverviewMetricScreen(vm, broopOverviewSeriesKey(key), { metricDetail = null })
    } }
}

@Composable
private fun BroopOverviewSleepSections(vm: AppViewModel, snap: BroopOverviewSnapshot?, isToday: Boolean, layoutRevision: Int,
    onNavigate: (String) -> Unit, onMetric: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signals by vm.v5Signals.collectAsStateWithLifecycle()
    val sections = remember(layoutRevision) { SleepLayoutPrefs.order(context).filterNot { it in SleepLayoutPrefs.hidden(context) } }
    sections.forEach { section ->
        when (section) {
            SleepSection.TONIGHT -> if (isToday) {
                TonightPlanCard(vm)
                BroopRow(stringResource(R.string.broop_overview_set_alarm), icon = Icons.Filled.Schedule) { onNavigate("smart_alarm") }
            }
            SleepSection.SLEEP_MARKS -> if (isToday) SleepMarkCard { type ->
                val mark = com.noop.analytics.SleepMark.now(type)
                vm.ble.externalLog(mark.logLine())
                scope.launch { runCatching { vm.repo.upsertMetricSeries(listOf(mark.metricPoint(vm.activeStrapId))) } }
                android.widget.Toast.makeText(context, mark.confirmation(), android.widget.Toast.LENGTH_SHORT).show()
            }
            SleepSection.BODY_CLOCK -> {
                val phase = signals?.bodyClock
                val night = snap?.night
                if (phase != null && phase.confidence != com.noop.analytics.CircadianEngine.PhaseConfidence.UNREADABLE && night != null) {
                    BodyClockDialCard(phase, localClockHour(night.heroOnsetTs ?: night.session.effectiveStartTs), localClockHour(night.heroWakeTs ?: night.session.endTs))
                }
            }
            SleepSection.NIGHT_DETAIL -> snap?.sleepModel?.let { NightDetailHostCard(it, onMetric) }
            SleepSection.SLEEP_DEBT -> snap?.sleepModel?.let { SleepDebtLedgerHostCard(it) }
            SleepSection.STAGES_VS_TYPICAL -> snap?.sleepModel?.let { StagesVsTypicalHostCard(it) }
            SleepSection.HOURS_VS_NEEDED -> snap?.sleepModel?.let { HoursVsNeededCard(it) }
            SleepSection.CONSISTENCY -> snap?.sleepModel?.let { ConsistencyHostCard(it) }
            SleepSection.ASLEEP_DURATION -> snap?.sleepModel?.let { AsleepDurationHostCard(it.trendHours, it.trendDates) }
            SleepSection.STAGES -> Unit
        }
    }
}

@Composable
fun BroopScoreScreen(vm: AppViewModel, score: String, onNavigate: (String) -> Unit, onBack: (() -> Unit)? = null) {
    if (score == "rest") { BroopSleepScreen(vm, onNavigate, onBack); return }
    val state = rememberBroopOverview(vm)
    val snap = state.snapshot
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val baselines by vm.chargeBaselines.collectAsStateWithLifecycle()
    val isCharge = score == "charge"
    var breakdown by remember { mutableStateOf(false) }
    var guide by remember { mutableStateOf(false) }
    var startWorkout by remember { mutableStateOf(false) }
    var addWorkout by remember { mutableStateOf(false) }
    BroopOverviewPage(state, broopOverviewMaxOffset(days, logicalDayNow()), onBack, { guide = true }) {
        BroopOverviewHero(if (isCharge) snap?.charge else snap?.effort,
            if (isCharge) 100.0 else snap?.effortMax ?: 21.0, broopScoreColor(score, snap),
            stringResource(broopScoreTitle(score)), if (isCharge) "%" else "",
            target = if (isCharge) null else snap?.effortTarget?.let { (it.lower * snap.effortMax / 100)..(it.upper * snap.effortMax / 100) })
        if (isCharge && snap?.carriedChargeDay != null) BroopCaps(stringResource(R.string.broop_overview_carried, lastChargeDateLabel(snap.carriedChargeDay.day)), BroopPalette.textSecondary)
        if (isCharge && snap?.calibrationNights != null) Text(stringResource(R.string.broop_overview_calibrating, snap.calibrationNights), style = BroopType.caption, color = BroopPalette.textSecondary)
        if (isCharge) {
            BroopCard {
                listOf("hrv", "rhr", "resp_rate", "spo2").forEach { key ->
                    val reading = snap?.readings?.firstOrNull { it.key == key }
                    if (reading != null) BroopOverviewReadingRow(reading, onNavigate, card = false)
                }
                BroopOverviewContributor(stringResource(R.string.broop_overview_sleep_performance), snap?.rest, "%", Icons.Filled.Bedtime) { onNavigate("score/rest") }
            }
            BroopOverviewReadinessDetails(snap)
            BroopOverviewCoachLink(snap, "charge", onNavigate)
            BroopRow(stringResource(R.string.broop_overview_charge_breakdown), icon = Icons.Filled.Info) { breakdown = true }
            BroopRow(stringResource(R.string.broop_overview_behaviors), icon = Icons.Filled.Check) { onNavigate("insights_hub") }
        } else {
            BroopCard {
                val zones = snap?.zoneMinutes
                BroopOverviewContributorText(stringResource(R.string.broop_overview_zones_low), zones?.take(3)?.sum()?.let(::broopDurationText), Icons.Filled.Favorite) { onNavigate("vital_detail/hr_zones13_min") }
                BroopOverviewContributorText(stringResource(R.string.broop_overview_zones_high), zones?.drop(3)?.sum()?.let(::broopDurationText), Icons.Filled.Favorite) { onNavigate("vital_detail/hr_zones45_min") }
                snap?.readings?.filter { it.key in listOf("steps", "active_kcal") }?.forEach { BroopOverviewReadingRow(it, onNavigate, card = false) }
            }
            BroopCard {
                Text(stringResource(when {
                    snap?.effort == null -> R.string.broop_overview_no_effort
                    snap.effort / snap.effortMax * 21 < 10 -> R.string.broop_overview_light_effort
                    snap.effort / snap.effortMax * 21 < 14 -> R.string.broop_overview_moderate_effort
                    snap.effort / snap.effortMax * 21 < 18 -> R.string.broop_overview_high_effort
                    else -> R.string.broop_overview_peak_effort
                }), style = BroopType.body, color = BroopPalette.textBody)
                snap?.effortTarget?.let { target ->
                    val max = snap?.effortMax ?: 21.0
                    Text(stringResource(R.string.broop_overview_target, broopOverviewDecimal(target.lower * max / 100, 1),
                        broopOverviewDecimal(target.upper * max / 100, 1)), style = BroopType.caption, color = BroopPalette.effort)
                    broopEffortProgress(snap)?.let { Text(it, style = BroopType.demi, color = BroopPalette.effort) }
                }
                BroopOverviewCoachLink(snap, "effort", onNavigate)
            }
            BroopOverviewActivities(snap, state.dayOffset == 0, onNavigate, { addWorkout = true }, { startWorkout = true }, includeSleep = false)
            snap?.zoneMinutes?.let { BroopOverviewZones(it) }
        }
        BroopOverviewTrendCard(vm, snap, score, onNavigate)
        BroopRow(stringResource(R.string.broop_overview_day_hr), icon = Icons.Filled.MonitorHeart) { onNavigate("full_day_chart") }
    }
    if (breakdown) BroopOverviewDialog({ breakdown = false }) {
        BroopOverviewChargeBreakdown(snap, baselines,
            broopRestForRow(snap?.carriedChargeDay ?: snap?.day, snap?.restSeries.orEmpty(),
                NoopPrefs.of(LocalContext.current).getBoolean(com.noop.analytics.RestPerformanceV2.enabledKey, true)), { breakdown = false },
            { breakdown = false; guide = true }, { breakdown = false; onNavigate("vital_detail/recovery") })
    }
    if (guide) BroopOverviewDialog({ guide = false }) { ScoringGuideScreen(onClose = { guide = false }) }
    if (startWorkout) StartWorkoutSheet(vm) { startWorkout = false }
    if (addWorkout) ManualWorkoutDialog(editing = null, onDismiss = { addWorkout = false }, onSave = { row, replacing -> vm.saveManualWorkout(row, replacing); addWorkout = false; state.reload() })
}

@Composable
private fun BroopOverviewPage(state: BroopOverviewState, maxOffset: Int, onBack: (() -> Unit)?, onInfo: () -> Unit,
    content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(BroopPalette.background)) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = BroopMetrics.compactGap), verticalAlignment = Alignment.CenterVertically) {
                if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.broop_overview_back), tint = BroopPalette.textPrimary) }
                BroopOverviewDateNav(state, maxOffset, Modifier.weight(1f))
                IconButton(onClick = onInfo) { Icon(Icons.Filled.Info, stringResource(R.string.broop_overview_guide), tint = BroopPalette.textPrimary) }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).broopDaySwipe(state, maxOffset)
                .padding(horizontal = BroopMetrics.page).padding(bottom = BroopMetrics.tabBarClearance),
                verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap), content = content)
        }
    }
}

@Composable
internal fun BroopOverviewDateNav(state: BroopOverviewState, maxOffset: Int, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val date = logicalDayNow().minusDays(state.dayOffset.toLong())
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        IconButton(onClick = { state.step(1, maxOffset) }, enabled = state.dayOffset < maxOffset) {
            Icon(Icons.Filled.ChevronLeft, stringResource(R.string.broop_overview_previous_day), tint = if (state.dayOffset < maxOffset) BroopPalette.textPrimary else BroopPalette.textTertiary)
        }
        Text(broopDayLabel(state.dayOffset), style = BroopType.demi, color = BroopPalette.textPrimary,
            modifier = Modifier.clickable {
                DatePickerDialog(context, { _, year, month, day ->
                    state.dayOffset = ChronoUnit.DAYS.between(LocalDate.of(year, month + 1, day), logicalDayNow()).toInt().coerceIn(0, maxOffset)
                }, date.year, date.monthValue - 1, date.dayOfMonth).apply {
                    datePicker.maxDate = logicalDayNow().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    datePicker.minDate = logicalDayNow().minusDays(maxOffset.toLong()).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                }.show()
            }.padding(vertical = BroopMetrics.gap))
        IconButton(onClick = { state.step(-1, maxOffset) }, enabled = state.dayOffset > 0) {
            Icon(Icons.Filled.ChevronRight, stringResource(R.string.broop_overview_next_day), tint = if (state.dayOffset > 0) BroopPalette.textPrimary else BroopPalette.textTertiary)
        }
    }
}

private fun Modifier.broopDaySwipe(state: BroopOverviewState, maxOffset: Int): Modifier = pointerInput(state, maxOffset) {
    var distance = 0f
    detectHorizontalDragGestures(onDragStart = { distance = 0f }, onDragEnd = {
        if (abs(distance) > BroopMetrics.touch.toPx()) state.step(if (distance > 0) 1 else -1, maxOffset)
    }) { _, amount -> distance += amount }
}

@Composable
private fun broopDayLabel(offset: Int): String = when (offset) {
    0 -> stringResource(R.string.broop_overview_today)
    1 -> stringResource(R.string.broop_overview_yesterday)
    else -> logicalDayNow().minusDays(offset.toLong()).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.getDefault()))
}

private fun broopScoreTitle(score: String): Int = when (score) {
    "rest" -> R.string.broop_overview_rest
    "effort" -> R.string.broop_overview_effort
    else -> R.string.broop_overview_charge
}

private fun broopScoreColor(score: String, snap: BroopOverviewSnapshot?): Color = when (score) {
    "rest" -> BroopPalette.rest
    "effort" -> BroopPalette.effort
    else -> snap?.charge?.let(BroopPalette::band) ?: BroopPalette.textSecondary
}

@Composable
private fun BroopOverviewRings(snap: BroopOverviewSnapshot?, onNavigate: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = BroopMetrics.page), horizontalArrangement = Arrangement.SpaceEvenly) {
        BroopRing(snap?.rest, color = BroopPalette.rest, label = stringResource(R.string.broop_overview_rest)) { onNavigate("score/rest") }
        BroopRing(snap?.charge, color = broopScoreColor("charge", snap), label = stringResource(R.string.broop_overview_charge)) { onNavigate("score/charge") }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            BroopRing(snap?.effort, snap?.effortMax ?: 21.0, BroopPalette.effort, stringResource(R.string.broop_overview_effort), "",
                target = snap?.effortTarget?.let { (it.lower * snap.effortMax / 100)..(it.upper * snap.effortMax / 100) }) { onNavigate("score/effort") }
            broopEffortProgress(snap)?.let { Text(it, style = BroopType.caption, color = BroopPalette.textSecondary,
                modifier = Modifier.clickable { onNavigate("score/effort") }) }
        }
    }
}

@Composable
private fun broopEffortProgress(snap: BroopOverviewSnapshot?): String? {
    val target = snap?.effortTarget ?: return null
    val effort = snap.effort ?: return null
    return when (target.zone(effort * 100 / snap.effortMax)) {
        com.noop.analytics.StrainTarget.Zone.RESTORING -> stringResource(R.string.broop_overview_effort_to_target,
            broopOverviewDecimal(target.lower * snap.effortMax / 100 - effort, 1))
        com.noop.analytics.StrainTarget.Zone.OPTIMAL -> stringResource(R.string.broop_overview_effort_in_target)
        com.noop.analytics.StrainTarget.Zone.OVERREACHING -> stringResource(R.string.broop_overview_effort_above_target)
    }
}

@Composable
internal fun BroopOverviewHero(value: Double?, max: Double = 100.0, color: Color, title: String, unit: String = "%",
    target: ClosedFloatingPointRange<Double>? = null) {
    Column(Modifier.fillMaxWidth().padding(vertical = BroopMetrics.sectionGap), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(BroopMetrics.page)) {
        Box(Modifier.size(BroopMetrics.ring * 2.1f), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = BroopMetrics.ringStroke.toPx() * 1.35f
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(BroopPalette.track, -90f, 360f, false, Offset(stroke / 2, stroke / 2), arcSize, style = Stroke(stroke))
                if (target != null) {
                    drawArc(color.copy(alpha = 0.3f), (target.start / max * 360 - 90).toFloat(),
                        ((target.endInclusive - target.start) / max * 360).toFloat(), false,
                        Offset(stroke / 2, stroke / 2), arcSize, style = Stroke(stroke * 1.8f))
                    val angle = ((target.start + target.endInclusive) / 2 / max * 2 * Math.PI - Math.PI / 2)
                    val radius = (size.width - stroke) / 2
                    val vector = Offset(kotlin.math.cos(angle).toFloat(), kotlin.math.sin(angle).toFloat())
                    drawLine(color, center + vector * (radius - stroke), center + vector * (radius + stroke), stroke / 3)
                }
                if (value != null && value.isFinite()) drawArc(color, -90f, (value / max).coerceIn(0.0, 1.0).toFloat() * 360,
                    false, Offset(stroke / 2, stroke / 2), arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(value?.let { if (unit.isEmpty()) broopOverviewDecimal(it, 1) else it.roundToInt().toString() } ?: "—",
                    style = BroopType.largeNumber, color = BroopPalette.textPrimary)
                if (value != null && unit.isNotEmpty()) Text(unit, style = BroopType.section, color = BroopPalette.textPrimary)
            }
        }
        BroopCaps(title)
    }
}

@Composable
private fun BroopOverviewMonitor(title: String, value: String, detail: String, color: Color, icon: ImageVector,
    modifier: Modifier, onClick: () -> Unit) {
    Column(modifier.clip(RoundedCornerShape(BroopMetrics.tileRadius)).background(BroopPalette.tile)
        .clickable(role = Role.Button, onClick = onClick).padding(BroopMetrics.page),
        verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = BroopType.caption, color = BroopPalette.textPrimary, modifier = Modifier.weight(1f))
            Icon(icon, null, tint = color, modifier = Modifier.size(BroopMetrics.smallIcon))
        }
        Text(value, style = BroopType.demi, color = color)
        Text(detail, style = BroopType.caption, color = BroopPalette.textSecondary)
    }
}

@Composable
private fun BroopOverviewStressMonitor(vm: AppViewModel, day: String, modifier: Modifier, onClick: () -> Unit) {
    val load by rememberBroopStressDay(vm, day)
    val result = load.result.takeIf { load.day == day }
    val current = rememberBroopStressNow(vm, result)
    BroopOverviewMonitor(stringResource(R.string.broop_overview_stress_monitor),
        if (current?.active == true) stringResource(R.string.broop_overview_active)
        else current?.level?.let { broopOverviewDecimal(it, 1) } ?: stringResource(R.string.broop_overview_no_data),
        if (current?.live == true) stringResource(R.string.broop_overview_live_stress)
        else current?.ts?.let { broopTime(it) } ?: stringResource(R.string.broop_overview_latest_reading),
        BroopPalette.warning, Icons.Filled.Bolt, modifier, onClick)
}

@Composable
private fun BroopOverviewActivities(snap: BroopOverviewSnapshot?, isToday: Boolean, onNavigate: (String) -> Unit,
    onAdd: () -> Unit, onStart: () -> Unit, includeSleep: Boolean = true) {
    val scale = UnitPrefs.effortScale(LocalContext.current)
    BroopCard {
        Row(Modifier.fillMaxWidth().clickable { onNavigate("workouts") }, verticalAlignment = Alignment.CenterVertically) {
            BroopCaps(stringResource(if (isToday) R.string.broop_overview_activities_today else R.string.broop_overview_activities))
            Spacer(Modifier.weight(1f))
            Icon(Icons.Filled.ChevronRight, null, tint = BroopPalette.textSecondary, modifier = Modifier.size(BroopMetrics.smallIcon))
        }
        if (includeSleep) {
            if (snap?.asleepMinutes != null) BroopOverviewActivityRow(stringResource(R.string.broop_overview_sleep), broopDurationText(snap.asleepMinutes!!),
                BroopPalette.rest, snap.night?.heroOnsetTs ?: snap.night?.session?.effectiveStartTs,
                snap.night?.heroWakeTs ?: snap.night?.session?.endTs, Icons.Filled.Bedtime) { onNavigate("score/rest") }
            else BroopRow(stringResource(R.string.broop_overview_no_sleep), stringResource(R.string.broop_overview_add_sleep), Icons.Filled.Bedtime) { onNavigate("score/rest") }
        }
        snap?.workouts.orEmpty().forEach { row ->
            BroopOverviewActivityRow(WorkoutEditing.displaySport(row), row.strain?.let { UnitFormatter.effortDisplay(it, scale) } ?: "—",
                BroopPalette.effort, row.startTs, row.endTs, Icons.Filled.FitnessCenter) {
                NoopRouteBus.postWorkoutDetected(WorkoutDetectedRoute(row.startTs, row.endTs, false)); onNavigate("workouts")
            }
        }
        if (!includeSleep && snap?.workouts.isNullOrEmpty()) Text(stringResource(R.string.broop_overview_no_activities), style = BroopType.body, color = BroopPalette.textSecondary)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            BroopOverviewFillButton(stringResource(R.string.broop_overview_add_activity), Icons.Filled.Add, Modifier.weight(1f), onAdd)
            if (isToday) BroopOverviewFillButton(stringResource(R.string.broop_overview_start_activity), Icons.Filled.Schedule, Modifier.weight(1f), onStart)
        }
    }
}

@Composable
private fun BroopOverviewFillButton(title: String, icon: ImageVector, modifier: Modifier = Modifier, action: () -> Unit) {
    Row(modifier.clip(RoundedCornerShape(BroopMetrics.rowRadius)).background(BroopPalette.row)
        .clickable(role = Role.Button, onClick = action).heightIn(min = BroopMetrics.touch).padding(BroopMetrics.gap),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        Icon(icon, null, tint = BroopPalette.textPrimary, modifier = Modifier.size(BroopMetrics.smallIcon))
        Spacer(Modifier.width(BroopMetrics.compactGap))
        Text(title, style = BroopType.caption, color = BroopPalette.textPrimary, textAlign = TextAlign.Center)
    }
}

@Composable
private fun BroopOverviewActivityRow(title: String, value: String, color: Color, start: Long?, end: Long?, icon: ImageVector, action: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(BroopMetrics.innerRadius)).background(BroopPalette.pillOuter)
        .clickable(role = Role.Button, onClick = action).padding(BroopMetrics.gap), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Row(Modifier.clip(RoundedCornerShape(BroopMetrics.rowRadius)).background(color).padding(BroopMetrics.gap),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
            Icon(icon, null, tint = BroopPalette.textPrimary, modifier = Modifier.size(BroopMetrics.smallIcon))
            Text(value, style = BroopType.demi, color = BroopPalette.textPrimary)
        }
        Text(title, style = BroopType.caps, color = BroopPalette.textPrimary, modifier = Modifier.weight(1f))
        if (start != null && end != null) Column(horizontalAlignment = Alignment.End) {
            Text(broopTime(start), style = BroopType.caption, color = BroopPalette.textBody)
            Text(broopTime(end), style = BroopType.caption, color = BroopPalette.textBody)
        }
    }
}

@Composable
private fun BroopOverviewTonight(vm: AppViewModel, onClick: () -> Unit) {
    val plan by vm.tonightPlan.collectAsStateWithLifecycle()
    BroopCard(onClick = onClick) {
        BroopCaps(stringResource(R.string.broop_overview_tonight))
        val p = plan
        if (p != null) {
            Text(stringResource(R.string.broop_overview_bed_by, clockLabel(p.target.bedMinute)), style = BroopType.section, color = BroopPalette.textPrimary)
            Text(stringResource(R.string.broop_overview_sleep_needed, broopDurationText(p.needMin)), style = BroopType.caption, color = BroopPalette.textSecondary)
        } else Text(stringResource(R.string.broop_overview_set_alarm), style = BroopType.body, color = BroopPalette.textSecondary)
    }
}

@Composable
private fun BroopOverviewJournal(snap: BroopOverviewSnapshot?, date: LocalDate, action: () -> Unit) {
    val done = date.toString() in snap?.journalDays.orEmpty()
    val weekdayFormat = DateTimeFormatter.ofPattern("EEEEE", Locale.getDefault())
    BroopCard(onClick = action) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Check, null, tint = if (done) BroopPalette.teal else BroopPalette.textSecondary)
            Spacer(Modifier.width(BroopMetrics.gap))
            Text(stringResource(R.string.broop_overview_journal), style = BroopType.caps, color = BroopPalette.textPrimary, modifier = Modifier.weight(1f))
            Text(stringResource(if (done) R.string.broop_overview_edit else R.string.broop_overview_fill_out), style = BroopType.caption, color = BroopPalette.textPrimary)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            (6 downTo 0).forEach { back ->
                val day = date.minusDays(back.toLong())
                val logged = day.toString() in snap?.journalDays.orEmpty()
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
                    Text(day.format(weekdayFormat), style = BroopType.caption, color = BroopPalette.textSecondary)
                    Box(Modifier.size(BroopMetrics.mark).clip(CircleShape)
                        .background(if (logged) BroopPalette.teal else BroopPalette.card)
                        .border(BroopMetrics.ringStroke / 5, if (logged) BroopPalette.teal else BroopPalette.textTertiary, CircleShape), contentAlignment = Alignment.Center) {
                        if (logged) Icon(Icons.Filled.Check, null, tint = BroopPalette.bgBottom, modifier = Modifier.size(BroopMetrics.smallIcon))
                    }
                }
            }
        }
    }
}

@Composable
private fun BroopOverviewReadingRow(reading: BroopOverviewReading, onNavigate: (String) -> Unit, card: Boolean = true) {
    val content: @Composable ColumnScope.() -> Unit = {
        Row(Modifier.fillMaxWidth().clickable { onNavigate("vital_detail/${when (reading.key) { "resp_rate" -> "resp"; "steps" -> "steps_est"; else -> reading.key }}") }, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            Icon(broopMetricIcon(reading.key), null, tint = BroopPalette.textSecondary, modifier = Modifier.size(BroopMetrics.icon))
            Text(stringResource(broopMetricTitle(reading.key)), style = BroopType.caps, color = BroopPalette.textPrimary, modifier = Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.End) {
                Text(broopMetricValue(reading.key, reading.value), style = BroopType.demi, color = BroopPalette.textPrimary)
                Text(reading.baseline?.let { stringResource(R.string.broop_overview_30_day_average, broopMetricValue(reading.key, it)) }
                    ?: stringResource(R.string.broop_overview_baseline_building), style = BroopType.caption, color = BroopPalette.textSecondary)
            }
            Icon(Icons.Filled.ChevronRight, null, tint = BroopPalette.textSecondary, modifier = Modifier.size(BroopMetrics.smallIcon))
        }
    }
    if (card) BroopCard(content = content) else Column(Modifier.padding(vertical = BroopMetrics.gap), content = content)
}

private fun broopMetricTitle(key: String): Int = when (key) {
    "hrv" -> R.string.broop_overview_hrv
    "rhr" -> R.string.broop_overview_rhr
    "resp_rate" -> R.string.broop_overview_resp
    "spo2" -> R.string.broop_overview_spo2
    "steps" -> R.string.broop_overview_steps
    else -> R.string.broop_overview_calories
}

private fun broopMetricIcon(key: String): ImageVector = when (key) {
    "hrv" -> Icons.Filled.MonitorHeart
    "rhr" -> Icons.Filled.Favorite
    "resp_rate" -> Icons.Filled.Air
    "spo2" -> Icons.Filled.WaterDrop
    "steps" -> Icons.Filled.FitnessCenter
    else -> Icons.Filled.LocalFireDepartment
}

private fun broopMetricValue(key: String, value: Double): String = when (key) {
    "hrv" -> "${value.roundToInt()} ms"
    "rhr" -> "${value.roundToInt()} bpm"
    "resp_rate" -> "${broopOverviewDecimal(value, 1)} rpm"
    "spo2" -> "${value.roundToInt()}%"
    "active_kcal" -> "${value.roundToInt()} kcal"
    else -> String.format(Locale.getDefault(), "%,d", value.roundToInt())
}

@Composable
private fun BroopOverviewContributor(title: String, value: Double?, unit: String, icon: ImageVector, action: (() -> Unit)? = null) =
    BroopOverviewContributorText(title, value?.let { "${it.roundToInt()}$unit" }, icon, action)

@Composable
private fun BroopOverviewContributorText(title: String, value: String?, icon: ImageVector, action: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().then(if (action != null) Modifier.clickable(role = Role.Button, onClick = action) else Modifier)
        .heightIn(min = BroopMetrics.touch), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Icon(icon, null, tint = BroopPalette.textSecondary, modifier = Modifier.size(BroopMetrics.icon))
        Text(title, style = BroopType.caption, color = BroopPalette.textBody, modifier = Modifier.weight(1f))
        Text(value ?: "—", style = BroopType.demi, color = BroopPalette.textPrimary)
        if (action != null) Icon(Icons.Filled.ChevronRight, null, tint = BroopPalette.textSecondary, modifier = Modifier.size(BroopMetrics.smallIcon))
    }
}

@Composable
private fun BroopOverviewNight(vm: AppViewModel, snap: BroopOverviewSnapshot) {
    val night = snap.night
    val model = snap.sleepModel
    var heartRate by remember(night?.heroOnsetTs, night?.session?.startTs, night?.heroWakeTs) {
        mutableStateOf<List<com.noop.data.HrBucket>>(emptyList())
    }
    var why by remember(night?.session?.startTs) { mutableStateOf(false) }
    LaunchedEffect(night, vm.activeStrapId) {
        heartRate = emptyList()
        if (night != null) heartRate = runCatching { vm.repo.hrBucketsUnion(vm.activeStrapId,
            night.heroOnsetTs ?: night.session.effectiveStartTs, night.heroWakeTs ?: night.session.endTs, 60) }.getOrDefault(emptyList())
    }
    BroopCard {
        BroopCaps(stringResource(R.string.broop_overview_sleep_asleep), BroopPalette.textSecondary)
        Text((model?.stages?.asleep ?: snap.asleepMinutes)?.let(::broopDurationText) ?: "—", style = BroopType.number, color = BroopPalette.textPrimary)
        if (night != null) Text(night.clockLabel, style = BroopType.caption, color = BroopPalette.textBody)
        if (heartRate.size >= 2) LineChart(heartRate.map { it.avgBpm }, Modifier.fillMaxWidth().height(BroopMetrics.ring),
            BroopPalette.rest, fill = false, timestamps = heartRate.map { it.bucket }, selectionEnabled = true,
            formatValue = { "${it.roundToInt()} bpm" })
        val segments = model?.realSegments
        if (model != null && segments != null && segments.size >= 2 && night != null) {
            StageTimeline(segments, model.stages, night.heroOnsetTs ?: night.session.effectiveStartTs,
                night.heroWakeTs ?: night.session.endTs, night.groupMotion)
            Text(stringResource(if (com.noop.data.DeviceBrandCatalog.isOura(night.session.deviceId)) R.string.broop_overview_raw_ring_stages else R.string.broop_overview_stages_estimated), style = BroopType.caption, color = BroopPalette.textSecondary)
        } else {
            val stages = listOf(
                Triple(R.string.broop_overview_sleep_deep, model?.stages?.deep ?: snap.restDay?.deepMin, BroopPalette.stageDeep),
                Triple(R.string.broop_overview_sleep_light, model?.stages?.light ?: snap.restDay?.lightMin, BroopPalette.stageLight),
                Triple(R.string.broop_overview_sleep_rem, model?.stages?.rem ?: snap.restDay?.remMin, BroopPalette.stageREM),
            )
            val total = stages.sumOf { it.second ?: 0.0 }.coerceAtLeast(1.0)
            if (stages.any { (it.second ?: 0.0) > 0 }) Row(Modifier.fillMaxWidth().height(BroopMetrics.gap)) {
                stages.filter { (it.second ?: 0.0) > 0 }.forEach { stage -> Box(Modifier.weight((stage.second!! / total).toFloat()).height(BroopMetrics.gap).background(stage.third)) }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                stages.forEach { stage -> Column {
                    Text(stringResource(stage.first), style = BroopType.caption, color = stage.third)
                    Text(stage.second?.let(::broopDurationText) ?: "—", style = BroopType.demi, color = BroopPalette.textPrimary)
                } }
            }
        }
        val deepRem = model?.stages?.let { it.deep + it.rem }
        BroopOverviewContributorText(stringResource(R.string.broop_overview_restorative), deepRem?.let(::broopDurationText), Icons.Filled.Bolt)
        if (night != null) {
            SleepWindowRow(night.heroOnsetTs ?: night.session.effectiveStartTs, night.heroWakeTs ?: night.session.endTs)
            BroopCaps(stringResource(when {
                night.session.deviceId.endsWith("-noop") -> R.string.today_source_on_device
                com.noop.data.DeviceBrandCatalog.isOura(night.session.deviceId) -> R.string.today_source_oura
                night.session.deviceId == "apple-health" -> R.string.today_source_apple_health
                else -> R.string.today_source_whoop
            }), BroopPalette.rest)
            val blocks = (night.heroGroup.ifEmpty { listOf(night.session) } + night.napBlocks)
            val selection = com.noop.analytics.SleepStageTotals.mainNightSelection(blocks.map {
                com.noop.analytics.SleepStageTotals.NightBlock.fromSession(it)
            }, uiTzOffsetSec(), snap.habitualMidsleepSec)
            if (selection != null) {
                TextButton(onClick = { why = !why }) { Text(stringResource(R.string.l10n_sleep_screen_why_this_sleep_ab42b016), color = BroopPalette.rest) }
                if (why) Text(stringResource(when (selection.reason) {
                    com.noop.analytics.SleepStageTotals.MainNightReason.onlyBlock -> R.string.broop_overview_main_only
                    com.noop.analytics.SleepStageTotals.MainNightReason.longest -> R.string.broop_overview_main_longest
                    com.noop.analytics.SleepStageTotals.MainNightReason.longestNearUsual -> R.string.broop_overview_main_longest_usual
                    com.noop.analytics.SleepStageTotals.MainNightReason.alignedToUsual -> R.string.broop_overview_main_usual
                }), style = BroopType.body, color = BroopPalette.textBody)
            }
        }
    }
    if (night != null && model != null) {
        val stages = model.stages
        val efficiency = night.session.efficiency?.let { if (it > 1) it / 100 else it }
            ?: stages.total.takeIf { it > 0 }?.let { stages.asleep / it }
        if (efficiency != null && stageStagingIsLowConfidence(stages.asleep, stages.deep, stages.rem, efficiency)) {
            BroopCard { BroopCaps(stringResource(R.string.l10n_sleep_screen_low_confidence_99d4ceae), BroopPalette.warning)
                Text(stringResource(R.string.l10n_sleep_screen_this_night_scored_high_efficiency_but_a11d90eb), style = BroopType.body, color = BroopPalette.textBody) }
        }
        val blocks = night.heroGroup.ifEmpty { listOf(night.session) }
        if (stageSparseNoteApplies(anyBlockStagingSparse(blocks), stages.asleep)) BroopCard {
            BroopCaps(stringResource(R.string.l10n_sleep_screen_may_be_incomplete_7230dc27), BroopPalette.warning)
            Text(stringResource(R.string.l10n_sleep_screen_little_motion_was_recorded_over_f061b7e4), style = BroopType.body, color = BroopPalette.textBody)
        }
        val coverage = com.noop.analytics.HypnogramCoverage.groupFraction(blocks.map {
            com.noop.analytics.HypnogramCoverage.Fragment(it.stagesJSON, (it.endTs - it.startTs).toDouble())
        })
        if (coverage != null && coverage < com.noop.analytics.HypnogramCoverage.minCoverage) BroopCard {
            BroopCaps(stringResource(R.string.l10n_sleep_screen_partly_recorded_f43509ab), BroopPalette.warning)
            Text(stringResource(R.string.l10n_sleep_screen_only_of_this_night_s_window_9660332a, (coverage * 100).roundToInt()), style = BroopType.body, color = BroopPalette.textBody)
        }
    }
}

@Composable
private fun BroopOverviewCoachLink(snap: BroopOverviewSnapshot?, score: String, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    if (NoopPrefs.of(context).getBoolean("noop.coachEnabled", true)) TextButton(onClick = {
        CoachHandoff.pendingPrompt = context.getString(R.string.broop_overview_coach_question,
            context.getString(broopScoreTitle(score)), snap?.dayKey ?: logicalDayKeyNow())
        onNavigate("coach")
    }) {
        Text(stringResource(R.string.broop_overview_ask_coach), style = BroopType.caption, color = BroopPalette.textPrimary)
    }
}

@Composable
private fun BroopOverviewZones(minutes: List<Double>) {
    BroopSection(stringResource(R.string.broop_overview_zones))
    val colors = listOf(BroopPalette.rest, BroopPalette.effort, BroopPalette.teal, BroopPalette.warning, BroopPalette.bandLow)
    val total = minutes.sum().coerceAtLeast(1.0)
    BroopCard {
        minutes.take(5).indices.reversed().forEach { i ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                Text(stringResource(R.string.broop_overview_zone, i + 1), style = BroopType.caption, color = colors[i])
                Box(Modifier.weight(1f).height(BroopMetrics.gap).background(BroopPalette.track, RoundedCornerShape(BroopMetrics.compactGap))) {
                    if (minutes[i] > 0) Box(Modifier.fillMaxWidth((minutes[i] / total).toFloat()).height(BroopMetrics.gap).background(colors[i], RoundedCornerShape(BroopMetrics.compactGap)))
                }
                Text(broopDurationText(minutes[i]), style = BroopType.caption, color = BroopPalette.textPrimary)
            }
        }
    }
}

@Composable
private fun BroopOverviewDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false), content = content)
}

private fun broopDurationText(minutes: Double): String = hoursMinutes(minutes)

@Composable
private fun broopTime(timestamp: Long): String {
    val is24h = ClockPrefs.uses24Hour(LocalContext.current)
    return Instant.ofEpochSecond(timestamp).atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofPattern(if (is24h) "HH:mm" else "h:mm a", Locale.getDefault()))
}

private fun broopOverviewDecimal(value: Double, decimals: Int): String = String.format(Locale.getDefault(), "%.${decimals}f", value)
