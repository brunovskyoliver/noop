package com.noop.ui

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.test.espresso.IdlingPolicies
import java.util.concurrent.TimeUnit
import android.graphics.Bitmap
import android.util.Log
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onRoot
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pinch
import androidx.compose.ui.geometry.Offset
import androidx.lifecycle.ViewModelStore
import androidx.test.platform.app.InstrumentationRegistry
import com.noop.data.DemoSeeder
import com.noop.data.HrSample
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.noop.NoopApplication
import com.noop.R
import kotlin.math.roundToInt
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Executes real destination bodies against the emulator's isolated application database. */
@RunWith(AndroidJUnit4::class)
class BroopPortSmokeTest {
    @get:Rule val compose = createComposeRule()
    private val store = ViewModelStore()
    private lateinit var vm: AppViewModel

    @Before fun setUp() {
        IdlingPolicies.setIdlingResourceTimeout(15, TimeUnit.SECONDS)
        IdlingPolicies.setMasterPolicyTimeout(20, TimeUnit.SECONDS)
        val app = ApplicationProvider.getApplicationContext<NoopApplication>()
        NoopPrefs.of(app).edit().putBoolean("updates.autoCheck", false).apply()
        BroopPrefs.setEnabled(app, true)
        if (InstrumentationRegistry.getArguments().getString("broop.seed") == "true") {
            runBlocking { DemoSeeder.seedIfEmpty(app.repository) }
        }
        vm = AppViewModel(app)
        store.put("broop", vm)
    }
    @After fun tearDown() { store.clear() }

