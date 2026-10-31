package com.noop.ui

import com.noop.R

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.sqlite.db.SupportSQLiteDatabase
import com.noop.analytics.LiftMetrics
import com.noop.data.LiftExerciseRow
import com.noop.data.LiftMuscle
import com.noop.data.LiftProgramItemRow
import com.noop.data.LiftProgramRow
import com.noop.data.LiftSessionRow
import com.noop.data.LiftSetEntity
import com.noop.data.WhoopDatabase
import com.noop.data.WorkoutRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/** Store adapter over the existing cross-platform lift tables; no migration or alternate format. */
internal class BroopLiftStore(private val room: WhoopDatabase, private val deviceId: String) {
    constructor(context: Context, deviceId: String) : this(WhoopDatabase.get(context.applicationContext), deviceId)
    private val db: SupportSQLiteDatabase get() = room.openHelper.writableDatabase
    private fun id(): String = UUID.randomUUID().toString()
    private fun now(): Long = System.currentTimeMillis() / 1000
    private fun Cursor.text(key: String): String? = getColumnIndexOrThrow(key).let { if (isNull(it)) null else getString(it) }
    private fun Cursor.long(key: String): Long? = getColumnIndexOrThrow(key).let { if (isNull(it)) null else getLong(it) }
    private fun Cursor.double(key: String): Double? = getColumnIndexOrThrow(key).let { if (isNull(it)) null else getDouble(it) }
    private fun insert(table: String, values: ContentValues) { db.insert(table, SQLiteDatabase.CONFLICT_REPLACE, values) }
    private inline fun <T> query(sql: String, args: Array<out Any?>, row: (Cursor) -> T): List<T> =
        db.query(sql, args).use { cursor -> buildList { while (cursor.moveToNext()) add(row(cursor)) } }
    private inline fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        try { val value = block(); db.setTransactionSuccessful(); return value } finally { db.endTransaction() }
    }
    suspend fun programs(): List<LiftProgramRow> = withContext(Dispatchers.IO) {
        query("SELECT * FROM liftProgram WHERE deviceId = ? AND archived = 0 ORDER BY updatedAt DESC", arrayOf(deviceId)) {
            LiftProgramRow(it.text("id")!!, deviceId, it.text("name")!!, it.text("note"), it.long("createdAt")!!, it.long("updatedAt")!!)
        }
    }
    suspend fun exercises(): List<LiftExerciseRow> = withContext(Dispatchers.IO) {
        query("SELECT * FROM liftExercise WHERE deviceId = ? ORDER BY lastUsedTs DESC,name", arrayOf(deviceId)) {
            LiftExerciseRow(it.text("id")!!, deviceId, it.text("name")!!, it.text("primaryMuscle"), it.text("secondaryMuscles"),
                it.long("createdAt")!!, it.long("lastUsedTs"))
        }
    }
    suspend fun items(programId: String): List<LiftProgramItemRow> = withContext(Dispatchers.IO) {
        query("SELECT * FROM liftProgramItem WHERE deviceId = ? AND programId = ? ORDER BY ord", arrayOf(deviceId, programId)) {
            LiftProgramItemRow(it.text("id")!!, deviceId, programId, it.long("ord")!!.toInt(), it.text("exercise")!!,
                it.long("targetSets")?.toInt(), it.long("targetRepsLow")?.toInt(), it.long("targetRepsHigh")?.toInt(),
                it.double("targetRpe"), it.double("targetWeightKg"), it.long("restSec")?.toInt(), it.text("note"))
        }
    }
    suspend fun saveProgram(existing: LiftProgramRow?, name: String, items: List<LiftProgramItemRow>, note: String? = existing?.note): String = withContext(Dispatchers.IO) {
        require(name.isNotBlank() && items.isNotEmpty() && items.all { it.exercise.isNotBlank() })
        val programId = existing?.id ?: id()
        transaction {
            insert("liftProgram", ContentValues().apply {
                put("id", programId); put("deviceId", deviceId); put("name", name.trim()); put("note", note?.take(120))
                put("createdAt", existing?.createdAt ?: now()); put("updatedAt", now()); put("archived", 0)
            })
            db.execSQL("DELETE FROM liftProgramItem WHERE deviceId = ? AND programId = ?", arrayOf(deviceId, programId))
            items.forEachIndexed { index, item -> insert("liftProgramItem", ContentValues().apply {
                put("id", item.id.ifBlank { id() }); put("deviceId", deviceId); put("programId", programId); put("ord", index)
                put("exercise", item.exercise.trim()); put("targetSets", item.targetSets); put("targetRepsLow", item.targetRepsLow)
                put("targetRepsHigh", item.targetRepsHigh); put("targetRpe", item.targetRpe); put("targetWeightKg", item.targetWeightKg)
                put("restSec", item.restSec); put("note", item.note)
            }) }
        }
        programId
    }
    suspend fun sessions(): List<LiftSessionRow> = withContext(Dispatchers.IO) {
        query("SELECT * FROM liftSession WHERE deviceId = ? ORDER BY startTs DESC LIMIT 100", arrayOf(deviceId)) {
            LiftSessionRow(it.text("id")!!, deviceId, it.long("startTs")!!, it.long("endTs"), it.text("sport")!!,
                it.text("programId"), it.text("programName"), it.double("sessionRpe"), it.text("note"))
        }
    }
    suspend fun start(program: LiftProgramRow?): Unit = withContext(Dispatchers.IO) {
        check(sessions().none { it.endTs == null })
        insert("liftSession", ContentValues().apply {
            put("id", id()); put("deviceId", deviceId); put("startTs", now()); put("sport", "strength")
            put("programId", program?.id); put("programName", program?.name)
        })
    }
    suspend fun sets(sessionId: String): List<LiftSetEntity> = withContext(Dispatchers.IO) {
        query("SELECT * FROM liftSet WHERE deviceId = ? AND sessionId = ? ORDER BY ord", arrayOf(deviceId, sessionId)) {
            LiftSetEntity(it.text("id")!!, deviceId, sessionId, it.long("ord")!!.toInt(), it.text("exercise")!!,
                it.text("primaryMuscle"), it.text("secondaryMuscles"), it.long("setIndex")!!.toInt(), it.double("weightKg"),
                it.long("reps")?.toInt(), it.double("rpe"), it.long("isWarmup") == 1L, it.long("startTs"), it.long("endTs"),
                it.long("restSec")?.toInt(), it.text("note"))
        }
    }
    /** Swift twin `WhoopStore.lastLiftSets(deviceId:exercise:before:)`; zero-rep rows never become carried targets. */
    suspend fun lastLiftValues(exercise: String, before: Long): Map<Int, com.noop.analytics.LiftSetCarry> = withContext(Dispatchers.IO) {
        val previous = query("SELECT s.sessionId FROM liftSet s JOIN liftSession sess ON sess.id = s.sessionId " +
            "WHERE s.deviceId = ? AND s.exercise = ? AND sess.startTs < ? AND (s.reps IS NULL OR s.reps <> 0) " +
            "ORDER BY sess.startTs DESC LIMIT 1", arrayOf(deviceId, exercise, before)) { it.text("sessionId")!! }.firstOrNull()
        if (previous == null) emptyMap() else sets(previous).filter { it.exercise == exercise && LiftMetrics.isPerformed(it.reps) }
            .associate { it.setIndex to com.noop.analytics.LiftSetCarry(it.weightKg, it.reps) }
    }
    suspend fun logSet(session: LiftSessionRow, exercise: String, weight: Double?, reps: Int?, rpe: Double?, warmup: Boolean,
        primary: LiftMuscle?, secondary: List<LiftMuscle>, startedAt: Long?) = withContext(Dispatchers.IO) {
        require(exercise.isNotBlank() && (weight == null || weight.isFinite() && weight >= 0) &&
            (reps == null || reps >= 0) && (rpe == null || rpe.isFinite() && rpe in 1.0..10.0))
        check(session.endTs == null)
        val rows = sets(session.id)
        val stamp = now(); val cleanName = exercise.trim()
        transaction {
            // Measure the preceding rest from the last completion tap; never substitute planned rest.
            rows.lastOrNull()?.let { previous -> previous.endTs?.let { end ->
                startedAt?.let { start -> db.execSQL("UPDATE liftSet SET restSec = ? WHERE id = ?", arrayOf(maxOf(0L, start - end), previous.id)) }
            } }
            insert("liftSet", ContentValues().apply {
                put("id", id()); put("deviceId", deviceId); put("sessionId", session.id); put("ord", (rows.maxOfOrNull { it.ord } ?: -1) + 1)
                put("exercise", cleanName); put("primaryMuscle", primary?.name)
                put("secondaryMuscles", LiftMuscle.encodeList(secondary, primary)); put("setIndex", (rows.filter { it.exercise == cleanName }.maxOfOrNull { it.setIndex } ?: 0) + 1)
                put("weightKg", weight); put("reps", reps); put("rpe", rpe); put("isWarmup", if (warmup) 1 else 0)
                put("startTs", startedAt); put("endTs", stamp)
            })
            val known = query("SELECT id,createdAt FROM liftExercise WHERE deviceId = ? AND name = ?", arrayOf(deviceId, cleanName)) { it.text("id")!! to it.long("createdAt")!! }.firstOrNull()
            insert("liftExercise", ContentValues().apply {
                put("id", known?.first ?: id()); put("deviceId", deviceId); put("name", cleanName); put("primaryMuscle", primary?.name)
                put("secondaryMuscles", LiftMuscle.encodeList(secondary, primary)); put("createdAt", known?.second ?: stamp); put("lastUsedTs", stamp)
            })
        }
    }
    suspend fun finish(session: LiftSessionRow, sessionRpe: Double?, note: String?) = withContext(Dispatchers.IO) {
        require(sessionRpe == null || sessionRpe.isFinite() && sessionRpe in 1.0..10.0)
        val stamp = now()
        transaction {
            db.execSQL("UPDATE liftSession SET endTs = ?, sessionRpe = ?, note = ? WHERE id = ? AND deviceId = ? AND endTs IS NULL",
                arrayOf(stamp, sessionRpe, note, session.id, deviceId))
            insert("workout", ContentValues().apply {
                put("deviceId", deviceId); put("startTs", session.startTs); put("endTs", stamp); put("sport", session.sport)
                put("source", "manual"); put("durationS", (stamp - session.startTs).toDouble()); put("notes", note)
            })
        }
    }
    suspend fun commitSession(session: LiftSessionRow, engine: com.noop.analytics.LiftSessionEngine,
        sets: List<com.noop.analytics.LiftFinishedSet>, keepProgram: Boolean, rpe: Double?, note: String?) = withContext(Dispatchers.IO) {
        require(rpe == null || rpe.isFinite() && rpe in 1.0..10.0)
        val program = session.programId?.let { items(it) }
        val updated = program?.let { com.noop.analytics.LiftSessionFinish.programAfterSession(sets, engine.plan, it,
            keepProgram, session.programId!!, deviceId) }
        val stamp = engine.stageStartedAt
        transaction {
            if (updated != null) {
                updated.forEach { item -> insert("liftProgramItem", ContentValues().apply {
                    put("id", item.id); put("deviceId", deviceId); put("programId", item.programId); put("ord", item.ord)
                    put("exercise", item.exercise); put("targetSets", item.targetSets); put("targetRepsLow", item.targetRepsLow)
                    put("targetRepsHigh", item.targetRepsHigh); put("targetRpe", item.targetRpe); put("targetWeightKg", item.targetWeightKg)
                    put("restSec", item.restSec); put("note", item.note)
                }) }
                db.execSQL("UPDATE liftProgram SET updatedAt = ? WHERE id = ? AND deviceId = ?", arrayOf(stamp, session.programId, deviceId))
            }
            db.execSQL("DELETE FROM liftSet WHERE sessionId = ? AND deviceId = ?", arrayOf(session.id, deviceId))
            if (!com.noop.analytics.LiftSessionFinish.anyPerformed(sets)) {
                db.execSQL("DELETE FROM liftSession WHERE id = ? AND deviceId = ?", arrayOf(session.id, deviceId))
            } else {
                sets.forEachIndexed { index, set ->
                    val item = engine.item(set.slot) ?: error("Missing session plan slot")
                    insert("liftSet", ContentValues().apply {
                        put("id", id()); put("deviceId", deviceId); put("sessionId", session.id); put("ord", index)
                        put("exercise", item.exercise); put("primaryMuscle", item.primaryMuscle?.name)
                        put("secondaryMuscles", LiftMuscle.encodeList(item.secondaryMuscles, item.primaryMuscle)); put("setIndex", set.slot.setIndex)
                        put("weightKg", set.weightKg); put("reps", set.reps); put("rpe", set.rpe); put("isWarmup", if (set.isWarmup) 1 else 0)
                        put("startTs", set.startTs); put("endTs", set.endTs); put("restSec", set.restSec)
                    })
                    val known = query("SELECT id,createdAt FROM liftExercise WHERE deviceId = ? AND name = ?", arrayOf(deviceId, item.exercise)) { it.text("id")!! to it.long("createdAt")!! }.firstOrNull()
                    insert("liftExercise", ContentValues().apply {
                        put("id", known?.first ?: id()); put("deviceId", deviceId); put("name", item.exercise)
                        put("primaryMuscle", item.primaryMuscle?.name); put("secondaryMuscles", LiftMuscle.encodeList(item.secondaryMuscles, item.primaryMuscle))
                        put("createdAt", known?.second ?: stamp); put("lastUsedTs", stamp)
                    })
                }
                db.execSQL("UPDATE liftSession SET endTs = ?, sessionRpe = ?, note = ? WHERE id = ? AND deviceId = ?",
                    arrayOf(stamp, rpe, note, session.id, deviceId))
                insert("workout", ContentValues().apply {
                    put("deviceId", deviceId); put("startTs", session.startTs); put("endTs", stamp); put("sport", session.sport)
                    put("source", "manual"); put("durationS", maxOf(0L, stamp - session.startTs).toDouble()); put("notes", note)
                })
            }
        }
    }
    suspend fun discardSession(session: LiftSessionRow) = withContext(Dispatchers.IO) {
        transaction {
            db.execSQL("DELETE FROM liftSet WHERE sessionId = ? AND deviceId = ?", arrayOf(session.id, deviceId))
            db.execSQL("DELETE FROM liftSession WHERE id = ? AND deviceId = ? AND endTs IS NULL", arrayOf(session.id, deviceId))
        }
    }
    suspend fun saveSet(set: LiftSetEntity, weight: Double?, reps: Int?, rpe: Double?, warmup: Boolean) = withContext(Dispatchers.IO) {
        require((weight == null || weight.isFinite() && weight >= 0) && (reps == null || reps >= 0) && (rpe == null || rpe.isFinite() && rpe in 1.0..10.0))
        db.execSQL("UPDATE liftSet SET weightKg = ?, reps = ?, rpe = ?, isWarmup = ? WHERE id = ? AND deviceId = ?",
            arrayOf(weight, reps, rpe, if (warmup) 1 else 0, set.id, deviceId))
    }
    suspend fun deleteSet(set: LiftSetEntity) = withContext(Dispatchers.IO) {
        db.execSQL("DELETE FROM liftSet WHERE id = ? AND deviceId = ?", arrayOf(set.id, deviceId))
    }
    suspend fun archiveProgram(program: LiftProgramRow) = withContext(Dispatchers.IO) {
        db.execSQL("UPDATE liftProgram SET archived = 1,updatedAt = ? WHERE id = ? AND deviceId = ?", arrayOf(now(), program.id, deviceId))
    }
    suspend fun updateSession(session: LiftSessionRow, rpe: Double?, note: String?) = withContext(Dispatchers.IO) {
        require(rpe == null || rpe.isFinite() && rpe in 1.0..10.0)
        transaction {
            db.execSQL("UPDATE liftSession SET sessionRpe = ?,note = ? WHERE id = ? AND deviceId = ?", arrayOf(rpe, note, session.id, deviceId))
            db.execSQL("UPDATE workout SET notes = ? WHERE deviceId = ? AND startTs = ? AND sport = ? AND source = 'manual'", arrayOf(note, deviceId, session.startTs, session.sport))
        }
    }
    suspend fun importPrograms(result: BroopLiftProgramImporter.Result) = withContext(Dispatchers.IO) {
        val stamp = now()
        transaction {
            result.programs.forEach { program ->
                val programId = id()
                insert("liftProgram", ContentValues().apply {
                    put("id", programId); put("deviceId", deviceId); put("name", program.name); put("note", program.note)
                    put("createdAt", stamp); put("updatedAt", stamp); put("archived", 0)
                })
                program.lines.forEachIndexed { index, line ->
                    insert("liftProgramItem", ContentValues().apply {
                        put("id", id()); put("deviceId", deviceId); put("programId", programId); put("ord", index)
                        put("exercise", line.exercise); put("targetSets", line.sets); put("targetRepsLow", line.reps)
                        put("targetRpe", line.rpe); put("targetWeightKg", line.weight); put("restSec", line.rest); put("note", line.note)
                    })
                    val known = query("SELECT id,createdAt FROM liftExercise WHERE deviceId = ? AND name = ?", arrayOf(deviceId, line.exercise)) { it.text("id")!! to it.long("createdAt")!! }.firstOrNull()
                    insert("liftExercise", ContentValues().apply {
                        put("id", known?.first ?: id()); put("deviceId", deviceId); put("name", line.exercise)
                        put("primaryMuscle", line.primary?.name); put("secondaryMuscles", LiftMuscle.encodeList(line.secondary, line.primary))
                        put("createdAt", known?.second ?: stamp)
                    })
                }
            }
        }
    }
}

