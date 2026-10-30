package com.noop.ui

import com.noop.R

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.noop.analytics.CircadianEngine
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Saved sleep timing and origin clock, matching Strand/Data/JetLagTrip.swift. */
internal data class BroopJetLagTrip(val travelDate: LocalDate, val originTimeZone: String,
    val destinationOffsetMinutes: Int, val bedMinute: Int, val wakeMinute: Int) {
    data class Day(val date: LocalDate, val timing: CircadianEngine.DayPlan)
    data class Plan(val direction: CircadianEngine.ShiftDirection, val days: List<Day>)
    fun resolve(): Plan? {
        val zone = runCatching { ZoneId.of(originTimeZone) }.getOrNull() ?: return null
        if (destinationOffsetMinutes !in -720..840 || bedMinute !in 0..1439 || wakeMinute !in 0..1439) return null
        val departure = travelDate.atStartOfDay(zone)
        val shift = (destinationOffsetMinutes * 60 - departure.offset.totalSeconds) / 3600.0
        if (abs(shift) > 12) return null
        val plan = CircadianEngine.planShift(shift, bedMinute / 60.0, wakeMinute / 60.0)
        return Plan(plan.direction, plan.days.map { day -> Day(travelDate.plusDays((day.dayIndex - plan.estimatedDays - 1).toLong()), day) })
    }
    fun encode(): String = JSONObject().put("travelDate", travelDate.toString()).put("originTimeZone", originTimeZone)
        .put("destinationOffsetMinutes", destinationOffsetMinutes).put("bedMinute", bedMinute).put("wakeMinute", wakeMinute).toString()
    companion object {
        const val preferenceKey = "broop.jetLag.activeTrip.v1"
        fun decode(raw: String): BroopJetLagTrip? = runCatching {
            val json = JSONObject(raw)
            BroopJetLagTrip(LocalDate.parse(json.getString("travelDate")), json.getString("originTimeZone"),
                json.getInt("destinationOffsetMinutes"), json.getInt("bedMinute"), json.getInt("wakeMinute"))
        }.getOrNull()
    }
}

