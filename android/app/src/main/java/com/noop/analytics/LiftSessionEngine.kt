package com.noop.analytics

import com.noop.data.LiftMuscle
import com.noop.data.LiftProgramItemRow

internal data class LiftSlot(val exerciseIndex: Int, val setIndex: Int)
internal data class LiftPlanItem(
    val exercise: String, val primaryMuscle: LiftMuscle? = null, val secondaryMuscles: List<LiftMuscle> = emptyList(),
    val targetSets: Int = 1, val restSec: Int = 120, val targetRepsLow: Int? = null, val targetRepsHigh: Int? = null,
    val targetRpe: Double? = null, val targetWeightKg: Double? = null, val note: String? = null,
    val programItemId: String? = null, val addedInSession: Boolean = false,
) {
    fun normalized() = copy(targetSets = maxOf(1, targetSets), restSec = maxOf(0, restSec))
}
internal data class LiftRecordedSet(val exerciseIndex: Int, val setIndex: Int, val weightKg: Double? = null,
    val reps: Int? = null, val rpe: Double? = null, val isWarmup: Boolean = false, val startTs: Long,
    val endTs: Long, val restSec: Int? = null) {
    val slot get() = LiftSlot(exerciseIndex, setIndex)
}
internal data class LiftSetCarry(val weightKg: Double? = null, val reps: Int? = null)