private fun LiftSetEntity.metricRow(): LiftMetrics.Row = LiftMetrics.Row(ord, exercise, isWarmup, weightKg, reps, rpe,
    LiftMuscle.fromRaw(primaryMuscle), LiftMuscle.decodeList(secondaryMuscles))

/** Keep raw edits while typing; parsing a trailing decimal must not rewrite the text field. */
internal data class BroopLiftProgramDraft(val sets: String, val repsLow: String, val repsHigh: String,
    val weight: String, val rpe: String, val rest: String, val note: String) {
    constructor(row: LiftProgramItemRow) : this(row.targetSets?.toString().orEmpty(), row.targetRepsLow?.toString().orEmpty(),
        row.targetRepsHigh?.toString().orEmpty(), row.targetWeightKg?.toString().orEmpty(), row.targetRpe?.toString().orEmpty(),
        row.restSec?.toString().orEmpty(), row.note.orEmpty())
    val valid: Boolean get() {
        fun integer(text: String, minimum: Int) = text.isBlank() || text.toIntOrNull()?.let { it >= minimum } == true
        fun number(text: String, minimum: Double, maximum: Double = Double.MAX_VALUE) = text.isBlank() ||
            text.toDoubleOrNull()?.let { it.isFinite() && it in minimum..maximum } == true
        return integer(sets, 1) && integer(repsLow, 0) && integer(repsHigh, 0) && number(weight, 0.0) &&
            number(rpe, 1.0, 10.0) && integer(rest, 0) && (repsHigh.isBlank() || repsLow.isBlank() || (repsHigh.toIntOrNull() ?: -1) >= (repsLow.toIntOrNull() ?: 0))
    }
    fun applying(row: LiftProgramItemRow): LiftProgramItemRow {
        require(valid)
        return row.copy(targetSets = sets.toIntOrNull(), targetRepsLow = repsLow.toIntOrNull(), targetRepsHigh = repsHigh.toIntOrNull(),
            targetWeightKg = weight.toDoubleOrNull(), targetRpe = rpe.toDoubleOrNull(), restSec = rest.toIntOrNull(), note = note.take(200).ifBlank { null })
    }
}

