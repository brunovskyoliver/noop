package com.noop.ui

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.viewModelScope
import com.noop.R
import com.noop.analytics.*
import com.noop.data.LiftExerciseRow
import com.noop.data.LiftMuscle
import com.noop.data.LiftProgramItemRow
import com.noop.data.LiftSessionRow
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Android-local crash snapshot; plan, stage, seconds and pending input match LiftSessionPersistence. */
internal object BroopLiftSnapshot {
    data class Restored(val sessionId: String, val deviceId: String, val engine: LiftSessionEngine,
        val pending: Map<LiftSlot, LiftPendingValues>, val warmups: Set<LiftSlot>, val warnedFor: Long?)
    fun encode(value: Restored): String {
        val engine = value.engine
        fun slot(slot: LiftSlot) = JSONObject().put("exerciseIndex", slot.exerciseIndex).put("setIndex", slot.setIndex)
        val stage = JSONObject()
        when (val current = engine.stage) {
            LiftSessionEngine.Stage.Warmup -> stage.put("kind", "warmup")
            LiftSessionEngine.Stage.Finished -> stage.put("kind", "finished")
            is LiftSessionEngine.Stage.Working -> stage.put("kind", "working").put("item", current.slot.exerciseIndex).put("set", current.slot.setIndex)
            is LiftSessionEngine.Stage.Resting -> stage.put("kind", "resting").put("item", current.slot.exerciseIndex).put("set", current.slot.setIndex).put("endsAt", current.endsAt)
        }
        return JSONObject().put("sessionId", value.sessionId).put("deviceId", value.deviceId).put("startSec", engine.startTs)
            .put("stageStartedAt", engine.stageStartedAt).put("stage", stage).put("warnedFor", value.warnedFor)
            .put("plan", JSONArray(engine.plan.map { line -> JSONObject().put("exercise", line.exercise)
                .put("primaryMuscle", line.primaryMuscle?.name).put("secondaryMuscles", JSONArray(line.secondaryMuscles.map { it.name }))
                .put("targetSets", line.targetSets).put("restSec", line.restSec).put("targetRepsLow", line.targetRepsLow)
                .put("targetRepsHigh", line.targetRepsHigh).put("targetRpe", line.targetRpe).put("targetWeightKg", line.targetWeightKg)
                .put("note", line.note).put("programItemId", line.programItemId).put("addedInSession", line.addedInSession) }))
            .put("sets", JSONArray(engine.sets.map { set -> slot(set.slot).put("weightKg", set.weightKg).put("reps", set.reps)
                .put("rpe", set.rpe).put("isWarmup", set.isWarmup).put("startTs", set.startTs).put("endTs", set.endTs).put("restSec", set.restSec) }))
            .put("pendingValues", JSONArray(value.pending.entries.sortedWith(compareBy({ it.key.exerciseIndex }, { it.key.setIndex })).map { (key, input) ->
                slot(key).put("weightKg", input.weightKg).put("reps", input.reps).put("rpe", input.rpe) }))
            .put("pendingWarmups", JSONArray(value.warmups.sortedWith(compareBy({ it.exerciseIndex }, { it.setIndex })).map(::slot))).toString()
    }
    fun decode(raw: String?, now: Long): Restored? = try {
        if (raw == null || raw.length > 4_000_000) null else {
            val json = JSONObject(raw)
            fun JSONObject.number(key: String) = if (has(key) && !isNull(key)) getDouble(key).takeIf { it.isFinite() } else null
            fun JSONObject.integer(key: String) = number(key)?.toInt()
            fun JSONObject.text(key: String) = if (has(key) && !isNull(key)) getString(key) else null
            fun JSONArray.rows() = (0 until length()).map { getJSONObject(it) }
            fun JSONObject.slot() = LiftSlot(getInt("exerciseIndex"), getInt("setIndex"))
            val start = json.getLong("startSec")
            val plan = json.getJSONArray("plan").rows().map { row -> LiftPlanItem(row.getString("exercise"),
                LiftMuscle.fromRaw(row.text("primaryMuscle")), row.optJSONArray("secondaryMuscles")?.let { list ->
                    (0 until list.length()).mapNotNull { LiftMuscle.fromRaw(list.getString(it)) } }.orEmpty(),
                row.getInt("targetSets"), row.getInt("restSec"), row.integer("targetRepsLow"), row.integer("targetRepsHigh"),
                row.number("targetRpe"), row.number("targetWeightKg"), row.text("note"), row.text("programItemId"), row.optBoolean("addedInSession")) }
            require(start > 1_000_000_000 && start < now + 86_400 && plan.size <= 200)
            require(plan.sumOf { it.targetSets.toLong() } <= 50_000)
            require(plan.all { it.targetSets in 1..10_000 && it.restSec >= 0 && it.exercise.isNotBlank() })
            fun valid(slot: LiftSlot) = slot.exerciseIndex in plan.indices && slot.setIndex in 1..plan[slot.exerciseIndex].targetSets
            val box = json.getJSONObject("stage")
            val stageSlot = if (box.has("item") && box.has("set")) LiftSlot(box.getInt("item"), box.getInt("set")) else null
            val stage = when {
                box.optString("kind") == "working" && stageSlot != null && valid(stageSlot) -> LiftSessionEngine.Stage.Working(stageSlot)
                box.optString("kind") == "resting" && stageSlot != null && valid(stageSlot) && box.has("endsAt") -> LiftSessionEngine.Stage.Resting(stageSlot, box.getLong("endsAt"))
                box.optString("kind") == "finished" -> LiftSessionEngine.Stage.Finished
                else -> LiftSessionEngine.Stage.Warmup
            }
            val sets = json.getJSONArray("sets").rows().map { row ->
                val slot = row.slot(); require(valid(slot))
                LiftRecordedSet(slot.exerciseIndex, slot.setIndex, row.number("weightKg"), row.integer("reps"), row.number("rpe"),
                    row.getBoolean("isWarmup"), row.getLong("startTs"), row.getLong("endTs"), row.integer("restSec"))
            }
            require(plan.isNotEmpty() || (box.optString("kind") in setOf("warmup", "finished") && sets.isEmpty()))
            require(sets.map { it.slot }.distinct().size == sets.size)
            val pending = json.optJSONArray("pendingValues")?.rows().orEmpty().filter { valid(it.slot()) }.associate { row ->
                row.slot() to LiftPendingValues(row.number("weightKg"), row.integer("reps"), row.number("rpe")) }
            val warmups = json.optJSONArray("pendingWarmups")?.rows().orEmpty().map { it.slot() }.filter(::valid).toSet()
            Restored(json.getString("sessionId"), json.getString("deviceId"),
                LiftSessionEngine(plan, start, stage, sets, json.getLong("stageStartedAt")), pending, warmups, json.number("warnedFor")?.toLong())
        }
    } catch (_: Exception) { null }
}

