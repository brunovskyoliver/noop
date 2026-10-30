package com.noop.ui

import android.app.Application
import androidx.room.Room
import com.noop.data.LiftMuscle
import com.noop.data.WhoopDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Exercises the production SQL adapter against Room's real schema, including paired workout writes. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, application = Application::class)
class BroopLiftStoreTest {
    private lateinit var db: WhoopDatabase
    private lateinit var store: BroopLiftStore
    @Before fun createDatabase() {
        db = Room.inMemoryDatabaseBuilder(RuntimeEnvironment.getApplication(), WhoopDatabase::class.java)
            .allowMainThreadQueries().build()
        store = BroopLiftStore(db, "active-strap")
    }
    @After fun closeDatabase() { db.close() }

    @Test fun sessionAndSetsSurviveReopeningAndFinishWithOneManualWorkout() = runBlocking {
        store.start(null)
        val active = BroopLiftStore(db, "active-strap").sessions().single()
        assertNull(active.endTs)
        store.logSet(active, "Bench press", 60.0, 8, 8.0, false, LiftMuscle.chest,
            listOf(LiftMuscle.triceps, LiftMuscle.chest, LiftMuscle.triceps), active.startTs)
        val first = store.sets(active.id).single()
        assertEquals("triceps", first.secondaryMuscles)
        assertEquals("chest", first.primaryMuscle)
        assertEquals(1, first.setIndex)
        store.saveSet(first, 62.5, 7, null, false)
        val edited = store.sets(active.id).single()
        assertEquals(62.5, edited.weightKg!!, 0.0)
        assertEquals(7, edited.reps)
        assertNull(edited.rpe)
        assertEquals(first.primaryMuscle, edited.primaryMuscle)
        store.finish(active, 8.0, "Local session")
        val finished = store.sessions().single()
        assertNotNull(finished.endTs)
        assertEquals(8.0, finished.sessionRpe!!, 0.0)
        db.openHelper.readableDatabase.query("SELECT * FROM workout WHERE deviceId = 'active-strap'").use { cursor ->
            assertEquals(1, cursor.count); assertTrue(cursor.moveToFirst())
            assertEquals(active.startTs, cursor.getLong(cursor.getColumnIndexOrThrow("startTs")))
            assertEquals(finished.endTs, cursor.getLong(cursor.getColumnIndexOrThrow("endTs")))
            assertEquals("manual", cursor.getString(cursor.getColumnIndexOrThrow("source")))
            assertEquals("Local session", cursor.getString(cursor.getColumnIndexOrThrow("notes")))
            assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("strain")))
            assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("avgHr")))
        }
        assertTrue(BroopLiftStore(db, "other-strap").sessions().isEmpty())
    }

    @Test fun deletingAnEarlierSetNeverReusesCompletionOrderOrSetNumber() = runBlocking {
        store.start(null); val session = store.sessions().single()
        repeat(3) { store.logSet(session, "Squat", 80.0, 5, null, false, LiftMuscle.quads, emptyList(), session.startTs) }
        val previous = store.sets(session.id)
        store.deleteSet(previous[1])
        store.logSet(session, "Squat", 85.0, 5, null, false, LiftMuscle.quads, emptyList(), session.startTs)
        val rows = store.sets(session.id)
        assertEquals(listOf(0, 2, 3), rows.map { it.ord })
        assertEquals(listOf(1, 3, 4), rows.map { it.setIndex })
    }

    @Test fun sheetImportCreatesProgramsAndVocabularyInTheCanonicalTables() = runBlocking {
        val bytes = javaClass.getResourceAsStream("/broop_lift_programs.csv")!!.use { it.readBytes() }
        store.importPrograms(BroopLiftProgramImporter.parse(bytes))
        val programs = store.programs().associateBy { it.name }
        assertEquals(setOf("Upper A", "Lower"), programs.keys)
        val upper = programs.getValue("Upper A")
        assertEquals("Build carefully", upper.note)
        assertEquals(listOf("Bench press", "Row", "Fly"), store.items(upper.id).map { it.exercise })
        assertEquals("chest", store.exercises().first { it.name == "Bench press" }.primaryMuscle)
        assertTrue(store.sessions().isEmpty())
        store.archiveProgram(upper)
        assertEquals(listOf("Lower"), store.programs().map { it.name })
        assertEquals(3, store.items(upper.id).size)
    }
    @Test fun finishingPlanKeepsCompletionOrderAndUntimedDiscardedSlotsAndUpdatesHeaviestProgramTarget() = runBlocking {
        val item = com.noop.data.LiftProgramItemRow("line", "active-strap", "", 0, "Squat", 3, 8, 10,
            targetRpe = 8.0, targetWeightKg = 50.0, restSec = 60)
        val programId = store.saveProgram(null, "Legs", listOf(item))
        val program = store.programs().single()
        store.start(program); val active = store.sessions().single()
        val plan = listOf(com.noop.analytics.LiftPlanItem("Squat", LiftMuscle.quads, targetSets = 3, restSec = 60,
            targetRepsLow = 8, targetRpe = 8.0, targetWeightKg = 50.0, programItemId = "line"))
        val engine = com.noop.analytics.LiftSessionEngine(plan, active.startTs)
        val slot = com.noop.analytics.LiftSlot(0, 2)
        engine.start(slot, active.startTs + 10); engine.advance(active.startTs + 40)
        engine.update(slot, 60.0, 12, null, false)
        engine.addSet(0); engine.finish(active.startTs + 60)
        val finished = com.noop.analytics.LiftSessionFinish.setsToSave(engine, emptyMap(), emptySet(), emptyMap(), false)
        store.commitSession(active, engine, finished, true, 8.5, "Done")
        val saved = store.sets(active.id)
        assertEquals(listOf(2, 1, 3, 4), saved.map { it.setIndex })
        assertEquals(20, saved.first().restSec)
        assertEquals(8.0, saved.first().rpe!!, 0.0)
        assertTrue(saved.drop(1).all { it.reps == 0 && it.weightKg == 0.0 && it.startTs == null && it.endTs == null && it.restSec == null })
        val updated = store.items(programId).single()
        assertEquals(4, updated.targetSets)
        assertEquals(60.0, updated.targetWeightKg!!, 0.0)
        assertEquals(12, updated.targetRepsLow)
        assertNull(updated.targetRepsHigh)
        assertNotNull(store.sessions().single().endTs)
        db.openHelper.readableDatabase.query("SELECT COUNT(*) FROM workout").use { it.moveToFirst(); assertEquals(1, it.getInt(0)) }
    }
    @Test fun discardingEveryUnstartedSlotSavesNeitherSessionNorWorkout() = runBlocking {
        store.start(null); val active = store.sessions().single()
        val engine = com.noop.analytics.LiftSessionEngine(listOf(com.noop.analytics.LiftPlanItem("Curl", targetSets = 2,
            targetWeightKg = 10.0, targetRepsLow = 12)), active.startTs)
        engine.finish(active.startTs + 20)
        store.commitSession(active, engine, com.noop.analytics.LiftSessionFinish.setsToSave(engine, emptyMap(), emptySet(), emptyMap(), false), false, null, null)
        assertTrue(store.sessions().isEmpty())
        assertTrue(store.sets(active.id).isEmpty())
        db.openHelper.readableDatabase.query("SELECT COUNT(*) FROM workout").use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
    }

    @Test fun previousSetCarrySearchesAllHistoryAndSkipsDiscardedRowsAndOtherStraps() = runBlocking {
        val sql = db.openHelper.writableDatabase
        fun session(id: String, start: Long, device: String = "active-strap") {
            sql.execSQL("INSERT INTO liftSession(id,deviceId,startTs,endTs,sport) VALUES(?,?,?,?,?)", arrayOf(id, device, start, start + 10, "strength"))
        }
        fun set(id: String, session: String, weight: Double, reps: Int, device: String = "active-strap") {
            sql.execSQL("INSERT INTO liftSet(id,deviceId,sessionId,ord,exercise,setIndex,weightKg,reps,isWarmup) VALUES(?,?,?,?,?,?,?,?,?)",
                arrayOf(id, device, session, 0, "Press", 1, weight, reps, 0))
        }
        session("old", 100); set("performed", "old", 52.5, 8)
        repeat(101) { session("unrelated-$it", 200L + it) }
        session("discarded", 500); set("discard", "discarded", 999.0, 0)
        session("foreign", 600, "other-strap"); set("foreign-set", "foreign", 200.0, 20, "other-strap")
        assertEquals(mapOf(1 to com.noop.analytics.LiftSetCarry(52.5, 8)), store.lastLiftValues("Press", 1000))
        assertTrue(store.lastLiftValues("Press", 100).isEmpty())
    }

}
