package com.noop.ui

import com.noop.R

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.VitalityWindow
import com.noop.analytics.BroopMindDay
import com.noop.analytics.BroopMindEngine
import com.noop.data.MetricSeriesRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.sqrt


private data class BroopMindData(val days: List<BroopMindDay> = emptyList(),
    val checkIns: Map<String, Map<BroopMindEngine.Form, Int>> = emptyMap(), val loaded: Boolean = false, val failed: Boolean = false)

@Composable
fun BroopMindScreen(vm: AppViewModel, onBack: (() -> Unit)? = null) {
    val dailies by vm.recentDays.collectAsStateWithLifecycle()
    var revision by remember { mutableStateOf(0) }
    var data by remember { mutableStateOf(BroopMindData()) }
    var showForm by rememberSaveable { mutableStateOf(false) }
    var deleteDay by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val today = LocalDate.now().toString()
    LaunchedEffect(dailies, vm.activeStrapId, revision) {
        try {
            data = withContext(Dispatchers.IO) {
                val all = mutableMapOf<String, MutableMap<String, Double>>()
                for (key in listOf("stress_high_min", "stress_low_min", "stress_scored_min", "sleep_stress_pct", "sleep_performance")) {
                    if (key == "sleep_performance") {
                        vm.repo.resolvedSeries(key, "my-whoop", LocalDate.now().minusDays(120).toString(), today, strapDeviceId = vm.activeStrapId)
                            .points.forEach { all.getOrPut(it.day) { mutableMapOf() }[key] = it.value }
                    } else vm.repo.metricSeriesComputedUnion(vm.activeStrapId, key, LocalDate.now().minusDays(120).toString(), today)
                            .forEach { all.getOrPut(it.day) { mutableMapOf() }[key] = it.value }
                }
                dailies.forEach { d -> d.recovery?.let { all.getOrPut(d.day) { mutableMapOf() }["charge"] = it } }
                val mindDays = all.toSortedMap().map { (day, v) -> BroopMindDay(day, v["stress_high_min"], v["stress_low_min"],
                    v["stress_scored_min"], v["sleep_stress_pct"], v["sleep_performance"], v["charge"]) }
                val checkIns = mutableMapOf<String, MutableMap<BroopMindEngine.Form, Int>>()
                for (form in BroopMindEngine.Form.entries) {
                    vm.repo.metricSeries("noop-mind", form.key, "0000-01-01", today).forEach { row ->
                        if (row.value.isFinite() && row.value == kotlin.math.floor(row.value) && row.value in 0.0..form.maximum.toDouble())
                            checkIns.getOrPut(row.day) { mutableMapOf() }[form] = row.value.toInt()
                    }
                }
                BroopMindData(mindDays, checkIns.toSortedMap(), loaded = true)
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { data = data.copy(loaded = true, failed = true) }
    }
    val resilience = remember(data, today) { BroopMindEngine.resilience(data.days, today) }
    val cumulative = remember(data, today) { BroopMindEngine.cumulative(data.days, today) }
    val stressDays = BroopMindEngine.window(data.days, today, 14).count { it.hasDaytimeStress }
    val loadDays = BroopMindEngine.window(data.days, today, 31).count { BroopMindEngine.dayLoad(it) != null }
    BroopPage(uiString(R.string.explore_category_mind), onBack) {
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_resilience_14_days_4f3ccfb))
            Text(resilience?.level?.let(::broopMindLevel) ?: "--", style = BroopType.section, color = BroopPalette.textPrimary)
            Text(resilience?.let { listOf(it.score.toInt().toString() + " / 100", broopMindTrend(it.trend)).joinToString(" · ") }
                ?: if (!data.loaded) uiString(R.string.broop_body_reading_your_mind_data_7c64be4) else uiString(R.string.broop_body_1_s_of_7_days_with_enough_daytime_stress_data_1d00cde, (stressDays).toString()),
                style = BroopType.body, color = BroopPalette.textBody)
            if (resilience != null) {
                BroopBodyValue(uiString(R.string.broop_body_daytime_high_stress_323805b), "${(resilience.highShare * 100).toInt()}%")
                BroopBodyValue(uiString(R.string.broop_body_calm_waking_time_8470c1b), "${(resilience.lowShare * 100).toInt()}%")
                resilience.nightRecovery?.let { BroopBodyValue(uiString(R.string.broop_body_overnight_recovery_15b6112), "${(it * 100).toInt()}%") }
                BroopBodyChart(BroopMindEngine.history(data.days, today, 90, true).map { it.second }, BroopPalette.teal, uiString(R.string.broop_body_resilience_history_868c2b3))
            }
        }
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_cumulative_stress_31_days_86aa244))
            Text(cumulative?.level?.let(::broopMindLevel) ?: "--", style = BroopType.section, color = BroopPalette.textPrimary)
            Text(cumulative?.let { listOf(it.score.toInt().toString() + " / 100", broopMindTrend(it.trend)).joinToString(" · ") }
                ?: uiString(R.string.broop_body_1_s_of_21_days_with_enough_stress_data_c190b8e, (loadDays).toString()), style = BroopType.body, color = BroopPalette.textBody)
            if (cumulative != null) {
                cumulative.daytimeLoad?.let { BroopBodyValue(uiString(R.string.broop_body_daytime_load_b15c746), "${(it * 100).toInt()}%") }
                cumulative.sleepLoad?.let { BroopBodyValue(uiString(R.string.broop_body_sleep_load_54b17b6), "${(it * 100).toInt()}%") }
                cumulative.recoveryLoad?.let { BroopBodyValue(uiString(R.string.broop_body_charge_shortfall_b2453fe), "${(it * 100).toInt()}%") }
                BroopBodyChart(BroopMindEngine.history(data.days, today, 90, false).map { it.second }, BroopPalette.effort, uiString(R.string.broop_body_cumulative_stress_history_397e0c1))
            }
        }
        if (data.failed) Text(uiString(R.string.broop_body_mind_data_could_not_be_read_open_this_screen__b0a87d2), style = BroopType.body, color = BroopPalette.warning)
        BroopSection(uiString(R.string.broop_body_monthly_check_in_8283f7e))
        BroopCard {
            Text(uiString(R.string.broop_body_eight_short_questions_about_perceived_stress__88b9168), style = BroopType.body, color = BroopPalette.textBody)
            BroopBodyButton(if (BroopMindEngine.isDue(data.checkIns.keys.lastOrNull(), today)) uiString(R.string.broop_body_complete_check_in_42fb987) else uiString(R.string.broop_body_update_check_in_cf26fbe)) { showForm = true }
        }
        data.checkIns.entries.reversed().take(12).forEach { (day, scores) ->
            BroopCard {
                BroopCaps(day)
                BroopMindEngine.Form.entries.forEach { form -> scores[form]?.let { BroopBodyValue(broopMindFormTitle(form), "$it / ${form.maximum}") } }
                TextButton(onClick = { deleteDay = day }) { Text(uiString(R.string.broop_body_delete_check_in_f02f075), color = BroopPalette.textSecondary) }
            }
        }
        if (data.checkIns.size >= 5) {
            BroopSection(uiString(R.string.broop_body_check_ins_your_body_1554df9))
            BroopCard {
                var hasLink = false
                BroopMindEngine.Form.entries.forEach { form ->
                    val scores = data.checkIns.mapNotNull { (day, values) -> values[form]?.let { day to it.toDouble() } }
                    for ((label, series) in listOf(uiString(R.string.today_metric_charge) to dailies.mapNotNull { d -> d.recovery?.let { d.day to it } },
                        "HRV" to dailies.mapNotNull { d -> d.avgHrv?.let { d.day to it } })) {
                        BroopMindEngine.correlate(scores, series, if (form == BroopMindEngine.Form.PSS4) 30 else 14)?.let { link ->
                            hasLink = true
                            BroopBodyValue(listOf(broopMindFormTitle(form), label).joinToString(" & "), if (abs(link.r) < 0.3) uiString(R.string.broop_body_no_clear_link_2f6562f) else "r = ${broopOne(link.r)} · n = ${link.n}")
                        }
                    }
                }
                if (!hasLink) Text(uiString(R.string.broop_body_more_overlapping_history_is_needed_to_compare_5952449), style = BroopType.body, color = BroopPalette.textBody)
            }
        }
        BroopSection(uiString(R.string.broop_body_daily_mood_0044be6))
        MindSection(vm)
        Text(uiString(R.string.broop_body_mind_describes_recorded_physiological_stress__d50419c),
            style = BroopType.caption, color = BroopPalette.textSecondary)
    }
    if (showForm) BroopMindForm(vm, onClose = { showForm = false }, onSaved = { revision++ })
    deleteDay?.let { day -> AlertDialog(onDismissRequest = { deleteDay = null }, title = { Text(uiString(R.string.broop_body_delete_check_in_3c86102)) },
        text = { Text(uiString(R.string.broop_body_the_monthly_scores_for_1_s_will_be_removed_fr_4527f7b, (day).toString())) },
        confirmButton = { TextButton(onClick = { deleteDay = null; scope.launch {
            try { withContext(Dispatchers.IO) { BroopMindEngine.Form.entries.forEach { vm.repo.deleteMetricSeriesPoint("noop-mind", day, it.key) } }; revision++ }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { error = uiString(R.string.broop_body_the_check_in_was_not_deleted_please_try_again_e84df5c) }
        } }) { Text(uiString(R.string.ground_truth_delete_confirm)) } }, dismissButton = { TextButton(onClick = { deleteDay = null }) { Text(uiString(R.string.ground_truth_cancel)) } }) }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null }, text = { Text(message) },
        confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }) }
}

