package com.noop.analytics

import com.noop.data.LiftProgramItemRow
import org.junit.Assert.*
import org.junit.Test

class LiftSessionParityOracleTest {
    private fun n(value: Any?) = value?.toString() ?: "-"
    private fun slot(value: LiftSlot?) = value?.let { "${it.exerciseIndex}.${it.setIndex}" } ?: "-"
    private fun stage(value: LiftSessionEngine.Stage): String = when (value) {
        LiftSessionEngine.Stage.Warmup -> "warmup"
        LiftSessionEngine.Stage.Finished -> "finished"
        is LiftSessionEngine.Stage.Working -> "work:" + slot(value.slot)
        is LiftSessionEngine.Stage.Resting -> "rest:" + slot(value.slot) + ":${value.endsAt}"
    }
    /** Expected literal is verbatim stdout from broop_lift_session_oracle.py compiling production Swift. */
    @Test fun exactSwiftTransitionsCarryFinishProgramAndGestureGates() {
        val out = mutableListOf<String>()
        fun emit(tag: String, e: LiftSessionEngine) {
            val rows = e.sets.joinToString(";") { "${slot(it.slot)}:${n(it.weightKg)}:${n(it.reps)}:${n(it.rpe)}:${if (it.isWarmup) 1 else 0}:${it.startTs}:${it.endTs}:${n(it.restSec)}" }
            out += "$tag|${stage(e.stage)}|${e.stageStartedAt}|${slot(e.nextPendingSlot)}|${slot(e.upcomingSlot)}|${e.plan.joinToString(",") { it.targetSets.toString() }}|$rows"
        }
        val plan = listOf(LiftPlanItem("Squat", targetSets = 2, restSec = 60, targetRepsLow = 10, targetRpe = 8.0, targetWeightKg = 50.0, programItemId = "a"),
            LiftPlanItem("Row", targetSets = 2, restSec = 0, targetRepsLow = 8, targetWeightKg = 40.0, programItemId = "b"))
        val e = LiftSessionEngine(plan, 100)
        emit("initial", e)
        e.start(LiftSlot(1, 1), 110); emit("skip", e)
        e.advance(130); emit("done", e)
        e.update(LiftSlot(1, 1), 42.5, 9, 7.0, false)
        e.advance(131); emit("same-machine", e)
        val carry = e.carry(LiftSlot(1, 2), emptyMap()); out += "carry|${n(carry.weightKg)}|${n(carry.reps)}"
        e.advance(150); e.advance(151); emit("return", e)
        e.addSet(0); emit("add", e)
        e.removeSet(0); emit("remove", e)
        e.undo(); emit("undo-count", e)
        e.start(LiftSlot(1, 1), 170); emit("redo", e)
        e.undo(); emit("undo-redo", e)
        e.advance(190); emit("rest", e)
        out += "remaining|${n(e.restRemaining(200))}|${n(e.restRemaining(300))}"
        e.finish(205); emit("finish", e)
        e.undo(); emit("undo-finish", e)
        for (elapsed in listOf(-1L, 0L, 1L, 4L, 5L, 6L)) for (end in listOf(90L, 100L, 101L, 200L)) {
            out += "knock|$elapsed|$end|${if (LiftSessionFinish.isKnock(elapsed, LiftSessionEngine.Stage.Resting(LiftSlot(0, 1), end), 100)) 1 else 0}"
        }
        for (end in listOf(0L, 100L, 101L, 104L, 105L, 120L)) {
            val times = LiftSessionFinish.restEventTimes(end, 100); out += "times|$end|${times.first}|${n(times.second)}"
        }
        val pending = mapOf(LiftSlot(0, 2) to LiftPendingValues(55.0, 12))
        val warmup = setOf(LiftSlot(0, 3))
        for (complete in listOf(false, true)) {
            val sets = LiftSessionFinish.setsToSave(e, pending, warmup, emptyMap(), complete)
            out += "save|${if (complete) 1 else 0}|" + sets.joinToString(";") { "${slot(it.slot)}:${n(it.weightKg)}:${n(it.reps)}:${n(it.rpe)}:${if (it.isWarmup) 1 else 0}:${n(it.startTs)}:${n(it.endTs)}:${n(it.restSec)}" }
            val items = listOf(LiftProgramItemRow("a", "d", "p", 0, "Squat", 2, 10, 11, 8.0, 50.0, 60),
                LiftProgramItemRow("b", "d", "p", 1, "Row", 2, 8, targetWeightKg = 40.0, restSec = 0))
            for (keep in listOf(false, true)) {
                val lines = LiftSessionFinish.programAfterSession(sets, e.plan, items, keep, "p", "d")
                out += "program|${if (complete) 1 else 0}|${if (keep) 1 else 0}|" + lines.joinToString(";") { "${it.id}:${n(it.targetSets)}:${n(it.targetRepsLow)}:${n(it.targetRepsHigh)}:${n(it.targetWeightKg)}" }
            }
        }
        val expected = """
initial|warmup|100|0.1|0.1|2,2|
skip|work:1.1|110|0.1|1.2|2,2|
done|rest:1.1:130|130|0.1|1.2|2,2|1.1:-:-:-:0:110:130:-
same-machine|work:1.2|131|0.1|0.1|2,2|1.1:42.5:9:7.0:0:110:130:1
carry|42.5|9
return|work:0.1|151|0.1|0.2|2,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1
add|work:0.1|151|0.1|0.2|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1
remove|work:0.1|151|0.1|0.2|2,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1
undo-count|work:0.1|151|0.1|0.2|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1
redo|work:1.1|170|0.1|0.1|3,2|1.2:-:-:-:0:131:150:1
undo-redo|work:0.1|151|0.1|0.2|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1
rest|rest:0.1:250|190|0.2|0.2|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1;0.1:-:-:-:0:151:190:-
remaining|50|0
finish|finished|205|0.2|-|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1;0.1:-:-:-:0:151:190:15
undo-finish|rest:0.1:250|190|0.2|0.2|3,2|1.1:42.5:9:7.0:0:110:130:1;1.2:-:-:-:0:131:150:1;0.1:-:-:-:0:151:190:-
knock|-1|90|0
knock|-1|100|0
knock|-1|101|0
knock|-1|200|0
knock|0|90|0
knock|0|100|0
knock|0|101|1
knock|0|200|1
knock|1|90|0
knock|1|100|0
knock|1|101|1
knock|1|200|1
knock|4|90|0
knock|4|100|0
knock|4|101|1
knock|4|200|1
knock|5|90|0
knock|5|100|0
knock|5|101|0
knock|5|200|0
knock|6|90|0
knock|6|100|0
knock|6|101|0
knock|6|200|0
times|0|101|-
times|100|101|-
times|101|101|101
times|104|101|104
times|105|101|105
times|120|115|120
save|0|1.1:42.5:9:7.0:0:110:130:1;1.2:42.5:9:-:0:131:150:1;0.1:50.0:10:8.0:0:151:190:-;0.2:0.0:0:-:0:-:-:-;0.3:0.0:0:-:1:-:-:-
program|0|0|a:2:10:11:50.0;b:2:9:-:42.5
program|0|1|a:3:10:11:50.0;b:2:9:-:42.5
save|1|1.1:42.5:9:7.0:0:110:130:1;1.2:42.5:9:-:0:131:150:1;0.1:50.0:10:8.0:0:151:190:-;0.2:55.0:12:8.0:0:-:-:-;0.3:50.0:10:8.0:1:-:-:-
program|1|0|a:2:10:11:50.0;b:2:9:-:42.5
program|1|1|a:3:10:11:50.0;b:2:9:-:42.5
""".trimIndent()

        assertEquals(expected, out.joinToString("\n"))
    }
    @Test fun completedOrCurrentSlotsCannotBeRemovedAndCapsCannotLoseRecords() {
        val e = LiftSessionEngine(listOf(LiftPlanItem("Curl", targetSets = 2)), 100)
        e.start(LiftSlot(0, 2), 110)
        assertFalse(e.removeSet(0))
        e.advance(130)
        assertFalse(e.removeSet(0))
        repeat(30) { e.addSet(0) }
        assertEquals(20, e.plan.single().targetSets)
        assertEquals(1, e.sets.size)
        repeat(200) { e.addExercise(LiftPlanItem("Extra", targetSets = 10)) }
        assertEquals(200, e.plan.size)
        assertTrue(e.plan.drop(1).all { it.targetSets == 1 })
    }
    @Test fun addingAnExerciseUpdatesOnlyItsOwnProgramWhenChosenAndNeverInventsTiming() {
        val e = LiftSessionEngine(listOf(LiftPlanItem("A", programItemId = "a")), 100)
        e.addExercise(LiftPlanItem("B", targetRepsLow = 0, targetWeightKg = 0.0, programItemId = "b", addedInSession = true))
        val saved = LiftSessionFinish.setsToSave(e, mapOf(LiftSlot(1,1) to LiftPendingValues(30.0, 10)), emptySet(), emptyMap(), true)
        assertTrue(saved.all { it.startTs == null && it.endTs == null && it.restSec == null })
        val original = listOf(LiftProgramItemRow("a", "d", "p", 0, "A"))
        assertEquals(original, LiftSessionFinish.programAfterSession(saved, e.plan, original, false, "p", "d"))
        val added = LiftSessionFinish.programAfterSession(saved, e.plan, original, true, "p", "d").last()
        assertEquals("B", added.exercise)
        assertEquals(0.0, added.targetWeightKg!!, 0.0)
        assertEquals(0, added.targetRepsLow)
        assertNull(added.targetRpe)
    }
}
