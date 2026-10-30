package com.noop.data

import android.app.Application
import androidx.room.Room
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** The displayed bridged night is one edit, including its tombstones and original source IDs. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, application = Application::class)
class BroopSleepGroupTransactionTest {
    private lateinit var db: WhoopDatabase
    private lateinit var repo: WhoopRepository
    private val fragments = listOf(SleepSession("a-noop", 1_000, 2_000, stagesJSON = "[]"),
        SleepSession("b-noop", 2_100, 3_000, startTsAdjusted = 2_050))
    @Before fun open() {
        db = Room.inMemoryDatabaseBuilder(RuntimeEnvironment.getApplication(), WhoopDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = WhoopRepository(db)
        runBlocking { repo.upsertSleepSessions(fragments) }
    }
    @After fun close() { db.close() }
    private fun count(table: String): Int = db.openHelper.readableDatabase.query("SELECT COUNT(*) FROM $table").use {
        check(it.moveToFirst()); it.getInt(0)
    }
    @Test fun deleteAndUndoRestoreBothFragmentsAndOriginalNamespaces() = runBlocking {
        repo.deleteSleepSessions(fragments + fragments.first())
        assertEquals(0, count("sleepSession"))
        assertEquals(2, count("dismissedSleep"))
        repo.undoDeleteSleepSessions(fragments)
        assertEquals(2, count("sleepSession"))
        assertEquals(0, count("dismissedSleep"))
        for (s in fragments) assertEquals(listOf(s), db.whoopDao().sleepSessions(s.deviceId, 0, 5_000, 100))
    }
    @Test fun failedSecondDeleteRollsBackFirstFragmentAndEveryTombstone() = runBlocking {
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER fail_sleep_delete BEFORE DELETE ON sleepSession WHEN OLD.startTs = 2100 BEGIN SELECT RAISE(ABORT, 'test deletion failure'); END")
        try { repo.deleteSleepSessions(fragments); fail("expected failure") } catch (_: android.database.SQLException) { }
        assertEquals(2, count("sleepSession"))
        assertEquals(0, count("dismissedSleep"))
    }
    @Test fun failedSecondRestoreKeepsBothTombstonesAndNoPartialNight() = runBlocking {
        repo.deleteSleepSessions(fragments)
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER fail_sleep_restore BEFORE INSERT ON sleepSession WHEN NEW.startTs = 2100 BEGIN SELECT RAISE(ABORT, 'test restore failure'); END")
        try { repo.undoDeleteSleepSessions(fragments); fail("expected failure") } catch (_: android.database.SQLException) { }
        assertEquals(0, count("sleepSession"))
        assertEquals(2, count("dismissedSleep"))
    }
}
