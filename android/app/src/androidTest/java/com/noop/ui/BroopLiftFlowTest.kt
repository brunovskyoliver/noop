package com.noop.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewModelScope
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.IdlingPolicies
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.noop.NoopApplication
import com.noop.R
import com.noop.analytics.LiftSessionEngine
import com.noop.data.DemoSeeder
import com.noop.data.WhoopDatabase
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

/** Drives the shipped strength controls and checks the resulting canonical SQLite records. */
@RunWith(AndroidJUnit4::class)
class BroopLiftFlowTest {
    @get:Rule val compose = createComposeRule()
    private val viewModels = ViewModelStore()
    private lateinit var app: NoopApplication
    private lateinit var vm: AppViewModel
    private lateinit var liftStore: BroopLiftStore
    private var sessionId: String? = null
    private fun text(id: Int) = app.getString(id)
    private fun button(id: Int) = compose.onNode(hasText(text(id)) and hasClickAction())
    private fun field(id: Int) = compose.onNode(hasText(text(id)) and hasSetTextAction())

    @Before fun setUp() {
        IdlingPolicies.setIdlingResourceTimeout(15, TimeUnit.SECONDS)
        IdlingPolicies.setMasterPolicyTimeout(20, TimeUnit.SECONDS)
        app = ApplicationProvider.getApplicationContext()
        NoopPrefs.of(app).edit().putBoolean("updates.autoCheck", false).apply()
        BroopPrefs.setEnabled(app, true)
        if (InstrumentationRegistry.getArguments().getString("broop.seed") == "true") {
            runBlocking { DemoSeeder.seedIfEmpty(app.repository) }
        }
        vm = AppViewModel(app)
        viewModels.put("broop-lift-flow", vm)
    }

    @After fun tearDown() {
        // A failed test must not leave a live rest alarm or half-finished fixture for the route suite.
        if (::vm.isInitialized) {
            var ownsActive = false
            compose.runOnIdle { ownsActive = sessionId != null && vm.broopLift.session?.id == sessionId }
            if (ownsActive) {
                val cleanup = java.util.concurrent.CountDownLatch(1)
                compose.runOnIdle {
                    vm.viewModelScope.launch {
                        try { vm.broopLift.discard() } finally { cleanup.countDown() }
                    }
                }
                assertTrue("Failed strength fixture did not release its rest alarms", cleanup.await(10, TimeUnit.SECONDS))
            }
        }
        viewModels.clear()
    }

