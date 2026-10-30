package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.*
import com.noop.data.LiftMuscle
import com.noop.data.LiftSessionRow
import com.noop.data.LiftSetEntity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private fun liftClock(seconds: Long) = maxOf(0L, seconds).let { "${it / 60}:${(it % 60).toString().padStart(2, '0')}" }

@Composable
internal fun BroopLiftMiniBar(vm: AppViewModel, onClick: () -> Unit) {
    val controller = vm.broopLift
    val engine = controller.engine ?: return
    if (!controller.isActive || controller.isPresented) return
    var now by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(engine.stage, controller.revision) { while (true) { now = System.currentTimeMillis() / 1000; delay(1000) } }
    val slot = engine.currentSlot ?: engine.nextPendingSlot
    BroopCard(onClick = onClick) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                BroopCaps(stringResource(if (engine.stage is LiftSessionEngine.Stage.Resting) R.string.broop_lift_resting else R.string.today_live_session_running))
                Text(slot?.let { engine.item(it)?.exercise } ?: controller.session?.programName ?: stringResource(R.string.broop_body_free_session_88633a3), style = BroopType.demi, color = BroopPalette.textPrimary)
                Text(liftClock(engine.restRemaining(now) ?: (now - engine.stageStartedAt)), style = BroopType.number, color = BroopPalette.teal)
            }
            TextButton(onClick = { controller.advance() }, enabled = !controller.saving && !engine.allCompleted) {
                Text(stringResource(if (engine.stage is LiftSessionEngine.Stage.Working) R.string.broop_body_complete_set_2c711f0 else R.string.broop_body_start_set_c818c49))
            }
        }
    }
}