@Composable
fun BroopJetLagScreen(vm: AppViewModel, onBack: (() -> Unit)? = null) {
    val context = LocalContext.current
    val prefs = remember(context) { NoopPrefs.of(context.applicationContext) }
    val sleep by vm.tonightPlan.collectAsStateWithLifecycle()
    var trip by remember { mutableStateOf(BroopJetLagTrip.decode(prefs.getString(BroopJetLagTrip.preferenceKey, "") ?: "")) }
    var date by remember { mutableStateOf(trip?.travelDate ?: LocalDate.now()) }
    var destination by remember { mutableStateOf(trip?.destinationOffsetMinutes ?: 0) }
    var offsets by remember { mutableStateOf(false) }
    LaunchedEffect(vm) { if (vm.tonightPlan.value == null) vm.refreshTonightPlan() }
    val matches = trip?.let { it.travelDate == date && it.destinationOffsetMinutes == destination } == true
    val plan = remember(trip) { trip?.resolve() }
    BroopPage(uiString(R.string.broop_body_jet_lag_planner_eb451ff), onBack) {
        BroopCard {
            BroopCaps(uiString(R.string.broop_body_travel_date_5e1827a))
            BroopBodyButton(date.format(DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.getDefault()))) {
                DatePickerDialog(context, { _, year, month, day -> date = LocalDate.of(year, month + 1, day) }, date.year, date.monthValue - 1, date.dayOfMonth).show()
            }
            BroopCaps(uiString(R.string.broop_body_destination_utc_offset_91949ac))
            TextButton(onClick = { offsets = true }) { Text(broopOffsetLabel(destination), style = BroopType.demi, color = BroopPalette.textPrimary) }
            DropdownMenu(expanded = offsets, onDismissRequest = { offsets = false }) {
                (-720..840 step 15).forEach { minute -> DropdownMenuItem(text = { Text(broopOffsetLabel(minute)) },
                    onClick = { destination = minute; offsets = false }) }
            }
            Text(uiString(R.string.broop_body_use_the_destination_s_utc_offset_on_your_trav_273ad19), style = BroopType.body, color = BroopPalette.textBody)
            val saved = trip
            val bed = if (matches) saved?.bedMinute else sleep?.target?.bedMinute
            val wake = if (matches) saved?.wakeMinute else sleep?.wakeMinute
            if (bed != null && wake != null) BroopBodyValue(uiString(R.string.broop_body_sleep_plan_starting_window_ceba37c), "${broopClock(bed / 60.0)} – ${broopClock(wake / 60.0)}")
            BroopBodyButton(uiString(R.string.broop_body_save_trip_4684b89), sleep != null) {
                sleep?.let { tonight ->
                    val next = BroopJetLagTrip(date, ZoneId.systemDefault().id, destination, tonight.target.bedMinute, tonight.wakeMinute)
                    prefs.edit().putString(BroopJetLagTrip.preferenceKey, next.encode()).apply()
                    trip = next
                }
            }
            if (sleep == null) Text(uiString(R.string.broop_body_a_sleep_plan_is_needed_before_saving_a_trip_k_35d4281), style = BroopType.caption, color = BroopPalette.textSecondary)
        }
        if (trip != null && matches) {
            Text(uiString(R.string.broop_body_before_travel_all_times_use_the_origin_clock__715522c, (trip?.originTimeZone).toString()), style = BroopType.body, color = BroopPalette.textBody)
            if (plan == null) BroopEmpty(uiString(R.string.broop_body_no_plan_available_fff0e46), uiString(R.string.broop_body_this_simple_planner_supports_time_differences_69b2907))
            else if (plan.days.isEmpty()) BroopEmpty(uiString(R.string.broop_body_already_aligned_f48e9f0), uiString(R.string.broop_body_no_meaningful_time_shift_is_needed_for_this_t_ac2513c))
            else plan.days.forEach { day ->
                BroopCard {
                    BroopCaps(day.date.format(DateTimeFormatter.ofPattern("EEE, d MMM", Locale.getDefault())))
                    BroopBodyValue(uiString(R.string.broop_body_sleep_wake_c15e119), "${broopClock(day.timing.targetSleepHour)} / ${broopClock(day.timing.targetWakeHour)}")
                    BroopBodyValue(uiString(R.string.broop_body_seek_bright_light_d9d3331), "${broopClock(day.timing.brightLightStartHour)} – ${broopClock(day.timing.brightLightEndHour)}")
                    BroopBodyValue(if (plan.direction == CircadianEngine.ShiftDirection.ADVANCE) uiString(R.string.broop_body_keep_evening_dim_from_6bd66ed) else uiString(R.string.broop_body_avoid_bright_morning_light_from_82d7966), broopClock(day.timing.dimFromHour))
                }
            }
            BroopBodyButton(uiString(R.string.broop_body_clear_trip_2a57665)) { prefs.edit().remove(BroopJetLagTrip.preferenceKey).apply(); trip = null }
        }
        BroopSection(uiString(R.string.broop_body_how_it_works_1dd6a17))
        BroopCard {
            Text(uiString(R.string.broop_body_moves_your_saved_sleep_plan_window_by_up_to_o_9cc49b2), style = BroopType.body, color = BroopPalette.textBody)
            Text(uiString(R.string.broop_body_dates_and_times_use_the_origin_clock_this_gui_395dac3), style = BroopType.caption, color = BroopPalette.textSecondary)
        }
    }
}

internal fun broopClock(hour: Double): String {
    val minutes = ((hour * 60).roundToInt() % 1440 + 1440) % 1440
    return String.format(Locale.US, "%02d:%02d", minutes / 60, minutes % 60)
}

private fun broopOffsetLabel(minute: Int): String = String.format(Locale.US, "UTC%s%02d:%02d", if (minute < 0) "−" else "+", abs(minute) / 60, abs(minute) % 60)