@Composable
fun BroopLiftLogScreen(vm: AppViewModel, onBack: (() -> Unit)? = null, autoResume: Boolean = false) {
    val context = LocalContext.current
    val store = remember(vm.activeStrapId, context) { BroopLiftStore(context, vm.activeStrapId) }
    val scope = rememberCoroutineScope()
    var revision by remember { mutableStateOf(0) }
    var programs by remember { mutableStateOf<List<LiftProgramRow>>(emptyList()) }
    var sessions by remember { mutableStateOf<List<LiftSessionRow>>(emptyList()) }
    var allSets by remember { mutableStateOf<Map<String, List<LiftSetEntity>>>(emptyMap()) }
    var editing by remember { mutableStateOf(false) }
    var programToEdit by remember { mutableStateOf<LiftProgramRow?>(null) }
    var viewing by remember { mutableStateOf<LiftSessionRow?>(null) }
    var progress by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var importing by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(store, revision) {
        try {
            programs = store.programs(); sessions = store.sessions()
            allSets = sessions.associate { it.id to store.sets(it.id) }; loaded = true
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = uiString(R.string.broop_body_the_strength_log_could_not_be_read_please_try_c258dbd); loaded = true }
    }
    val liftController = vm.broopLift
    val active = sessions.firstOrNull { it.endTs == null }
    var resumed by remember(store) { mutableStateOf(false) }
    LaunchedEffect(store, loaded, active?.id) {
        if (autoResume && loaded && active != null && !resumed) { resumed = true; viewing = active }
    }
    fun start(program: LiftProgramRow?) { scope.launch {
        try {
            store.start(program)
            val started = store.sessions().first { it.endTs == null }
            liftController.attach(started, program?.let { store.items(it.id) }.orEmpty(), store.exercises(), emptyList())
            viewing = started; revision++
        }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = uiString(R.string.broop_body_the_session_could_not_be_started_please_try_a_252e4d5) }
    } }
    BroopPage(uiString(R.string.broop_body_strength_trainer_be7a1d4), onBack) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            TextButton(onClick = { progress = false }) { Text(uiString(R.string.broop_body_my_workouts_eea31e4), color = if (!progress) BroopPalette.textPrimary else BroopPalette.textSecondary) }
            TextButton(onClick = { progress = true }) { Text(uiString(R.string.broop_body_progress_1b90271), color = if (progress) BroopPalette.textPrimary else BroopPalette.textSecondary) }
        }
        if (active != null) {
            BroopCard(onClick = { viewing = active }) {
                BroopCaps(uiString(R.string.today_live_session_running), BroopPalette.connected)
                Text(active.programName ?: uiString(R.string.broop_body_free_session_88633a3), style = BroopType.section, color = BroopPalette.textPrimary)
                Text(uiString(R.string.broop_body_1_s_sets_logged_tap_to_continue_7f7dddd, (liftController.engine?.sets?.size ?: allSets[active.id].orEmpty().size).toString()), style = BroopType.body, color = BroopPalette.textBody)
            }
        }
        if (!progress) {
            BroopBodyButton(uiString(R.string.broop_body_start_free_session_7bc09db), active == null) { start(null) }
            BroopBodyButton(uiString(R.string.broop_body_create_program_63a76cb)) { programToEdit = null; editing = true }
            BroopBodyButton(uiString(R.string.broop_body_import_programs_3ea1d93)) { importing = true }
            BroopSection(uiString(R.string.broop_body_saved_programs_43b7a51))
            if (loaded && programs.isEmpty()) BroopEmpty(uiString(R.string.broop_body_your_programs_e6de2df), uiString(R.string.broop_body_build_a_program_from_your_own_exercise_names__1f4ea6a))
            programs.forEach { program ->
                BroopCard {
                    Text(program.name, style = BroopType.section, color = BroopPalette.textPrimary)
                    Row(horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                        TextButton(onClick = { programToEdit = program; editing = true }) { Text(uiString(R.string.workout_detected_action_edit), color = BroopPalette.textBody) }
                        TextButton(onClick = { start(program) }, enabled = active == null) { Text(uiString(R.string.ground_truth_marker_start), color = BroopPalette.teal) }
                    }
                }
            }
        } else {
            BroopSection(uiString(R.string.broop_body_sets_per_muscle_2836360))
            val week = LocalDate.now().minusDays(6).atStartOfDay(ZoneId.systemDefault()).toEpochSecond()
            val rows = sessions.filter { it.startTs >= week }.flatMap { allSets[it.id].orEmpty() }.map { it.metricRow() }
            val counts = LiftMetrics.muscleCounts(rows).fractional
            BroopCard {
                if (counts.isEmpty()) Text(uiString(R.string.broop_body_assign_muscles_as_you_log_sets_to_see_your_we_5ff13e6), style = BroopType.body, color = BroopPalette.textBody)
                counts.forEach { (muscle, value) -> BroopBodyValue(broopMuscleName(muscle), uiString(R.string.broop_body_1_s_sets_75c7fc6, (broopOne(value)).toString())) }
                Text(uiString(R.string.broop_body_last_7_days_direct_sets_count_once_and_second_efd2913), style = BroopType.caption, color = BroopPalette.textSecondary)
            }
            BroopSection(uiString(R.string.l10n_insights_screen_sessions_e11e37a9))
            sessions.filter { it.endTs != null }.forEach { session ->
                val date = Instant.ofEpochSecond(session.startTs).atZone(ZoneId.systemDefault())
                    .format(DateTimeFormatter.ofPattern("d MMM yyyy · HH:mm", Locale.getDefault()))
                BroopRow(session.programName ?: uiString(R.string.broop_body_free_session_88633a3), uiString(R.string.broop_body_1_s_2_s_sets_330f729, (date).toString(), (allSets[session.id].orEmpty().size).toString())) { viewing = session }
            }
        }
        Text(uiString(R.string.broop_body_typed_sets_never_change_cardiovascular_effort_6b36675), style = BroopType.caption, color = BroopPalette.textSecondary)
    }
    if (editing) BroopLiftProgramEditor(store, programToEdit, onClose = { editing = false }, onSaved = { revision++; editing = false })
    if (importing) BroopLiftImportSheet(store, onClose = { importing = false }, onImported = { revision++; importing = false })
    viewing?.let { target ->
        val resolved = sessions.firstOrNull { it.id == target.id } ?: target
        if (resolved.endTs == null) BroopLiftActiveSessionView(vm, store, resolved, allSets[target.id].orEmpty(),
            onClose = { viewing = null }, onChanged = { revision++; vm.loadWorkouts() })
        else BroopLiftSessionView(store, resolved, allSets[target.id].orEmpty(),
            onClose = { viewing = null }, onChanged = { revision++; vm.loadWorkouts() })
    }
    error?.let { message -> AlertDialog(onDismissRequest = { error = null }, text = { Text(message) },
        confirmButton = { TextButton(onClick = { error = null; revision++ }) { Text(uiString(R.string.broop_body_retry_9f5cd8a)) } }) }
}