@Composable
internal fun BroopLiftActiveSessionView(vm: AppViewModel, store: BroopLiftStore, session: LiftSessionRow,
    recorded: List<LiftSetEntity>, onClose: () -> Unit, onChanged: () -> Unit) {
    val controller = vm.broopLift
    DisposableEffect(controller) {
        controller.isPresented = true; vm.requestRealtimeHr()
        onDispose { controller.isPresented = false; vm.releaseRealtimeHr() }
    }
    var error by remember { mutableStateOf<String?>(null) }
    var adding by remember { mutableStateOf(false) }
    var finish by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<LiftSlot?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    val live by vm.live.collectAsStateWithLifecycle()
    LaunchedEffect(session.id) {
        try { controller.attach(session, session.programId?.let { store.items(it) }.orEmpty(), store.exercises(), recorded) }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = uiString(R.string.broop_body_the_strength_log_could_not_be_read_please_try_c258dbd) }
        while (true) { now = System.currentTimeMillis() / 1000; delay(1000) }
    }
    val engine = controller.engine
    Dialog(onDismissRequest = { if (!controller.saving) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(session.programName ?: stringResource(R.string.broop_body_free_session_88633a3), onClose) {
            if (engine != null && controller.session?.id == session.id) {
                BroopCard {
                    val stageLabel = when (engine.stage) {
                        LiftSessionEngine.Stage.Warmup -> R.string.broop_body_warm_up_47148ff
                        is LiftSessionEngine.Stage.Working -> R.string.broop_body_set_in_progress_abcce63
                        is LiftSessionEngine.Stage.Resting -> if ((engine.restRemaining(now) ?: 0) == 0L) R.string.broop_lift_rest_ready else R.string.broop_lift_resting
                        LiftSessionEngine.Stage.Finished -> R.string.broop_body_saving_56a2285
                    }
                    BroopCaps(stringResource(stageLabel))
                    Text(liftClock(engine.restRemaining(now) ?: (now - engine.stageStartedAt)), style = BroopType.largeNumber, color = BroopPalette.teal)
                    engine.currentSlot?.let { slot -> Text(stringResource(R.string.broop_lift_slot_name, engine.item(slot)?.exercise.orEmpty(), slot.setIndex), style = BroopType.section, color = BroopPalette.textPrimary) }
                    BroopBodyValue(stringResource(R.string.broop_body_duration_1370004), liftClock(now - session.startTs))
                    BroopBodyValue(stringResource(R.string.broop_body_sets_logged_e642d28), "${engine.sets.size} / ${engine.allSlots.size}")
                    live.heartRate?.let { BroopBodyValue(stringResource(R.string.l10n_breathe_screen_heart_rate_410aa15c), it.toString()) }
                    engine.upcomingSlot?.let { slot -> Text(stringResource(R.string.broop_lift_next_slot, engine.item(slot)?.exercise.orEmpty(), slot.setIndex), style = BroopType.body, color = BroopPalette.textBody) }
                    Row(horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                        TextButton(onClick = controller::undo, enabled = engine.canUndo && !controller.saving) { Text(stringResource(R.string.broop_lift_undo)) }
                        TextButton(onClick = { finish = true }, enabled = !controller.saving) { Text(stringResource(R.string.broop_body_finish_session_5fe14d3)) }
                    }
                    if (!engine.allCompleted || engine.stage is LiftSessionEngine.Stage.Working) BroopBodyButton(
                        stringResource(if (engine.stage is LiftSessionEngine.Stage.Working) R.string.broop_body_complete_set_2c711f0 else R.string.broop_body_start_set_c818c49), !controller.saving) { controller.advance() }
                }
                BroopSection(stringResource(R.string.broop_lift_exercises))
                engine.plan.forEachIndexed { index, line -> BroopCard {
                    Text(line.exercise, style = BroopType.section, color = BroopPalette.textPrimary)
                    line.note?.let { Text(it, style = BroopType.caption, color = BroopPalette.textSecondary) }
                    engine.slots(index).forEach { slot ->
                        val numbers = controller.values(slot); val typed = controller.entered(slot)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = { editing = slot }, modifier = Modifier.weight(1f).testTag("broop.lift.slot.$index.${slot.setIndex}")) {
                                Text(stringResource(R.string.broop_lift_slot_numbers, slot.setIndex,
                                    (typed.weightKg ?: numbers.weightKg)?.let(::broopOne) ?: "--", (typed.reps ?: numbers.reps)?.toString() ?: "--") +
                                    if (controller.isWarmup(slot)) " · " + stringResource(R.string.broop_body_warm_up_47148ff) else "",
                                    color = if (engine.completed(slot)) BroopPalette.teal else BroopPalette.textPrimary)
                            }
                            TextButton(onClick = { if ((engine.stage as? LiftSessionEngine.Stage.Working)?.slot == slot) controller.advance() else controller.start(slot) }, enabled = !controller.saving) {
                                Text(stringResource(when {
                                    (engine.stage as? LiftSessionEngine.Stage.Working)?.slot == slot -> R.string.broop_lift_done
                                    engine.completed(slot) -> R.string.broop_lift_redo
                                    else -> R.string.ground_truth_marker_start
                                }))
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                        TextButton(onClick = { controller.addSet(index) }, enabled = line.targetSets < 20 && !controller.saving) { Text(stringResource(R.string.broop_lift_add_set)) }
                        TextButton(onClick = { controller.removeSet(index) }, enabled = engine.canRemoveSet(index) && !controller.saving) { Text(stringResource(R.string.broop_lift_remove_set)) }
                    }
                } }
                BroopBodyButton(stringResource(R.string.broop_lift_add_exercise), engine.plan.size < 200 && !controller.saving) { adding = true }
            } else Text(stringResource(R.string.broop_body_saving_56a2285), style = BroopType.body, color = BroopPalette.textBody)
            error?.let { Text(it, style = BroopType.body, color = BroopPalette.warning) }
        }
    }
    editing?.let { slot -> BroopLiftSlotEditor(controller, slot, onClose = { editing = null }) }
    if (adding) BroopLiftAddExercise(store, onClose = { adding = false }) { name, primary, secondary -> controller.addExercise(name, primary, secondary); adding = false }
    if (finish) BroopLiftFinishSheet(controller, store, onClose = { finish = false }, onSaved = { finish = false; onChanged(); onClose() })
}