    @Test fun freeSessionCanLogUndoRestFinishAndReopenWithoutDuplicatingItsWorkout() {
        compose.setContent { NoopTheme { BroopAppRoot(vm, initialRoute = "lift_log") } }
        compose.waitUntil(20_000) {
            compose.onAllNodesWithText(text(R.string.broop_body_start_free_session_7bc09db)).fetchSemanticsNodes().isNotEmpty()
        }
        liftStore = BroopLiftStore(app, vm.activeStrapId)
        val before = runBlocking { liftStore.sessions().mapTo(HashSet()) { it.id } }
        assertTrue("The isolated fixture already has an unfinished strength session",
            runBlocking { liftStore.sessions().none { it.endTs == null } })

        button(R.string.broop_body_start_free_session_7bc09db).performScrollTo().performClick()
        compose.waitUntil(20_000) { vm.broopLift.session != null && vm.broopLift.isPresented }
        compose.runOnIdle { sessionId = vm.broopLift.session!!.id }
        val exercise = "Port test press"
        button(R.string.broop_lift_add_exercise).performScrollTo().performClick()
        field(R.string.broop_body_exercise_20863c8).performTextReplacement(exercise)
        compose.onNodeWithTag("broop.lift.exercise.confirm").performClick()
        compose.waitUntil(10_000) { vm.broopLift.engine?.plan?.singleOrNull()?.exercise == exercise }

        fun editNumbers() {
            compose.onNodeWithTag("broop.lift.slot.0.1").performScrollTo().performClick()
            field(R.string.broop_body_weight_kg_d249832).performTextReplacement("42.5")
            field(R.string.broop_body_reps_702045f).performTextReplacement("8")
            compose.onNodeWithTag("broop.lift.slot.confirm").performClick()
        }
        editNumbers()
        button(R.string.broop_body_start_set_c818c49).performScrollTo().performClick()
        button(R.string.broop_body_complete_set_2c711f0).performScrollTo().performClick()
        compose.waitUntil(10_000) {
            vm.broopLift.engine?.let { it.stage is LiftSessionEngine.Stage.Resting && it.sets.size == 1 } == true
        }
        button(R.string.broop_lift_undo).performScrollTo().performClick()
        compose.waitUntil(10_000) {
            vm.broopLift.engine?.let { it.stage is LiftSessionEngine.Stage.Working && it.sets.isEmpty() } == true
        }
        // A redo can have different numbers; the final save must reflect the values shown now.
        editNumbers()
        button(R.string.broop_body_complete_set_2c711f0).performScrollTo().performClick()
        compose.waitUntil(10_000) { vm.broopLift.engine?.sets?.size == 1 }
        compose.onNodeWithText(text(R.string.broop_lift_resting), ignoreCase = true).performScrollTo().assertIsDisplayed()

        // Leave one real planned slot unfinished so the finish-choice UI also owns what is saved.
        button(R.string.broop_lift_add_set).performScrollTo().performClick()
        button(R.string.broop_body_finish_session_5fe14d3).performScrollTo().performClick()
        button(R.string.broop_lift_discard_unfinished).performScrollTo().performClick()
        field(R.string.broop_body_session_rpe_1_10_optional_8e9effb).performScrollTo().performTextReplacement("7")
        field(R.string.broop_body_session_note_fd92224).performScrollTo().performTextReplacement("Port flow verified")
        button(R.string.broop_body_save_session_8c7478c).performScrollTo().performClick()
        compose.waitUntil(20_000) { vm.broopLift.session == null }

        val id = sessionId!!
        val saved = runBlocking { liftStore.sessions().single { it.id == id } }
        assertFalse(before.contains(saved.id))
        assertNotNull(saved.endTs)
        assertEquals(7.0, saved.sessionRpe!!, 0.0)
        assertEquals("Port flow verified", saved.note)
        val sets = runBlocking { liftStore.sets(id) }
        assertEquals(2, sets.size)
        assertEquals(listOf(1, 2), sets.map { it.setIndex })
        assertEquals(exercise, sets.first().exercise)
        assertEquals(42.5, sets.first().weightKg!!, 0.0)
        assertEquals(8, sets.first().reps)
        assertNotNull(sets.first().startTs)
        assertNotNull(sets.first().endTs)
        assertTrue(sets.first().endTs!! >= sets.first().startTs!!)
        assertNotNull(sets.first().restSec)
        assertEquals(0, sets.last().reps)
        assertEquals(0.0, sets.last().weightKg!!, 0.0)
        assertNull(sets.last().startTs)
        assertNull(sets.last().endTs)
        assertNull(sets.last().restSec)

        fun assertSinglePairedWorkout() {
            WhoopDatabase.get(app).openHelper.readableDatabase.query(
                "SELECT * FROM workout WHERE deviceId = ? AND startTs = ? AND sport = ?",
                arrayOf(saved.deviceId, saved.startTs, saved.sport),
            ).use { cursor ->
                assertEquals("Finishing or reopening created a duplicate workout", 1, cursor.count)
                assertTrue(cursor.moveToFirst())
                assertEquals(saved.endTs, cursor.getLong(cursor.getColumnIndexOrThrow("endTs")))
                assertEquals("manual", cursor.getString(cursor.getColumnIndexOrThrow("source")))
                assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("strain")))
                assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("avgHr")))
            }
        }
        assertSinglePairedWorkout()
        button(R.string.broop_body_progress_1b90271).performScrollTo().performClick()
        compose.onAllNodesWithText(text(R.string.broop_body_free_session_88633a3)).onFirst().performScrollTo().performClick()
        // History uses BroopCaps (uppercase), and its set rows arrive after the static heading.
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText(exercise, substring = true, ignoreCase = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onAllNodesWithText(exercise, substring = true, ignoreCase = true).onFirst().performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("${broopOne(42.5)} kg × 8").performScrollTo().assertIsDisplayed()
        assertSinglePairedWorkout()
    }
}
