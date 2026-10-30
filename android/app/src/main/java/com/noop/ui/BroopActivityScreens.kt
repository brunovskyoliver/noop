package com.noop.ui

import com.noop.R

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

/** Activity tools and the local workout log use the same destinations as the existing Android app. */
@Composable
fun BroopActivityScreen(vm: AppViewModel, onNavigate: (String) -> Unit, onBack: (() -> Unit)? = null) {
    val workouts by vm.workouts.collectAsStateWithLifecycle()
    val active by vm.activeWorkout.collectAsStateWithLifecycle()
    val days by vm.recentDays.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.loadWorkouts() }
    val weekStart = java.time.LocalDate.now().minusDays(6).atStartOfDay(ZoneId.systemDefault()).toEpochSecond()
    val week = workouts.filter { it.startTs >= weekStart }
    BroopPage(uiString(R.string.today_workouts_activity), onBack) {
        active?.let { workout ->
            BroopCard(onClick = { vm.openActiveWorkout(); onNavigate("live") }) {
                BroopCaps(uiString(R.string.broop_body_activity_running_5990da9), BroopPalette.connected)
                Text(workout.sport.name, style = BroopType.section, color = BroopPalette.textPrimary)
                Text(uiString(R.string.broop_body_open_your_session_to_pause_finish_or_review_l_d69c82a), style = BroopType.body, color = BroopPalette.textBody)
            }
        }
        if (active != null) BroopActivityStrainCoach(vm)
        BroopRow(uiString(R.string.broop_body_start_activity_e91aaca), uiString(R.string.broop_body_record_heart_rate_and_your_workout_9943ec7), Icons.Filled.Add) { onNavigate("live") }
        BroopRow(uiString(R.string.broop_body_activities_e58f7f8), uiString(R.string.broop_body_add_edit_search_and_review_your_sessions_bd4c643), Icons.Filled.FitnessCenter) { onNavigate("workouts") }
        BroopRow(uiString(R.string.broop_body_strength_trainer_be7a1d4), uiString(R.string.broop_body_programs_sets_and_your_progress_defc9a8), Icons.Filled.FitnessCenter) { onNavigate("lift_log") }
        BroopSection(uiString(R.string.trends_this_week))
        BroopCard {
            BroopBodyValue(uiString(R.string.l10n_insights_screen_sessions_e11e37a9), week.size.toString())
            BroopBodyValue(uiString(R.string.broop_body_active_time_e3be4b7), "${(week.sumOf { it.durationS ?: (it.endTs - it.startTs).toDouble() } / 60).roundToInt()} min")
            val energy = week.mapNotNull { it.energyKcal }
            if (energy.isNotEmpty()) BroopBodyValue(uiString(R.string.broop_body_recorded_activity_calories_03f403f), uiString(R.string.broop_body_1_s_kcal_0884119, (energy.sum().roundToInt()).toString()))
            val effort = days.lastOrNull()?.strain
            BroopBodyValue(uiString(R.string.broop_body_latest_daily_effort_85c99e9), effort?.let { "${it.roundToInt()} / 100" } ?: "--")
        }
        BroopSection(uiString(R.string.broop_body_tools_4fa8cc8))
        BroopRow(uiString(R.string.broop_body_live_heart_rate_1359395), uiString(R.string.broop_body_heart_rate_zones_and_your_current_session_24e83f4), Icons.Filled.FavoriteBorder) { onNavigate("live") }
        BroopRow(uiString(R.string.l10n_breathe_screen_breathe_282be568), uiString(R.string.broop_body_guided_breathing_sessions_da4df0a), Icons.Filled.Air) { onNavigate("breathe") }
        BroopRow(uiString(R.string.nav_intervals), uiString(R.string.broop_body_build_and_run_an_interval_session_5b078da), Icons.Filled.Timer) { onNavigate("intervals") }
        BroopSection(uiString(R.string.broop_body_recent_sessions_3a63bf6))
        if (workouts.isEmpty()) BroopEmpty(uiString(R.string.broop_body_your_activity_starts_here_eaae7f2), uiString(R.string.broop_body_start_a_session_or_add_an_activity_to_build_y_1c2903d))
        workouts.sortedByDescending { it.startTs }.take(8).forEach { workout ->
            val date = Instant.ofEpochSecond(workout.startTs).atZone(ZoneId.systemDefault())
                .format(DateTimeFormatter.ofPattern("EEE, d MMM · HH:mm", Locale.getDefault()))
            BroopRow(WorkoutEditing.displaySport(workout.sport), "$date · ${((workout.durationS ?: (workout.endTs - workout.startTs).toDouble()) / 60).roundToInt()} min",
                Icons.Filled.FitnessCenter) { onNavigate("workouts") }
        }
    }
}