@Composable
private fun BroopLiftSlotEditor(controller: BroopLiftController, slot: LiftSlot, onClose: () -> Unit) {
    val original = controller.entered(slot); val grey = controller.values(slot)
    var weight by remember(slot) { mutableStateOf(original.weightKg?.toString().orEmpty()) }
    var reps by remember(slot) { mutableStateOf(original.reps?.toString().orEmpty()) }
    var rpe by remember(slot) { mutableStateOf(original.rpe?.toString().orEmpty()) }
    var warmup by remember(slot) { mutableStateOf(controller.isWarmup(slot)) }
    val valid = (weight.isBlank() || weight.toDoubleOrNull()?.let { it.isFinite() && it >= 0 } == true) &&
        (reps.isBlank() || reps.toIntOrNull()?.let { it >= 0 } == true) && (rpe.isBlank() || rpe.toDoubleOrNull()?.let { it.isFinite() && it in 1.0..10.0 } == true)
    fun applyIfValid() { if (valid) controller.update(slot, LiftPendingValues(weight.toDoubleOrNull(), reps.toIntOrNull(), rpe.toDoubleOrNull()), warmup) }
    // Every valid edit is persisted immediately; leaving a field never discards a pending set's input.
    LaunchedEffect(weight, reps, rpe, warmup) { applyIfValid() }
    AlertDialog(onDismissRequest = onClose, title = { Text(controller.engine?.item(slot)?.exercise.orEmpty()) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            OutlinedTextField(weight, { weight = it }, label = { Text(stringResource(R.string.broop_body_weight_kg_d249832)) }, placeholder = { Text(grey.weightKg?.let(::broopOne) ?: "--") }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal))
            OutlinedTextField(reps, { reps = it }, label = { Text(stringResource(R.string.broop_body_reps_702045f)) }, placeholder = { Text(grey.reps?.toString() ?: "--") }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number))
            OutlinedTextField(rpe, { rpe = it }, label = { Text(stringResource(R.string.broop_body_rpe_1_10_optional_862f960)) }, placeholder = { Text(controller.engine?.item(slot)?.targetRpe?.let(::broopOne) ?: "--") }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal))
            Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(warmup, { warmup = it }); Text(stringResource(R.string.broop_body_warm_up_set_331fda9)) }
        }
    }, confirmButton = { TextButton(onClick = { applyIfValid(); onClose() }, enabled = valid, modifier = Modifier.testTag("broop.lift.slot.confirm")) { Text(stringResource(R.string.broop_lift_done)) } })
}

@Composable
private fun BroopLiftAddExercise(store: BroopLiftStore, onClose: () -> Unit, onAdd: (String, LiftMuscle?, List<LiftMuscle>) -> Unit) {
    var name by remember { mutableStateOf("") }; var primary by remember { mutableStateOf<LiftMuscle?>(null) }
    var secondary by remember { mutableStateOf<List<LiftMuscle>>(emptyList()) }; var picker by remember { mutableStateOf(false) }
    var secondaryPicker by remember { mutableStateOf(false) }; var known by remember { mutableStateOf<List<com.noop.data.LiftExerciseRow>>(emptyList()) }
    LaunchedEffect(store) { known = store.exercises() }
    AlertDialog(onDismissRequest = onClose, title = { Text(stringResource(R.string.broop_lift_add_exercise)) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.broop_body_exercise_20863c8)) })
            known.filter { name.isBlank() || it.name.contains(name, true) }.take(4).forEach { item -> TextButton(onClick = { name = item.name; primary = LiftMuscle.fromRaw(item.primaryMuscle); secondary = LiftMuscle.decodeList(item.secondaryMuscles) }) { Text(item.name) } }
            TextButton(onClick = { picker = true }) { Text(primary?.let(::broopMuscleName) ?: stringResource(R.string.broop_body_unassigned_e57016e)) }
            DropdownMenu(picker, { picker = false }) { LiftMuscle.entries.forEach { muscle -> DropdownMenuItem(text = { Text(broopMuscleName(muscle)) }, onClick = { primary = muscle; secondary = secondary - muscle; picker = false }) } }
            TextButton(onClick = { secondaryPicker = true }) { Text(stringResource(R.string.broop_body_secondary_muscles_1_s_f729d5e, secondary.size.toString())) }
            DropdownMenu(secondaryPicker, { secondaryPicker = false }) { LiftMuscle.entries.filter { it != primary }.forEach { muscle -> DropdownMenuItem(text = { Text((if (muscle in secondary) "✓ " else "") + broopMuscleName(muscle)) }, onClick = { secondary = if (muscle in secondary) secondary - muscle else secondary + muscle }) } }
        }
    }, confirmButton = { TextButton(onClick = { onAdd(name, primary, secondary) }, enabled = name.isNotBlank(), modifier = Modifier.testTag("broop.lift.exercise.confirm")) { Text(stringResource(R.string.broop_lift_add_exercise)) } }, dismissButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.ground_truth_cancel)) } })
}