/** Swift twin `LiftSessionEngine`: absolute time and completion order survive an occupied machine. */
internal class LiftSessionEngine(plan: List<LiftPlanItem>, val startTs: Long,
    stage: Stage = Stage.Warmup, sets: List<LiftRecordedSet> = emptyList(), stageStartedAt: Long = startTs) {
    sealed interface Stage {
        data object Warmup : Stage
        data class Working(val slot: LiftSlot) : Stage
        data class Resting(val slot: LiftSlot, val endsAt: Long) : Stage
        data object Finished : Stage
    }
    var plan = plan.map { it.normalized() }; private set
    var stage = stage; private set
    var sets = sets; private set
    var stageStartedAt = stageStartedAt; private set
    private data class Snapshot(val plan: List<LiftPlanItem>, val stage: Stage, val sets: List<LiftRecordedSet>, val at: Long)
    private val history = mutableListOf<Snapshot>()
    /** Swift twin `LiftSessionEngine.slots(forExercise:)`. */
    fun slots(index: Int): List<LiftSlot> = plan.getOrNull(index)?.let { line -> (1..line.targetSets).map { LiftSlot(index, it) } }.orEmpty()
    val allSlots get() = plan.indices.flatMap(::slots)
    /** Swift twin `LiftSessionEngine.recordedSet(for:)`. */
    fun recorded(slot: LiftSlot) = sets.firstOrNull { it.slot == slot }
    /** Swift twin `LiftSessionEngine.isCompleted(_:)`. */
    fun completed(slot: LiftSlot) = recorded(slot) != null
    val currentSlot get() = when (val value = stage) { is Stage.Working -> value.slot; is Stage.Resting -> value.slot; else -> null }
    val nextPendingSlot get() = allSlots.firstOrNull { !completed(it) }
    /** Swift twin `LiftSessionEngine.slotAfter(_:)`. */
    fun slotAfter(slot: LiftSlot) = slots(slot.exerciseIndex).firstOrNull { !completed(it) } ?: nextPendingSlot
    val upcomingSlot get() = when (stage) {
        Stage.Warmup -> nextPendingSlot
        Stage.Finished -> null
        else -> currentSlot?.let { slot -> slots(slot.exerciseIndex).firstOrNull { !completed(it) && it != slot }
            ?: allSlots.firstOrNull { !completed(it) && it != slot } }
    }
    val allCompleted get() = nextPendingSlot == null
    val isFinished get() = stage == Stage.Finished
    val canUndo get() = history.isNotEmpty()
    val plannedWorkingSets get() = plan.sumOf { it.targetSets }
    val completedWorkingSets get() = sets.count { !it.isWarmup }
    val unperformedSlots get() = allSlots.filter { !completed(it) }
    /** Swift twin `LiftSessionEngine.planItem(for:)`. */
    fun item(slot: LiftSlot) = plan.getOrNull(slot.exerciseIndex)
    /** Swift twin `LiftSessionEngine.restRemaining(now:)`. */
    fun restRemaining(now: Long) = (stage as? Stage.Resting)?.let { maxOf(0L, it.endsAt - now) }
    /** Swift twin `LiftSessionEngine.previousSetInSession(for:)`. */
    fun previous(slot: LiftSlot) = (1 until maxOf(1, slot.setIndex)).reversed().firstNotNullOfOrNull { recorded(LiftSlot(slot.exerciseIndex, it)) }
    /** Swift twin `LiftSessionEngine.carry(for:lastSession:)`. */
    fun carry(slot: LiftSlot, last: Map<Int, LiftSetCarry>): LiftSetCarry {
        val previous = previous(slot)?.let { values(it.slot, last) }; val old = last[slot.setIndex]; val line = item(slot)
        return LiftSetCarry(previous?.weightKg ?: old?.weightKg ?: line?.targetWeightKg,
            previous?.reps ?: old?.reps ?: line?.targetRepsLow)
    }
    /** Swift twin `LiftSessionEngine.values(of:lastSession:)`. */
    fun values(slot: LiftSlot, last: Map<Int, LiftSetCarry>): LiftSetCarry {
        val grey = carry(slot, last); val set = recorded(slot)
        return LiftSetCarry(set?.weightKg ?: grey.weightKg, set?.reps ?: grey.reps)
    }
    /** Swift twin `LiftSessionEngine.start(_:now:)`. */
    fun start(slot: LiftSlot, now: Long) {
        if (item(slot) == null) return
        pushHistory(); sets = sets.filter { it.slot != slot }; stage = Stage.Working(slot); stageStartedAt = now
    }
    /** Swift twin `LiftSessionEngine.advance(now:)`. */
    fun advance(now: Long) {
        when (val value = stage) {
            Stage.Warmup -> nextPendingSlot?.let { start(it, now) }
            is Stage.Working -> {
                pushHistory()
                sets = sets + LiftRecordedSet(value.slot.exerciseIndex, value.slot.setIndex, startTs = stageStartedAt, endTs = now)
                stage = Stage.Resting(value.slot, now + (item(value.slot)?.restSec ?: 120)); stageStartedAt = now
            }
            is Stage.Resting -> {
                pushHistory(); sets = sets.map { if (it.slot == value.slot) it.copy(restSec = maxOf(0L, now - stageStartedAt).toInt()) else it }
                stage = slotAfter(value.slot)?.let { Stage.Working(it) } ?: Stage.Resting(value.slot, now)
                stageStartedAt = now
            }
            Stage.Finished -> Unit
        }
    }
    /** Swift twin `LiftSessionEngine.updateSet(_:weightKg:reps:rpe:isWarmup:)`. */
    fun update(slot: LiftSlot, weight: Double?, reps: Int?, rpe: Double?, warmup: Boolean) {
        sets = sets.map { if (it.slot == slot) it.copy(weightKg = weight, reps = reps, rpe = rpe, isWarmup = warmup) else it }
    }
    /** Swift twin `LiftSessionEngine.addSet(toExercise:)`. */
    fun addSet(index: Int): Boolean {
        val line = plan.getOrNull(index) ?: return false
        if (line.targetSets >= 20) return false
        pushHistory(); plan = plan.mapIndexed { i, item -> if (i == index) item.copy(targetSets = item.targetSets + 1) else item }; return true
    }
    /** Swift twin `LiftSessionEngine.canRemoveSet(fromExercise:)`. */
    fun canRemoveSet(index: Int): Boolean {
        val line = plan.getOrNull(index) ?: return false; val last = LiftSlot(index, line.targetSets)
        return line.targetSets > 1 && !completed(last) && currentSlot != last
    }
    /** Swift twin `LiftSessionEngine.removeSet(fromExercise:)`. */
    fun removeSet(index: Int): Boolean {
        if (!canRemoveSet(index)) return false
        pushHistory(); plan = plan.mapIndexed { i, item -> if (i == index) item.copy(targetSets = item.targetSets - 1) else item }; return true
    }
    /** Swift twin `LiftSessionEngine.addExercise(_:)`. */
    fun addExercise(item: LiftPlanItem): Boolean {
        if (isFinished || plan.size >= 200) return false
        pushHistory(); plan = plan + item.normalized().copy(targetSets = 1); return true
    }
    /** Swift twin `LiftSessionEngine.finish(now:)`. */
    fun finish(now: Long) {
        if (isFinished) return
        pushHistory()
        (stage as? Stage.Resting)?.let { rest -> sets = sets.map {
            if (it.slot == rest.slot && it.restSec == null) it.copy(restSec = maxOf(0L, now - stageStartedAt).toInt()) else it
        } }
        stage = Stage.Finished; stageStartedAt = now
    }
    /** Swift twin `LiftSessionEngine.undo()`. */
    fun undo() {
        val old = history.removeLastOrNull() ?: return
        plan = old.plan; stage = old.stage; sets = old.sets; stageStartedAt = old.at
    }
    /** Swift twin `LiftSessionEngine.pushHistory()`. */
    private fun pushHistory() { history.add(Snapshot(plan, stage, sets, stageStartedAt)) }
}

internal data class LiftPendingValues(val weightKg: Double? = null, val reps: Int? = null, val rpe: Double? = null)
internal data class LiftFinishedSet(val slot: LiftSlot, val weightKg: Double?, val reps: Int?, val rpe: Double?,
    val isWarmup: Boolean, val startTs: Long?, val endTs: Long?, val restSec: Int?)
