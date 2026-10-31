package com.noop.ui

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import com.noop.analytics.*
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class BroopLiftSnapshotTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun snapshot(): BroopLiftSnapshot.Restored {
        val now = System.currentTimeMillis() / 1000
        val engine = LiftSessionEngine(listOf(LiftPlanItem("Press", targetSets = 3, restSec = 120, targetWeightKg = 50.0, targetRepsLow = 8)), now - 100)
        engine.start(LiftSlot(0, 1), now - 80); engine.advance(now - 40)
        engine.update(LiftSlot(0, 1), 52.5, 8, null, false)
        return BroopLiftSnapshot.Restored("session", "strap", engine, mapOf(LiftSlot(0, 2) to LiftPendingValues(55.0, 7, 9.0)), setOf(LiftSlot(0, 3)), null)
    }
    @After fun clear() {
        BroopLiftRestReceiver.liveWarning = null
        BroopLiftRestReceiver.cancel(context)
        NoopPrefs.of(context).edit().clear().commit()
        context.getSystemService(NotificationManager::class.java).cancelAll()
    }
    @Test fun processRestartRestoresAbsoluteRestPlanTypedPendingNumbersAndWarmupsWithoutUndoHistory() {
        val original = snapshot()
        val restored = BroopLiftSnapshot.decode(BroopLiftSnapshot.encode(original), System.currentTimeMillis() / 1000)!!
        assertEquals(original.sessionId, restored.sessionId)
        assertEquals(original.deviceId, restored.deviceId)
        assertEquals(original.engine.plan, restored.engine.plan)
        assertEquals(original.engine.stage, restored.engine.stage)
        assertEquals(original.engine.sets, restored.engine.sets)
        assertEquals(original.engine.stageStartedAt, restored.engine.stageStartedAt)
        assertEquals(original.pending, restored.pending)
        assertEquals(original.warmups, restored.warmups)
        assertFalse(restored.engine.canUndo)
        val rest = restored.engine.stage as LiftSessionEngine.Stage.Resting
        assertEquals(0L, restored.engine.restRemaining(rest.endsAt + 3600))
        restored.engine.advance(rest.endsAt + 10)
        assertEquals(LiftSessionEngine.Stage.Working(LiftSlot(0, 2)), restored.engine.stage)
        assertEquals(130, restored.engine.sets.single().restSec)
    }
    @Test fun freeWarmupWithNoExerciseYetSurvivesProcessRestart() {
        val now = System.currentTimeMillis() / 1000
        val free = BroopLiftSnapshot.Restored("free", "strap", LiftSessionEngine(emptyList(), now - 60), emptyMap(), emptySet(), null)
        val resumed = BroopLiftSnapshot.decode(BroopLiftSnapshot.encode(free), now)!!
        assertEquals("free", resumed.sessionId)
        assertTrue(resumed.engine.plan.isEmpty())
        assertEquals(LiftSessionEngine.Stage.Warmup, resumed.engine.stage)
        assertEquals(now - 60, resumed.engine.startTs)
        val invalid = free.copy(engine = LiftSessionEngine(emptyList(), now - 60, LiftSessionEngine.Stage.Working(LiftSlot(0, 1))))
        assertNull(BroopLiftSnapshot.decode(BroopLiftSnapshot.encode(invalid), now))
    }
    @Test fun unknownStageRecoversCompletedSetsAndCorruptOrOversizedSnapshotsCannotReviveASession() {
        val raw = JSONObject(BroopLiftSnapshot.encode(snapshot()))
        raw.put("stage", JSONObject().put("kind", "future-stage"))
        val restored = BroopLiftSnapshot.decode(raw.toString(), System.currentTimeMillis() / 1000)!!
        assertEquals(LiftSessionEngine.Stage.Warmup, restored.engine.stage)
        assertEquals(1, restored.engine.sets.size)
        assertEquals(LiftSlot(0, 2), restored.engine.nextPendingSlot)
        assertNull(BroopLiftSnapshot.decode("garbage", 2_000_000_000))
        raw.put("startSec", 0)
        assertNull(BroopLiftSnapshot.decode(raw.toString(), 2_000_000_000))
    }
    @Test fun staleSessionOrRestAlarmCannotNotifyButMatchingAlarmSurvivesWithoutController() {
        val base = snapshot()
        val now = System.currentTimeMillis() / 1000
        val rest = base.engine.stage as LiftSessionEngine.Stage.Resting
        val engine = LiftSessionEngine(base.engine.plan, base.engine.startTs,
            LiftSessionEngine.Stage.Resting(rest.slot, now - 1), base.engine.sets, base.engine.stageStartedAt)
        val value = base.copy(engine = engine)
        NoopPrefs.of(context).edit().putString("noop.activeLiftSession.strap", BroopLiftSnapshot.encode(value)).commit()
        assertFalse(BroopLiftRestReceiver.matches(value, "old-session", "strap", now - 1))
        assertFalse(BroopLiftRestReceiver.matches(value, "session", "other-strap", now - 1))
        assertFalse(BroopLiftRestReceiver.matches(value, "session", "strap", now - 2))
        val intent = Intent(context, BroopLiftRestReceiver::class.java).setAction("com.noop.LIFT_REST_END")
            .putExtra("session", "old-session").putExtra("device", "strap").putExtra("end", now - 1)
        val manager = context.getSystemService(NotificationManager::class.java)
        BroopLiftRestReceiver().onReceive(context, intent)
        assertNull(shadowOf(manager).getNotification(6241))
        BroopLiftRestReceiver().onReceive(context, intent.putExtra("session", "session"))
        val ready = shadowOf(manager).getNotification(6241)
        assertNotNull(ready)
        assertEquals(context.getString(com.noop.R.string.broop_lift_rest_ready), ready.extras.getString(Notification.EXTRA_TEXT))
        assertEquals(0, ready.flags and Notification.FLAG_ONGOING_EVENT)
    }
}