@Composable
private fun BroopLiftProgramEditor(store: BroopLiftStore, program: LiftProgramRow?, onClose: () -> Unit, onSaved: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(program?.name ?: "") }
    var rows by remember { mutableStateOf<List<LiftProgramItemRow>>(emptyList()) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var archive by remember { mutableStateOf(false) }
    var programNote by rememberSaveable { mutableStateOf(program?.note ?: "") }
    var drafts by remember { mutableStateOf<Map<String, BroopLiftProgramDraft>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(program) { if (program != null) try { rows = store.items(program.id) }
        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { error = uiString(R.string.broop_body_this_program_could_not_be_read_459616e) } }
    fun blank() = LiftProgramItemRow(UUID.randomUUID().toString(), "", program?.id ?: "", rows.size, "", targetSets = 3, restSec = 90)
    Dialog(onDismissRequest = { if (!saving) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(if (program == null) uiString(R.string.broop_body_create_program_63a76cb) else uiString(R.string.broop_body_edit_program_1cf307c), { if (!saving) onClose() }) {
            OutlinedTextField(name, { name = it }, label = { Text(uiString(R.string.broop_body_program_name_699413c)) }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(programNote, { programNote = it.take(120) }, label = { Text(uiString(R.string.broop_body_program_note)) }, modifier = Modifier.fillMaxWidth())
            rows.forEachIndexed { index, item ->
                val draft = drafts[item.id] ?: BroopLiftProgramDraft(item)
                fun change(next: BroopLiftProgramDraft) { drafts = drafts + (item.id to next) }
                BroopCard {
                    OutlinedTextField(item.exercise, { value -> rows = rows.toMutableList().also { it[index] = item.copy(exercise = value) } },
                        label = { Text(uiString(R.string.broop_body_exercise_20863c8)) }, modifier = Modifier.fillMaxWidth())
                    BroopLiftNumberField(uiString(R.string.broop_body_sets_2ab262f), draft.sets) { change(draft.copy(sets = it)) }
                    BroopLiftNumberField(uiString(R.string.broop_body_reps_low), draft.repsLow) { change(draft.copy(repsLow = it)) }
                    BroopLiftNumberField(uiString(R.string.broop_body_reps_high), draft.repsHigh) { change(draft.copy(repsHigh = it)) }
                    BroopLiftNumberField(uiString(R.string.broop_body_target_weight_kg_4208ada), draft.weight) { change(draft.copy(weight = it)) }
                    BroopLiftNumberField(uiString(R.string.broop_body_target_max_rpe), draft.rpe) { change(draft.copy(rpe = it)) }
                    BroopLiftNumberField(uiString(R.string.broop_body_rest_seconds_0341bbc), draft.rest) { change(draft.copy(rest = it)) }
                    OutlinedTextField(draft.note, { change(draft.copy(note = it.take(200))) }, label = { Text(uiString(R.string.broop_body_technique_note)) }, modifier = Modifier.fillMaxWidth())
                    if (!draft.valid) Text(uiString(R.string.broop_body_review_targets), style = BroopType.caption, color = BroopPalette.warning)
                    Row(horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                        TextButton(enabled = index > 0, onClick = { rows = rows.toMutableList().apply { add(index - 1, removeAt(index)) } }) { Text(uiString(R.string.broop_body_move_up)) }
                        TextButton(enabled = index < rows.lastIndex, onClick = { rows = rows.toMutableList().apply { add(index + 1, removeAt(index)) } }) { Text(uiString(R.string.broop_body_move_down)) }
                    }
                    TextButton(onClick = { rows = rows.filterIndexed { i, _ -> i != index } }) { Text(uiString(R.string.broop_body_remove_exercise_4c52294), color = BroopPalette.textSecondary) }
                }
            }
            BroopBodyButton(uiString(R.string.broop_body_add_exercise_6440480)) { rows = rows + blank() }
            if (program != null) BroopBodyButton(uiString(R.string.broop_body_archive_program_6c84cdc), !saving) { archive = true }
            error?.let { Text(it, style = BroopType.body, color = BroopPalette.warning) }
            BroopBodyButton(if (saving) uiString(R.string.broop_body_saving_56a2285) else uiString(R.string.broop_body_save_program_61b7d92), !saving && name.isNotBlank() && rows.isNotEmpty() && rows.all { it.exercise.isNotBlank() && (drafts[it.id] ?: BroopLiftProgramDraft(it)).valid }) {
                saving = true
                scope.launch { try { store.saveProgram(program, name, rows.map { (drafts[it.id] ?: BroopLiftProgramDraft(it)).applying(it) }, programNote.ifBlank { null }); onSaved() }
                    catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                    catch (_: Exception) { error = uiString(R.string.broop_body_the_program_was_not_saved_your_edits_are_stil_dc884ee) }
                    finally { saving = false } }
            }
        }
    }
    if (archive && program != null) AlertDialog(onDismissRequest = { archive = false }, title = { Text(uiString(R.string.broop_body_archive_program_059f31d)) },
        text = { Text(uiString(R.string.broop_body_the_program_leaves_your_workouts_list_existin_d8f4585)) },
        confirmButton = { TextButton(onClick = { archive = false; scope.launch { try { store.archiveProgram(program); onSaved() }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { error = uiString(R.string.broop_body_the_program_could_not_be_archived_0283a60) } } }) { Text(uiString(R.string.broop_body_archive_2621c6f)) } },
        dismissButton = { TextButton(onClick = { archive = false }) { Text(uiString(R.string.ground_truth_cancel)) } })
}

@Composable
private fun BroopLiftSessionView(store: BroopLiftStore, session: LiftSessionRow, sets: List<LiftSetEntity>, onClose: () -> Unit, onChanged: () -> Unit) {
    val scope = rememberCoroutineScope()
    var exercise by rememberSaveable(session.id) { mutableStateOf(sets.lastOrNull()?.exercise ?: "") }
    var weight by rememberSaveable(session.id) { mutableStateOf("") }
    var reps by rememberSaveable(session.id) { mutableStateOf("") }
    var rpe by rememberSaveable(session.id) { mutableStateOf("") }
    var warmup by rememberSaveable(session.id) { mutableStateOf(false) }
    var primary by remember { mutableStateOf<LiftMuscle?>(null) }
    var secondaries by remember { mutableStateOf<List<LiftMuscle>>(emptyList()) }
    var primaryPicker by remember { mutableStateOf(false) }
    var secondaryPicker by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var finish by remember { mutableStateOf(false) }
    var sessionRpe by rememberSaveable(session.id) { mutableStateOf("") }
    var note by rememberSaveable(session.id) { mutableStateOf(session.note ?: "") }
    var now by remember { mutableStateOf(System.currentTimeMillis() / 1000) }
    var plan by remember { mutableStateOf<List<LiftProgramItemRow>>(emptyList()) }
    var setStartedAt by rememberSaveable(session.id) { mutableStateOf<Long?>(null) }
    var editingSet by remember { mutableStateOf<LiftSetEntity?>(null) }
    LaunchedEffect(session.id) {
        session.programId?.let { id -> plan = store.items(id); if (exercise.isBlank()) exercise = plan.firstOrNull()?.exercise ?: "" }
        while (session.endTs == null) { delay(1000); now = System.currentTimeMillis() / 1000 }
    }
    val rows = sets.map { it.metricRow() }
    val volume = LiftMetrics.volumeLoadKg(rows)
    val weightValue = weight.toDoubleOrNull(); val repsValue = reps.toIntOrNull(); val rpeValue = rpe.toDoubleOrNull()
    val valid = exercise.isNotBlank() && (weight.isBlank() || weightValue?.let { it.isFinite() && it >= 0 } == true) &&
        (reps.isBlank() || repsValue?.let { it >= 0 } == true) && (rpe.isBlank() || rpeValue?.let { it.isFinite() && it in 1.0..10.0 } == true)
    Dialog(onDismissRequest = { if (!saving) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(session.programName ?: uiString(R.string.broop_body_strength_session_84a38cf), { if (!saving) onClose() }) {
            BroopCard {
                val elapsed = maxOf(0L, (session.endTs ?: now) - session.startTs)
                BroopBodyValue(uiString(R.string.broop_body_duration_1370004), "${elapsed / 60}:${(elapsed % 60).toString().padStart(2, '0')}")
                BroopBodyValue(uiString(R.string.broop_body_sets_logged_e642d28), sets.size.toString())
                volume?.let { BroopBodyValue(uiString(R.string.broop_body_volume_load_8710aef), "${broopOne(it)} kg") }
                sets.lastOrNull()?.endTs?.takeIf { session.endTs == null }?.let { BroopBodyValue(uiString(R.string.broop_body_since_last_set_e5b4ceb), "${maxOf(0L, now - it)} sec") }
            }
            if (session.endTs == null) {
                if (plan.isNotEmpty()) {
                    BroopSection(uiString(R.string.broop_body_program_9d68007))
                    plan.forEach { item -> BroopRow(item.exercise, uiString(R.string.broop_body_1_s_sets_2_s_reps_3_s_kg_4_s_sec_rest_522f62f, (item.targetSets ?: "--").toString(), (item.targetRepsLow ?: "--").toString(), (item.targetWeightKg?.let(::broopOne) ?: "--").toString(), (item.restSec ?: "--").toString())) {
                        exercise = item.exercise; weight = item.targetWeightKg?.let(::broopOne) ?: ""; reps = item.targetRepsLow?.toString() ?: ""; rpe = ""
                    } }
                }
                BroopSection(uiString(R.string.broop_body_log_a_set_f78c7e1))
                BroopCard {
                    OutlinedTextField(exercise, { exercise = it }, label = { Text(uiString(R.string.broop_body_exercise_20863c8)) }, modifier = Modifier.fillMaxWidth())
                    BroopLiftNumberField(uiString(R.string.broop_body_weight_kg_d249832), weight) { weight = it }
                    BroopLiftNumberField(uiString(R.string.broop_body_reps_702045f), reps) { reps = it }
                    BroopLiftNumberField(uiString(R.string.broop_body_rpe_1_10_optional_862f960), rpe) { rpe = it }
                    Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(warmup, { warmup = it }); Text(uiString(R.string.broop_body_warm_up_set_331fda9), style = BroopType.body, color = BroopPalette.textBody) }
                    TextButton(onClick = { primaryPicker = true }) { Text(uiString(R.string.broop_body_primary_muscle_1_s_9ea716c, (primary?.let(::broopMuscleName) ?: uiString(R.string.broop_body_unassigned_e57016e)).toString()), color = BroopPalette.textBody) }
                    DropdownMenu(primaryPicker, { primaryPicker = false }) {
                        DropdownMenuItem(text = { Text(uiString(R.string.broop_body_unassigned_e57016e)) }, onClick = { primary = null; primaryPicker = false })
                        LiftMuscle.entries.forEach { muscle -> DropdownMenuItem(text = { Text(broopMuscleName(muscle)) }, onClick = { primary = muscle; secondaries = secondaries - muscle; primaryPicker = false }) }
                    }
                    TextButton(onClick = { secondaryPicker = true }) { Text(uiString(R.string.broop_body_secondary_muscles_1_s_f729d5e, (secondaries.size).toString()), color = BroopPalette.textBody) }
                    DropdownMenu(secondaryPicker, { secondaryPicker = false }) {
                        LiftMuscle.entries.filter { it != primary }.forEach { muscle -> DropdownMenuItem(text = { Text(listOfNotNull(if (muscle in secondaries) "✓" else null, broopMuscleName(muscle)).joinToString(" ")) }, onClick = { secondaries = if (muscle in secondaries) secondaries - muscle else secondaries + muscle }) }
                    }
                    if (setStartedAt == null) BroopBodyButton(uiString(R.string.broop_body_start_set_c818c49), valid && !saving) { setStartedAt = System.currentTimeMillis() / 1000 }
                    else BroopBodyValue(uiString(R.string.broop_body_set_in_progress_abcce63), "${maxOf(0L, now - (setStartedAt ?: now))} sec")
                    BroopBodyButton(if (saving) uiString(R.string.broop_body_saving_56a2285) else uiString(R.string.broop_body_complete_set_2c711f0), valid && !saving && setStartedAt != null) {
                        saving = true
                        scope.launch { try { store.logSet(session, exercise, weightValue, repsValue, rpeValue, warmup, primary, secondaries, setStartedAt); setStartedAt = null; rpe = ""; onChanged() }
                            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                            catch (_: Exception) { error = uiString(R.string.broop_body_the_set_was_not_saved_your_entries_are_still__96e66f8) }
                            finally { saving = false } }
                    }
                }
                BroopBodyButton(uiString(R.string.broop_body_finish_session_5fe14d3), !saving) { finish = true }
            } else {
                BroopBodyButton(uiString(R.string.broop_body_edit_session_notes_and_rating_7b25bfc)) { sessionRpe = session.sessionRpe?.let(::broopOne) ?: ""; finish = true }
            }
            error?.let { Text(it, style = BroopType.body, color = BroopPalette.warning) }
            BroopSection(uiString(R.string.broop_body_logged_sets_fba3249))
            sets.forEach { set -> BroopCard(onClick = { editingSet = set }) {
                BroopCaps(uiString(R.string.broop_body_1_s_set_2_s_3_s_89be812, (set.exercise).toString(), (set.setIndex).toString(), (if (set.isWarmup) uiString(R.string.broop_body_warm_up_47148ff) else "").toString()))
                BroopBodyValue(uiString(R.string.broop_body_weight_reps_f413c45), "${set.weightKg?.let(::broopOne) ?: "--"} kg × ${set.reps ?: "--"}")
                set.rpe?.let { BroopBodyValue("RPE", broopOne(it)) }
                LiftMetrics.estimatedOneRepMaxKg(set.weightKg, set.reps)?.let { BroopBodyValue(uiString(R.string.broop_body_estimated_1rm_c8e4686), "${broopOne(it)} kg") }
            } }
        }
    }
    if (finish) AlertDialog(onDismissRequest = { if (!saving) finish = false }, title = { Text(uiString(R.string.broop_body_finish_session_5fe14d3)) },
        text = { androidx.compose.foundation.layout.Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            BroopLiftNumberField(uiString(R.string.broop_body_session_rpe_1_10_optional_8e9effb), sessionRpe) { sessionRpe = it }
            OutlinedTextField(note, { note = it }, label = { Text(uiString(R.string.broop_body_session_note_fd92224)) })
        } }, confirmButton = { TextButton(enabled = !saving && (sessionRpe.isBlank() || sessionRpe.toDoubleOrNull()?.let { it.isFinite() && it in 1.0..10.0 } == true), onClick = {
            saving = true; scope.launch { try {
                if (session.endTs == null) store.finish(session, sessionRpe.toDoubleOrNull(), note.ifBlank { null })
                else store.updateSession(session, sessionRpe.toDoubleOrNull(), note.ifBlank { null })
                onChanged(); finish = false; onClose()
            }
                catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                catch (_: Exception) { error = uiString(R.string.broop_body_the_session_could_not_be_finished_your_sets_a_5674aeb) }
                finally { saving = false } }
        }) { Text(uiString(R.string.broop_body_save_session_8c7478c)) } }, dismissButton = { TextButton(onClick = { finish = false }, enabled = !saving) { Text(uiString(R.string.ground_truth_cancel)) } })
    editingSet?.let { set -> BroopLiftSetEditor(store, set, onClose = { editingSet = null }, onSaved = { editingSet = null; onChanged() }) }
}

@Composable
private fun BroopLiftSetEditor(store: BroopLiftStore, set: LiftSetEntity, onClose: () -> Unit, onSaved: () -> Unit) {
    var weight by rememberSaveable(set.id) { mutableStateOf(set.weightKg?.let(::broopOne) ?: "") }
    var reps by rememberSaveable(set.id) { mutableStateOf(set.reps?.toString() ?: "") }
    var rpe by rememberSaveable(set.id) { mutableStateOf(set.rpe?.let(::broopOne) ?: "") }
    var warmup by rememberSaveable(set.id) { mutableStateOf(set.isWarmup) }
    var deleting by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val w = weight.toDoubleOrNull(); val r = reps.toIntOrNull(); val effort = rpe.toDoubleOrNull()
    val valid = (weight.isBlank() || w?.let { it.isFinite() && it >= 0 } == true) &&
        (reps.isBlank() || r?.let { it >= 0 } == true) && (rpe.isBlank() || effort?.let { it.isFinite() && it in 1.0..10.0 } == true)
    AlertDialog(onDismissRequest = { if (!saving) onClose() }, title = { Text(uiString(R.string.broop_body_1_s_set_2_s_7e002a8, (set.exercise).toString(), (set.setIndex).toString())) },
        text = { androidx.compose.foundation.layout.Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
            BroopLiftNumberField(uiString(R.string.broop_body_weight_kg_d249832), weight) { weight = it }
            BroopLiftNumberField(uiString(R.string.broop_body_reps_702045f), reps) { reps = it }
            BroopLiftNumberField(uiString(R.string.broop_body_rpe_1_10_optional_862f960), rpe) { rpe = it }
            Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(warmup, { warmup = it }); Text(uiString(R.string.broop_body_warm_up_set_331fda9)) }
            if (error) Text(uiString(R.string.broop_body_the_set_was_not_saved_please_try_again_fbdeb56))
            TextButton(onClick = { deleting = true }, enabled = !saving) { Text(uiString(R.string.broop_body_delete_set_45fc823)) }
        } }, confirmButton = { TextButton(enabled = valid && !saving, onClick = {
            saving = true; scope.launch { try { store.saveSet(set, w, r, effort, warmup); onSaved() }
                catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                catch (_: Exception) { error = true }
                finally { saving = false } }
        }) { Text(uiString(R.string.ground_truth_save)) } }, dismissButton = { TextButton(onClick = onClose, enabled = !saving) { Text(uiString(R.string.ground_truth_cancel)) } })
    if (deleting) AlertDialog(onDismissRequest = { deleting = false }, title = { Text(uiString(R.string.broop_body_delete_set_9e5a6f1)) },
        text = { Text(uiString(R.string.broop_body_this_set_will_be_removed_from_the_session_and_d186c4f)) },
        confirmButton = { TextButton(onClick = { deleting = false; saving = true; scope.launch { try { store.deleteSet(set); onSaved() }
            catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { error = true }
            finally { saving = false } } }) { Text(uiString(R.string.ground_truth_delete_confirm)) } }, dismissButton = { TextButton(onClick = { deleting = false }) { Text(uiString(R.string.ground_truth_cancel)) } })
}