internal data class LiftSetCountChange(val itemId: String, val exercise: String, val from: Int, val to: Int)
internal object LiftSessionFinish {
    /** Swift twin `LiftSessionController.setsToSave(completingUnfinished:)`. */
    fun setsToSave(engine: LiftSessionEngine, pending: Map<LiftSlot, LiftPendingValues>, warmups: Set<LiftSlot>,
        last: Map<String, Map<Int, LiftSetCarry>>, completingUnfinished: Boolean): List<LiftFinishedSet> {
        fun lastFor(slot: LiftSlot) = last[engine.item(slot)?.exercise].orEmpty()
        return engine.sets.map { set ->
            val shown = engine.values(set.slot, lastFor(set.slot))
            LiftFinishedSet(set.slot, shown.weightKg, shown.reps, set.rpe ?: engine.item(set.slot)?.targetRpe,
                set.isWarmup, set.startTs, set.endTs, set.restSec)
        } + engine.unperformedSlots.map { slot ->
            val typed = pending[slot]; val grey = engine.carry(slot, lastFor(slot))
            LiftFinishedSet(slot, if (completingUnfinished) typed?.weightKg ?: grey.weightKg else 0.0,
                if (completingUnfinished) typed?.reps ?: grey.reps else 0,
                if (completingUnfinished) typed?.rpe ?: engine.item(slot)?.targetRpe else null,
                slot in warmups, null, null, null)
        }
    }
    /** Swift twin `LiftSessionController.anyPerformed(_:)`. */
    fun anyPerformed(sets: List<LiftFinishedSet>) = sets.any { LiftMetrics.isPerformed(it.reps) }
    /** Swift twin `LiftSessionController.setCountChanges(plan:program:)`. */
    fun changes(plan: List<LiftPlanItem>, items: List<LiftProgramItemRow>): List<LiftSetCountChange> {
        val byId = items.groupBy { it.id }.mapValues { it.value.first() }
        return plan.mapNotNull { line -> val row = byId[line.programItemId] ?: return@mapNotNull null
            val saved = maxOf(1, row.targetSets ?: 1)
            if (saved == line.targetSets) null else LiftSetCountChange(row.id, line.exercise, saved, line.targetSets) }
    }
    /** Swift twin `LiftSessionController.applyingHeaviestSets(_:plan:to:)`. */
    fun applyingHeaviest(sets: List<LiftFinishedSet>, plan: List<LiftPlanItem>, items: List<LiftProgramItemRow>): List<LiftProgramItemRow> {
        val heaviest = mutableMapOf<String, LiftFinishedSet>()
        for (set in sets.filter { it.startTs != null && !it.isWarmup && LiftMetrics.isPerformed(it.reps) }) {
            val id = plan.getOrNull(set.slot.exerciseIndex)?.programItemId ?: continue
            val best = heaviest[id]
            if (best != null && !heavier(set, best)) continue
            heaviest[id] = set
        }
        return items.map { row -> heaviest[row.id]?.let { top -> row.copy(targetWeightKg = top.weightKg ?: row.targetWeightKg,
            targetRepsLow = top.reps ?: row.targetRepsLow,
            targetRepsHigh = if (top.reps != null && row.targetRepsHigh != null && row.targetRepsHigh < top.reps) null else row.targetRepsHigh) } ?: row }
    }
    /** Swift twin `LiftSessionController.isHeavier(_:than:)`. */
    private fun heavier(a: LiftFinishedSet, b: LiftFinishedSet) = if ((a.weightKg ?: -1.0) != (b.weightKg ?: -1.0))
        (a.weightKg ?: -1.0) > (b.weightKg ?: -1.0) else (a.reps ?: -1) > (b.reps ?: -1)
    /** Swift twin `LiftSessionController.programAfterSession(_:plan:program:keepingChanges:programId:deviceId:)`. */
    fun programAfterSession(sets: List<LiftFinishedSet>, plan: List<LiftPlanItem>, items: List<LiftProgramItemRow>,
        keepingChanges: Boolean, programId: String, deviceId: String): List<LiftProgramItemRow> {
        var lines = items
        if (keepingChanges) {
            val changes = changes(plan, items).associate { it.itemId to it.to }
            lines = lines.map { row -> changes[row.id]?.let { row.copy(targetSets = it) } ?: row }
            val next = (items.maxOfOrNull { it.ord } ?: -1) + 1
            plan.filter { it.addedInSession }.forEachIndexed { offset, line ->
                val id = line.programItemId ?: return@forEachIndexed
                if (lines.none { it.id == id }) lines = lines + LiftProgramItemRow(id, deviceId, programId, next + offset,
                    line.exercise, line.targetSets, 0, targetWeightKg = 0.0)
            }
        }
        return applyingHeaviest(sets, plan, lines)
    }
    /** Swift twin `LiftSessionController.isKnock(secondsSinceLastStep:stage:now:)`. */
    fun isKnock(secondsSinceLastStep: Long, stage: LiftSessionEngine.Stage, now: Long): Boolean {
        if (secondsSinceLastStep !in 0L..4L) return false
        return !(stage is LiftSessionEngine.Stage.Resting && stage.endsAt <= now)
    }
    /** Swift twin `LiftSessionController.restEventTimes(endsAt:now:)`. */
    fun restEventTimes(endsAt: Long, now: Long) = maxOf(now + 1, endsAt - 5) to endsAt.takeIf { it > now }
}