private val broopMindQuestions = listOf(
    uiString(R.string.broop_body_in_the_last_month_how_often_have_you_felt_tha_7226828),
    uiString(R.string.broop_body_in_the_last_month_how_often_have_you_felt_con_9966976),
    uiString(R.string.broop_body_in_the_last_month_how_often_have_you_felt_tha_1d6591d),
    uiString(R.string.broop_body_in_the_last_month_how_often_have_you_felt_dif_82b88dc),
    uiString(R.string.broop_body_over_the_last_2_weeks_how_often_have_you_been_977e3b7),
    uiString(R.string.broop_body_over_the_last_2_weeks_how_often_have_you_been_1797060),
    uiString(R.string.broop_body_over_the_last_2_weeks_how_often_have_you_been_4edeb0a),
    uiString(R.string.broop_body_over_the_last_2_weeks_how_often_have_you_been_65a307b),
)

@Composable
private fun BroopMindForm(vm: AppViewModel, onClose: () -> Unit, onSaved: () -> Unit) {
    var answers by rememberSaveable { mutableStateOf(List(8) { -1 }) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf<Map<BroopMindEngine.Form, Int>?>(null) }
    val scope = rememberCoroutineScope()
    val totals = mapOf(BroopMindEngine.Form.PSS4 to BroopMindEngine.score(BroopMindEngine.Form.PSS4, answers.take(4)),
        BroopMindEngine.Form.GAD2 to BroopMindEngine.score(BroopMindEngine.Form.GAD2, answers.subList(4, 6)),
        BroopMindEngine.Form.PHQ2 to BroopMindEngine.score(BroopMindEngine.Form.PHQ2, answers.takeLast(2)))
    Dialog(onDismissRequest = { if (!saving) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(uiString(R.string.broop_body_monthly_check_in_8283f7e), onBack = { if (!saving) onClose() }) {
            if (saved != null) {
                BroopCard {
                    BroopCaps(uiString(R.string.broop_body_saved_c0ae8f6))
                    BroopMindEngine.Form.entries.forEach { form -> BroopBodyValue(broopMindFormTitle(form), "${saved?.get(form)} / ${form.maximum}") }
                    if ((saved?.get(BroopMindEngine.Form.GAD2) ?: 0) >= 3 || (saved?.get(BroopMindEngine.Form.PHQ2) ?: 0) >= 3)
                        Text(uiString(R.string.broop_body_some_answers_were_in_the_range_where_talking__3a2ef28), style = BroopType.body, color = BroopPalette.textBody)
                }
                BroopBodyButton(uiString(R.string.cycle_tracker_done), onClick = onClose)
            } else {
                Text(uiString(R.string.broop_body_there_are_no_right_answers_complete_all_eight_00d43b6), style = BroopType.body, color = BroopPalette.textBody)
                broopMindQuestions.forEachIndexed { index, question ->
                    BroopCard {
                        Text(question, style = BroopType.demi, color = BroopPalette.textPrimary)
                        val options = if (index < 4) listOf(uiString(R.string.push_never), uiString(R.string.broop_body_almost_never_3d44633), uiString(R.string.broop_body_sometimes_1bc4d66), uiString(R.string.broop_body_fairly_often_2d2ee46), uiString(R.string.broop_body_very_often_ddf2028))
                            else listOf(uiString(R.string.broop_body_not_at_all_35b42ab), uiString(R.string.broop_body_several_days_0ba6cf5), uiString(R.string.broop_body_more_than_half_the_days_3e1feec), uiString(R.string.broop_body_nearly_every_day_6b4ee33))
                        options.forEachIndexed { value, title ->
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                                RadioButton(selected = answers[index] == value, enabled = !saving,
                                    onClick = { answers = answers.toMutableList().also { it[index] = value } })
                                Text(title, style = BroopType.body, color = BroopPalette.textBody)
                            }
                        }
                    }
                }
                if (error) Text(uiString(R.string.broop_body_your_check_in_was_not_saved_your_answers_are__b996f2d), style = BroopType.body, color = BroopPalette.warning)
                BroopBodyButton(if (saving) uiString(R.string.broop_body_saving_56a2285) else uiString(R.string.broop_body_save_check_in_6dfe99e), !saving && totals.values.all { it != null }) {
                    saving = true; error = false
                    scope.launch {
                        try {
                            withContext(Dispatchers.IO) {
                                vm.repo.upsertMetricSeries(totals.map { (form, total) -> MetricSeriesRow("noop-mind", LocalDate.now().toString(), form.key, requireNotNull(total).toDouble()) })
                            }
                            saved = totals.mapValues { requireNotNull(it.value) }; onSaved()
                        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                        catch (_: Exception) { error = true }
                        finally { saving = false }
                    }
                }
                Text(uiString(R.string.broop_body_pss_4_cohen_1983_gad_2_and_phq_2_kroenke_2003_d7d172d), style = BroopType.caption, color = BroopPalette.textSecondary)
            }
        }
    }
}

private fun broopMindTrend(trend: BroopMindEngine.Trend?): String = when (trend) {
    BroopMindEngine.Trend.IMPROVING -> uiString(R.string.broop_body_improving_over_the_last_week_ef9cb8e)
    BroopMindEngine.Trend.WORSENING -> uiString(R.string.broop_body_worsening_over_the_last_week_fb3eb09)
    BroopMindEngine.Trend.STEADY -> uiString(R.string.broop_body_steady_over_the_last_week_50060e4)
    null -> uiString(R.string.broop_body_building_weekly_history_8c4b783)
}

internal fun broopMindLevel(level: String): String = uiString(when (level) {
    "Limited" -> R.string.broop_body_level_limited
    "Adequate" -> R.string.broop_body_level_adequate
    "Solid" -> R.string.broop_body_level_solid
    "Strong" -> R.string.broop_body_level_strong
    "Exceptional" -> R.string.broop_body_level_exceptional
    "Moderate" -> R.string.broop_body_level_moderate
    "Elevated" -> R.string.broop_body_level_elevated
    "High" -> R.string.broop_body_high_b1a5954
    else -> R.string.hrv_status_low
})

private fun broopMindFormTitle(form: BroopMindEngine.Form): String = uiString(when (form) {
    BroopMindEngine.Form.PSS4 -> R.string.broop_body_form_stress
    BroopMindEngine.Form.GAD2 -> R.string.broop_body_form_worry
    BroopMindEngine.Form.PHQ2 -> R.string.broop_body_form_mood
})