    @Test fun everyPortedDestinationRendersAndKeepsNavigation() {
        val route = mutableStateOf("today")
        compose.setContent { NoopTheme { key(route.value) { BroopAppRoot(vm, initialRoute = route.value) } } }
        val destinations = listOf(
            "today", "health_hub", "more", "sleep", "score/charge", "score/rest", "score/effort",
            "vital_signs", "coach_settings", "full_day_chart", "coupled_view", "workouts", "activity", "live", "lift_log", "lift_active", "breathe", "intervals",
            "health", "stress", "lab_book", "rhythm", "explore", "trends", "hydration", "compare",
            "healthspan", "mind", "energy", "jet_lag", "vital_detail/hrv", "vital_detail/sleep_stress_pct",
            "insights", "insights_hub", "intelligence", "fused_record", "coach", "smart_alarm", "settings",
            "account/profile", "account/heart_rate", "account/units", "account/appearance", "account/sleep",
            "account/features", "account/strap", "account/data", "account/scoring", "account/experimental",
            "account/about", "account/storage", "integrations", "devices", "apple_health", "mi_band", "data_sources",
            "backup_sync", "shortcuts_export", "android_shortcuts", "noop_limitations", "automations", "power_saving",
            "notifications", "test_centre", "steps_calibration", "self_hosted_push", "classic_today", "journal_insights",
        )
        val requested = InstrumentationRegistry.getArguments().getString("broop.routes")?.split(',')
        for (destination in requested ?: destinations) {
            compose.runOnIdle { route.value = destination }
            compose.waitUntil(30_000) { compose.onAllNodesWithContentDescription("Quick actions").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("broop.quickActions").assertIsDisplayed()
            if (InstrumentationRegistry.getArguments().getString("broop.seed") == "true" && destination in setOf("today", "sleep", "score/charge", "score/rest", "score/effort")) {
                if (destination == "today") {
                    val scoredRing = SemanticsMatcher("recorded Rest or Charge") { node ->
                        node.config.getOrNull(SemanticsProperties.ContentDescription)?.any {
                            Regex("(?:Rest|Charge): [0-9]+%").matches(it)
                        } == true
                    }
                    compose.waitUntil(20_000) { compose.onAllNodes(scoredRing).fetchSemanticsNodes().size >= 2 }
                }
                val numeric = SemanticsMatcher("recorded score") { node ->
                    node.config.getOrNull(SemanticsProperties.Text)?.any { Regex("[0-9]+(\\.[0-9]+)?").matches(it.text) } == true
                }
                compose.waitUntil(20_000) { compose.onAllNodes(numeric, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
            }
            compose.waitForIdle()
            Log.i("BroopPortSmoke", "Rendered $destination")
            if (destination in setOf("today", "health_hub", "more", "sleep", "score/charge", "score/rest", "score/effort", "lift_log", "energy", "mind", "stress", "healthspan", "coupled_view", "full_day_chart")) {
                val app = ApplicationProvider.getApplicationContext<NoopApplication>()
                val folder = java.io.File(app.filesDir, "broop-port-evidence").apply { mkdirs() }
                java.io.File(folder, destination.replace('/', '-') + ".png").outputStream().use {
                    compose.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            }
        }
    }

    @Test fun tabsAndQuickActionsNavigateToTheActualForms() {
        compose.setContent { NoopTheme { BroopAppRoot(vm) } }
        compose.onNodeWithText("More").performClick()
        compose.waitUntil(20_000) { compose.onAllNodesWithText("My Profile").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Home").performClick()
        compose.onNodeWithTag("broop.quickActions").performClick()
        compose.onNodeWithText("Add activity").performClick()
        compose.waitUntil(20_000) { compose.onAllNodesWithText("Add").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Add").assertIsDisplayed()
    }

    @Test fun historicalRestKeepsTheSelectedDayAcrossNavigation() {
        val app = ApplicationProvider.getApplicationContext<NoopApplication>()
        val yesterday = logicalDayNow().minusDays(1).toString()
        val expected = runBlocking {
            DemoSeeder.seedIfEmpty(app.repository)
            app.repository.resolvedSeries("sleep_performance", "my-whoop", yesterday, yesterday,
                strapDeviceId = vm.activeStrapId).values.last { it.first == yesterday }.second
        }
        val restLabel = app.getString(R.string.broop_overview_rest)
        val description = app.getString(R.string.broop_ring_description, restLabel,
            expected.roundToInt().toString(), "%")
        compose.setContent { NoopTheme { BroopAppRoot(vm) } }
        compose.waitUntil(20_000) { vm.recentDays.value.isNotEmpty() }
        compose.onNodeWithContentDescription("Previous day").assertIsEnabled().performClick()
        compose.waitUntil(20_000) {
            compose.onAllNodesWithContentDescription(description).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Yesterday").assertIsDisplayed()
        compose.onNodeWithContentDescription(description).performClick()
        compose.waitUntil(20_000) { compose.onAllNodesWithText("Sleep performance", ignoreCase = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithText("Yesterday").onFirst().assertIsDisplayed()
        androidx.test.espresso.Espresso.pressBack()
        compose.onNodeWithText("Yesterday").assertIsDisplayed()
        compose.onNodeWithContentDescription(description).assertIsDisplayed()
        compose.onNodeWithContentDescription("Next day").performClick()
        compose.onNodeWithText("Today").assertIsDisplayed()
    }

    @Test fun dayChartSupportsHoldReadPinchAndReset() {
        val app = ApplicationProvider.getApplicationContext<NoopApplication>()
        runBlocking {
            DemoSeeder.seedIfEmpty(app.repository)
            // Demo history contains summaries, so supply a known raw curve for the gesture test.
            val noon = logicalDayNow().atStartOfDay(ZoneId.systemDefault()).toEpochSecond() + 12 * 3600
            app.repository.insertHr((0 until 1200).map { i ->
                HrSample(deviceId = vm.activeStrapId, ts = noon + i, bpm = 65 + (i / 30) % 35)
            })
        }
        compose.setContent { NoopTheme { BroopAppRoot(vm, initialRoute = "full_day_chart") } }
        compose.waitUntil(20_000) {
            compose.onAllNodesWithContentDescription("Timeline,", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        val plot = compose.onNodeWithContentDescription("Timeline,", substring = true)
        plot.performTouchInput { down(center) }
        try {
            compose.mainClock.advanceTimeBy(800)
            val readout = SemanticsMatcher("held timeline value") { node ->
                node.config.getOrNull(SemanticsProperties.Text)?.any {
                    Regex("\\d{1,2}:\\d{2}.* · \\d+").matches(it.text)
                } == true
            }
            compose.waitUntil(10_000) { compose.onAllNodes(readout).fetchSemanticsNodes().isNotEmpty() }
        } finally { plot.performTouchInput { up() } }
        plot.performTouchInput {
            pinch(start0 = center - Offset(width * 0.1f, 0f), end0 = center - Offset(width * 0.35f, 0f),
                start1 = center + Offset(width * 0.1f, 0f), end1 = center + Offset(width * 0.35f, 0f), durationMillis = 500)
        }
        compose.onNodeWithText(app.getString(R.string.timeline_reset)).performScrollTo().performClick()
        compose.onNodeWithText(app.getString(R.string.timeline_reset)).assertDoesNotExist()
    }
}