@Composable
private fun BroopLiftFinishSheet(controller: BroopLiftController, store: BroopLiftStore, onClose: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope(); val engine = controller.engine ?: return
    var complete by remember { mutableStateOf<Boolean?>(null) }; var update by remember { mutableStateOf<Boolean?>(null) }
    var rpe by remember { mutableStateOf("") }; var note by remember { mutableStateOf(controller.session?.note.orEmpty()) }
    var changes by remember { mutableStateOf<List<LiftSetCountChange>>(emptyList()) }; var loaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }; var discard by remember { mutableStateOf(false) }
    LaunchedEffect(controller.session?.id, engine.plan) {
        try { changes = controller.session?.programId?.let { LiftSessionFinish.changes(engine.plan, store.items(it)) }.orEmpty(); loaded = true }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = uiString(R.string.broop_body_the_strength_log_could_not_be_read_please_try_c258dbd) }
    }
    val asksProgram = controller.session?.programId != null && (changes.isNotEmpty() || engine.plan.any { it.addedInSession })
    val answered = (engine.unperformedSlots.isEmpty() || complete != null) && (!asksProgram || update != null)
    Dialog(onDismissRequest = { if (!controller.saving) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(stringResource(R.string.broop_body_finish_session_5fe14d3), onClose) {
            BroopCard {
                BroopLiftNumberField(stringResource(R.string.broop_body_session_rpe_1_10_optional_8e9effb), rpe) { rpe = it }
                OutlinedTextField(note, { note = it }, label = { Text(stringResource(R.string.broop_body_session_note_fd92224)) }, modifier = Modifier.fillMaxWidth())
            }
            if (engine.unperformedSlots.isNotEmpty()) BroopCard {
                Text(stringResource(R.string.broop_lift_unfinished, engine.unperformedSlots.size), style = BroopType.section, color = BroopPalette.textPrimary)
                BroopLiftChoice(stringResource(R.string.broop_lift_complete_unfinished), stringResource(R.string.broop_lift_discard_unfinished), complete) { complete = it }
                Text(stringResource(R.string.broop_lift_unfinished_detail), style = BroopType.body, color = BroopPalette.textBody)
                if (complete == false && !LiftSessionFinish.anyPerformed(LiftSessionFinish.setsToSave(engine, controller.pending, controller.warmups, controller.last, false))) Text(stringResource(R.string.broop_lift_nothing_performed), style = BroopType.body, color = BroopPalette.warning)
            }
            if (asksProgram) BroopCard {
                Text(stringResource(R.string.broop_lift_program_question), style = BroopType.section, color = BroopPalette.textPrimary)
                changes.forEach { Text(stringResource(R.string.broop_lift_count_change, it.exercise, it.from, it.to), style = BroopType.body, color = BroopPalette.textBody) }
                engine.plan.filter { it.addedInSession }.forEach { Text(stringResource(R.string.broop_lift_new_line, it.exercise, it.targetSets), style = BroopType.body, color = BroopPalette.textBody) }
                BroopLiftChoice(stringResource(R.string.broop_lift_update_program), stringResource(R.string.broop_lift_keep_program), update) { update = it }
            }
            BroopBodyButton(stringResource(R.string.broop_body_save_session_8c7478c), loaded && answered && !controller.saving &&
                (rpe.isBlank() || rpe.toDoubleOrNull()?.let { it.isFinite() && it in 1.0..10.0 } == true)) {
                scope.launch { try { controller.save(complete == true, update == true, rpe.toDoubleOrNull(), note.ifBlank { null }); onSaved() }
                    catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                    catch (_: Exception) { error = uiString(R.string.broop_body_the_session_could_not_be_finished_your_sets_a_5674aeb) } }
            }
            BroopBodyButton(stringResource(R.string.broop_lift_discard_session), !controller.saving) { discard = true }
            error?.let { Text(it, style = BroopType.body, color = BroopPalette.warning) }
        }
    }
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text(stringResource(R.string.broop_lift_discard_session)) }, text = { Text(stringResource(R.string.broop_lift_discard_session_detail, engine.sets.size)) }, confirmButton = {
        TextButton(onClick = { scope.launch { try { controller.discard(); onSaved() } catch (_: Exception) { error = uiString(R.string.broop_body_the_session_could_not_be_finished_your_sets_a_5674aeb) } } }) { Text(stringResource(R.string.broop_lift_discard_unfinished)) }
    }, dismissButton = { TextButton(onClick = { discard = false }) { Text(stringResource(R.string.ground_truth_cancel)) } })
}

@Composable
private fun BroopLiftChoice(yes: String, no: String, value: Boolean?, onChange: (Boolean) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        TextButton(onClick = { onChange(true) }) { Text(yes, color = if (value == true) BroopPalette.teal else BroopPalette.textBody) }
        TextButton(onClick = { onChange(false) }) { Text(no, color = if (value == false) BroopPalette.teal else BroopPalette.textBody) }
    }
}
