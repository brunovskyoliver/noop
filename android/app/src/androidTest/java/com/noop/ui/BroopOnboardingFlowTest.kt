package com.noop.ui

import android.graphics.Bitmap
import android.Manifest
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.noop.NoopApplication
import com.noop.R
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the unpaired path with permission grants supplied by the test harness. */
@RunWith(AndroidJUnit4::class)
class BroopOnboardingFlowTest {
    @get:Rule val compose = createComposeRule()
    private val models = ViewModelStore()

    @After fun tearDown() { models.clear() }

    @Test fun unpairedUserCanFinishAllApplicableOnboardingSteps() {
        val app = ApplicationProvider.getApplicationContext<NoopApplication>()
        val permissions = blePermissions().toList() +
            if (Build.VERSION.SDK_INT >= 33) listOf(Manifest.permission.POST_NOTIFICATIONS) else emptyList()
        permissions.forEach { permission ->
            ParcelFileDescriptor.AutoCloseInputStream(
                InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
                    "pm grant ${app.packageName} $permission"),
            ).use { it.readBytes() }
        }
        BroopPrefs.setEnabled(app, true)
        NoopPrefs.of(app).edit().putBoolean("updates.autoCheck", false).apply()
        val vm = AppViewModel(app)
        models.put("onboarding", vm)
        val finished = mutableStateOf(false)
        compose.setContent {
            NoopTheme {
                if (finished.value) Text("Onboarding completed")
                else BroopOnboardingScreen(vm) { finished.value = true }
            }
        }
        val steps = listOf(
            1 to R.string.broop_onboarding_get_started,
            2 to R.string.onboarding_cta_continue,
            3 to R.string.broop_onboarding_understand,
            4 to R.string.onboarding_cta_continue,
            5 to R.string.broop_onboarding_wearing,
            6 to R.string.onboarding_cta_continue,
            8 to R.string.onboarding_cta_save_continue,
            9 to R.string.onboarding_cta_continue,
            10 to R.string.onboarding_cta_continue,
            11 to R.string.onboarding_cta_continue,
            12 to R.string.broop_onboarding_enter,
        )
        for ((page, cta) in steps) {
            compose.onNodeWithText(app.getString(R.string.l10n_onboarding_screen_page_total_50b38f9a, page, 12))
                .assertIsDisplayed()
            if (page == 1 || page == 8) {
                val folder = java.io.File(app.filesDir, "broop-port-evidence").apply { mkdirs() }
                java.io.File(folder, "onboarding-$page.png").outputStream().use {
                    compose.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            }
            compose.onNodeWithText(app.getString(cta)).performClick()
        }
        compose.onNodeWithText("Onboarding completed").assertIsDisplayed()
    }
}