@Composable
internal fun BroopLiftNumberField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(value, onChange, label = { Text(label) }, modifier = Modifier.fillMaxWidth(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
}

internal fun broopMuscleName(muscle: LiftMuscle): String = uiString(when (muscle) {
    LiftMuscle.chest -> R.string.broop_body_muscle_chest
    LiftMuscle.frontDelts -> R.string.broop_body_muscle_frontdelts
    LiftMuscle.sideDelts -> R.string.broop_body_muscle_sidedelts
    LiftMuscle.rearDelts -> R.string.broop_body_muscle_reardelts
    LiftMuscle.triceps -> R.string.broop_body_muscle_triceps
    LiftMuscle.lats -> R.string.broop_body_muscle_lats
    LiftMuscle.upperBack -> R.string.broop_body_muscle_upperback
    LiftMuscle.traps -> R.string.broop_body_muscle_traps
    LiftMuscle.biceps -> R.string.broop_body_muscle_biceps
    LiftMuscle.forearms -> R.string.broop_body_muscle_forearms
    LiftMuscle.quads -> R.string.broop_body_muscle_quads
    LiftMuscle.hamstrings -> R.string.broop_body_muscle_hamstrings
    LiftMuscle.glutes -> R.string.broop_body_muscle_glutes
    LiftMuscle.adductors -> R.string.broop_body_muscle_adductors
    LiftMuscle.abductors -> R.string.broop_body_muscle_abductors
    LiftMuscle.calves -> R.string.broop_body_muscle_calves
    LiftMuscle.abs -> R.string.broop_body_muscle_abs
    LiftMuscle.obliques -> R.string.broop_body_muscle_obliques
    LiftMuscle.lowerBack -> R.string.broop_body_muscle_lowerback
    LiftMuscle.neck -> R.string.broop_body_muscle_neck
})
