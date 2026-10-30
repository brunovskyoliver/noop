package com.noop.ui

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.noop.R
import com.noop.analytics.SleepEditGuard
import com.noop.data.SleepSession
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.launch

internal fun broopSleepNightIndex(groups: List<List<SleepSession>>, day: String): Int? =
    groups.indexOfFirst { blocks -> blocks.any { localDayString(it.endTs) == day } }.takeIf { it >= 0 }

/** Delete the same bridged group the main-night editor displays; a nap remains its own session. */
internal fun broopSleepDeleteGroup(night: HeroNight, selected: SleepSession): List<SleepSession> =
    if (selected.deviceId == night.session.deviceId && selected.startTs == night.session.startTs)
        night.heroGroup.ifEmpty { listOf(selected) } else listOf(selected)

internal data class BroopSleepEdit(val start: Long, val end: Long, val session: SleepSession? = null, val nap: Boolean = false)

/** Date-first endpoint editing, one validated save, and a recorded-coverage confirmation for corrections. */
@Composable
internal fun BroopOverviewSleepEditor(
    edit: BroopSleepEdit, onDismiss: () -> Unit, onSave: suspend (Long, Long) -> Unit,
    onDelete: (suspend () -> Unit)? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var draft by remember(edit) { mutableStateOf(SleepTimeEditDraft(edit.start, edit.end)) }
    var busy by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDisjoint by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val now = System.currentTimeMillis() / 1000
    val valid = draft.validatedWindow(now)
    val zone = ZoneId.systemDefault()
    val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
    fun choose(bed: Boolean) {
        val value = if (bed) draft.startTs else draft.endTs
        val local = Instant.ofEpochSecond(value).atZone(zone)
        DatePickerDialog(context, { _, year, month, day ->
            TimePickerDialog(context, { _, hour, minute ->
                val selected = sleepEndpointTs(value, year, month, day, hour, minute)
                draft = if (bed) draft.copy(startTs = selected) else draft.withWakeCandidate(selected)
            }, local.hour, local.minute, ClockPrefs.uses24Hour(context)).show()
        }, local.year, local.monthValue - 1, local.dayOfMonth).apply {
            datePicker.maxDate = System.currentTimeMillis()
        }.show()
    }
    fun save() {
        val window = valid ?: return
        busy = true
        scope.launch {
            try { onSave(window.first, window.second); onDismiss() }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { failed = true; busy = false }
        }
    }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() }, containerColor = BroopPalette.card,
        titleContentColor = BroopPalette.textPrimary, textContentColor = BroopPalette.textBody,
        title = { Text(stringResource(if (edit.session != null) R.string.l10n_sleep_screen_adjust_sleep_times_1e325561
            else if (edit.nap) R.string.l10n_sleep_screen_add_a_nap_a1b3204f else R.string.broop_overview_add_sleep)) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            TextButton(onClick = { choose(true) }, enabled = !busy) { Column {
                BroopCaps(stringResource(R.string.l10n_sleep_screen_asleep_b9692bbe))
                Text(Instant.ofEpochSecond(draft.startTs).atZone(zone).format(dateTime), color = BroopPalette.textPrimary)
            } }
            TextButton(onClick = { choose(false) }, enabled = !busy) { Column {
                BroopCaps(stringResource(R.string.l10n_sleep_screen_woke_cfbb59a8))
                Text(Instant.ofEpochSecond(draft.endTs).atZone(zone).format(dateTime), color = BroopPalette.textPrimary)
            } }
            if (valid == null) Text(stringResource(R.string.broop_overview_invalid_sleep_window), color = BroopPalette.warning)
            if (failed) Text(stringResource(R.string.broop_overview_sleep_save_failed), color = BroopPalette.warning)
            if (onDelete != null) TextButton(onClick = { confirmDelete = true }, enabled = !busy) {
                Text(stringResource(R.string.l10n_sleep_screen_delete_this_sleep_session_6932e931), color = BroopPalette.bandLow)
            }
        } },
        confirmButton = { TextButton(onClick = {
            val session = edit.session
            if (session != null && valid != null && SleepEditGuard.isDisjoint(valid.first, valid.second,
                    minOf(session.startTs, session.effectiveStartTs), session.endTs)) confirmDisjoint = true else save()
        }, enabled = valid != null && !busy) { Text(stringResource(R.string.l10n_sleep_screen_save_efc007a3), color = BroopPalette.textPrimary) } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text(stringResource(R.string.l10n_sleep_screen_cancel_77dfd213), color = BroopPalette.textSecondary) } },
    )
    if (confirmDelete || confirmDisjoint) AlertDialog(
        onDismissRequest = { confirmDelete = false; confirmDisjoint = false }, containerColor = BroopPalette.card,
        title = { Text(stringResource(if (confirmDelete) R.string.l10n_sleep_screen_delete_this_sleep_session_c347b909 else R.string.broop_overview_outside_coverage), color = BroopPalette.textPrimary) },
        text = { Text(stringResource(if (confirmDelete) R.string.sleep_delete_recorded_body else R.string.broop_overview_outside_coverage_detail), color = BroopPalette.textBody) },
        confirmButton = { TextButton(onClick = {
            if (confirmDelete) {
                confirmDelete = false; busy = true
                scope.launch {
                    try { onDelete?.invoke(); onDismiss() }
                    catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                    catch (_: Exception) { failed = true; busy = false }
                }
            } else { confirmDisjoint = false; save() }
        }) { Text(stringResource(if (confirmDelete) R.string.l10n_sleep_screen_delete_f6fdbe48 else R.string.l10n_sleep_screen_save_efc007a3), color = BroopPalette.textPrimary) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false; confirmDisjoint = false }) { Text(stringResource(R.string.l10n_sleep_screen_cancel_77dfd213)) } },
    )
}