/** Lives with AppViewModel, so minimising the sheet leaves gestures and rest warnings running. */
internal class BroopLiftController(private val vm: AppViewModel) {
    private val context = vm.getApplication<android.app.Application>()
    private val prefs = NoopPrefs.of(context)
    private var current: LiftSessionEngine? = null
    var revision by mutableIntStateOf(0); private set
    val engine: LiftSessionEngine? get() { revision; return current }
    var session by mutableStateOf<LiftSessionRow?>(null); private set
    var pending by mutableStateOf<Map<LiftSlot, LiftPendingValues>>(emptyMap()); private set
    var warmups by mutableStateOf<Set<LiftSlot>>(emptySet()); private set
    var saving by mutableStateOf(false); private set
    var isPresented by mutableStateOf(false)
    var last: Map<String, Map<Int, LiftSetCarry>> = emptyMap(); private set
    private var warnedFor: Long? = null
    private var lastStrapStepAt: Long? = null
    private var scheduledEnd: Long? = null
    private var restJob: Job? = null
    val isActive get() = session?.deviceId == vm.activeStrapId && engine?.isFinished == false
    private fun now() = System.currentTimeMillis() / 1000
    private fun key(device: String) = "noop.activeLiftSession.$device"
    private fun store() = BroopLiftStore(context, session?.deviceId ?: vm.activeStrapId)
    fun resumeSaved() {
        val device = vm.activeStrapId
        if (session?.deviceId == device && current != null) return
        restJob?.cancel(); BroopLiftRestReceiver.cancel(context); BroopLiftRestReceiver.liveWarning = null; scheduledEnd = null; current = null; session = null; pending = emptyMap(); warmups = emptySet(); revision++
        val restored = BroopLiftSnapshot.decode(prefs.getString(key(device), null), now()) ?: return
        if (restored.deviceId != device) return
        vm.viewModelScope.launch {
            val row = runCatching { BroopLiftStore(context, device).sessions().firstOrNull { it.id == restored.sessionId && it.endTs == null } }.getOrNull()
            if (vm.activeStrapId != device || row == null) return@launch
            session = row; current = restored.engine; pending = restored.pending; warmups = restored.warmups
            warnedFor = (restored.engine.stage as? LiftSessionEngine.Stage.Resting)?.endsAt?.takeIf { it - now() <= 5 } ?: restored.warnedFor; lastStrapStepAt = null; revision++; scheduleRest()
            loadPrevious()
        }
    }
    suspend fun attach(row: LiftSessionRow, items: List<LiftProgramItemRow>, exercises: List<LiftExerciseRow>, recorded: List<com.noop.data.LiftSetEntity>) {
        if (session?.id == row.id && current != null) return
        val restored = BroopLiftSnapshot.decode(prefs.getString(key(row.deviceId), null), now())?.takeIf { it.sessionId == row.id && it.deviceId == row.deviceId }
        session = row; pending = restored?.pending.orEmpty(); warmups = restored?.warmups.orEmpty(); warnedFor = restored?.warnedFor
        val plan = if (items.isNotEmpty()) items.map { line ->
            val exercise = exercises.firstOrNull { it.name == line.exercise }
            LiftPlanItem(line.exercise, LiftMuscle.fromRaw(exercise?.primaryMuscle), LiftMuscle.decodeList(exercise?.secondaryMuscles),
                maxOf(1, line.targetSets ?: 1), maxOf(0, line.restSec ?: 120), line.targetRepsLow, line.targetRepsHigh,
                line.targetRpe, line.targetWeightKg, line.note, line.id)
        } else recorded.map { it.exercise }.distinct().map { name ->
            val sets = recorded.filter { it.exercise == name }; val rowSet = sets.first()
            LiftPlanItem(name, LiftMuscle.fromRaw(rowSet.primaryMuscle), LiftMuscle.decodeList(rowSet.secondaryMuscles), sets.maxOf { it.setIndex }) }
        current = restored?.engine ?: LiftSessionEngine(plan, row.startTs,
            sets = recorded.map { set -> LiftRecordedSet(plan.indexOfFirst { it.exercise == set.exercise }, set.setIndex, set.weightKg,
                set.reps, set.rpe, set.isWarmup, set.startTs ?: row.startTs, set.endTs ?: row.startTs, set.restSec) })
        lastStrapStepAt = null; persist(); loadPrevious()
    }
    private suspend fun loadPrevious() {
        val row = session ?: return
        val names = current?.plan?.map { it.exercise }?.distinct().orEmpty()
        val history = names.associateWith { store().lastLiftValues(it, row.startTs) }
        if (session?.id == row.id) { last = history; revision++ }
    }
    fun values(slot: LiftSlot): LiftSetCarry = engine?.let { it.values(slot, last[it.item(slot)?.exercise].orEmpty()) } ?: LiftSetCarry()
    fun entered(slot: LiftSlot) = engine?.recorded(slot)?.let { LiftPendingValues(it.weightKg, it.reps, it.rpe) } ?: pending[slot] ?: LiftPendingValues()
    fun isWarmup(slot: LiftSlot) = engine?.recorded(slot)?.isWarmup ?: (slot in warmups)
    fun update(slot: LiftSlot, input: LiftPendingValues, warmup: Boolean) {
        val engine = current ?: return
        warmups = if (warmup) warmups + slot else warmups - slot
        if (engine.recorded(slot) != null) engine.update(slot, input.weightKg, input.reps, input.rpe, warmup)
        else pending = if (input == LiftPendingValues()) pending - slot else pending + (slot to input)
        persist()
    }
    fun start(slot: LiftSlot) { if (!saving) { current?.start(slot, now()); warnedFor = null; persist() } }
    fun advance(fromStrap: Boolean = false) {
        val engine = current ?: return
        if (!isActive || saving) return
        val stamp = now()
        if (fromStrap && lastStrapStepAt?.let { LiftSessionFinish.isKnock(stamp - it, engine.stage, stamp) } == true) {
            vm.ble.externalLog("Lift double-tap held: under five seconds since last session step"); return
        }
        if (fromStrap) { lastStrapStepAt = stamp; vm.buzz(1, HapticPrefs.WORKOUT) }
        val completing = (engine.stage as? LiftSessionEngine.Stage.Working)?.slot
        engine.advance(stamp)
        if (completing != null) {
            val typed = pending[completing]; val row = engine.recorded(completing)
            if (row != null) engine.update(completing, typed?.weightKg ?: row.weightKg, typed?.reps ?: row.reps,
                typed?.rpe ?: row.rpe, row.isWarmup || completing in warmups)
            pending = pending - completing
        }
        persist()
    }
    fun addSet(index: Int) { if (current?.addSet(index) == true) persist() }
    fun removeSet(index: Int) {
        val engine = current ?: return; val slot = LiftSlot(index, engine.plan.getOrNull(index)?.targetSets ?: return)
        if (engine.removeSet(index)) { pending = pending - slot; warmups = warmups - slot; persist() }
    }
    fun addExercise(name: String, primary: LiftMuscle?, secondary: List<LiftMuscle>) {
        if (name.isBlank()) return
        if (current?.addExercise(LiftPlanItem(name.trim(), primary, secondary.filter { it != primary }, targetRepsLow = 0,
                targetWeightKg = 0.0, programItemId = UUID.randomUUID().toString(), addedInSession = true)) == true) { persist(); vm.viewModelScope.launch { loadPrevious() } }
    }
    fun undo() { if (!saving) { current?.undo(); persist() } }
    suspend fun save(complete: Boolean, keepProgram: Boolean, rpe: Double?, note: String?) {
        if (saving) return
        val original = current ?: return; val row = session ?: return
        saving = true
        try {
            val ended = LiftSessionEngine(original.plan, original.startTs, original.stage, original.sets, original.stageStartedAt)
            ended.finish(now())
            val finished = LiftSessionFinish.setsToSave(ended, pending, warmups, last, complete)
            store().commitSession(row, ended, finished, keepProgram, rpe, note)
            teardown(); vm.loadWorkouts()
        } finally { saving = false }
    }
    suspend fun discard() {
        if (saving) return
        val row = session ?: return
        store().discardSession(row); teardown()
    }
    private fun teardown() {
        session?.let { prefs.edit().remove(key(it.deviceId)).commit() }
        restJob?.cancel(); scheduledEnd = null; current = null; session = null; pending = emptyMap(); warmups = emptySet(); last = emptyMap(); revision++
        BroopLiftRestReceiver.cancel(context); BroopLiftRestReceiver.liveWarning = null
        NotificationManagerCompat.from(context).cancel(6241)
    }
    private fun persist() {
        val engine = current ?: return; val row = session ?: return
        check(prefs.edit().putString(key(row.deviceId), BroopLiftSnapshot.encode(BroopLiftSnapshot.Restored(row.id, row.deviceId,
            engine, pending, warmups, warnedFor))).commit()) { "Lift snapshot could not be saved" }
        revision++; scheduleRest()
    }
    private fun scheduleRest() {
        val end = (current?.stage as? LiftSessionEngine.Stage.Resting)?.endsAt
        if (end == scheduledEnd) return
        restJob?.cancel(); scheduledEnd = end
        BroopLiftRestReceiver.cancel(context)
        if (end == null) { BroopLiftRestReceiver.liveWarning = null; NotificationManagerCompat.from(context).cancel(6241); return }
        val row = session ?: return
        val engine = current ?: return
        val snapshot = BroopLiftSnapshot.Restored(row.id, row.deviceId, engine, pending, warmups, warnedFor)
        BroopLiftRestReceiver.liveWarning = { sessionId, device, expectedEnd ->
            if (session?.id == sessionId && session?.deviceId == device && scheduledEnd == expectedEnd) { fireWarning(expectedEnd); true } else false
        }
        BroopLiftRestReceiver.schedule(context, snapshot, now())
        BroopLiftRestReceiver.show(context, snapshot, end <= now())
        restJob = vm.viewModelScope.launch {
            val (warning, final) = LiftSessionFinish.restEventTimes(end, now())
            delay(maxOf(0L, warning * 1000 - System.currentTimeMillis()))
            if ((current?.stage as? LiftSessionEngine.Stage.Resting)?.endsAt != end) return@launch
            fireWarning(end)
            final?.let { delay(maxOf(0L, it * 1000 - System.currentTimeMillis())); revision++ }
        }
    }
    private fun fireWarning(end: Long) {
        if ((current?.stage as? LiftSessionEngine.Stage.Resting)?.endsAt != end || end - now() > 5) return
        val row = session ?: return
        val persisted = BroopLiftSnapshot.decode(prefs.getString(key(row.deviceId), null), now())
        if (warnedFor == end || persisted?.warnedFor == end) { warnedFor = end; return }
        warnedFor = end; vm.buzz(3, HapticPrefs.WORKOUT); persist()
    }
}
