package com.noop.ui

import android.app.Application
import android.content.Intent
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, application = Application::class)
class BroopAndroidShortcutsTest {
    @Before fun setUp() = clearQueue()
    @After fun tearDown() = clearQueue()

    private fun clearQueue() {
        while (NoopRouteBus.shortcuts.value.isNotEmpty()) NoopRouteBus.consumeShortcut()
    }

    @Test fun eachPinnedIntentHasAStableIdAnExplicitActivityAndTheExistingTaskFlags() {
        val app = RuntimeEnvironment.getApplication()
        assertEquals(listOf("broop.sync", "broop.buzz", "broop.mark"), BroopShortcutAction.entries.map { it.id })
        for (action in BroopShortcutAction.entries) {
            val intent = BroopAndroidShortcuts.launchIntent(app, action)
            assertEquals(MainActivity::class.java.name, intent.component?.className)
            assertEquals(app.packageName, intent.component?.packageName)
            assertEquals(BroopAndroidShortcuts.intentAction, intent.action)
            assertEquals(action.id, intent.getStringExtra(BroopAndroidShortcuts.actionExtra))
            for (flag in listOf(Intent.FLAG_ACTIVITY_NEW_TASK, Intent.FLAG_ACTIVITY_CLEAR_TOP, Intent.FLAG_ACTIVITY_SINGLE_TOP)) {
                assertEquals(flag, intent.flags and flag)
            }
        }
    }

    @Test fun dispatchConsumesThePayloadBeforePostingAndDoesNotReplayTheSameIntent() {
        val app = RuntimeEnvironment.getApplication()
        val intent = BroopAndroidShortcuts.launchIntent(app, BroopShortcutAction.Sync)
        BroopAndroidShortcuts.dispatchIntent(intent)
        assertFalse(intent.hasExtra(BroopAndroidShortcuts.actionExtra))
        BroopAndroidShortcuts.dispatchIntent(intent)
        assertEquals(listOf(BroopShortcutAction.Sync), NoopRouteBus.shortcuts.value)
        NoopRouteBus.consumeShortcut()
        BroopAndroidShortcuts.dispatchIntent(BroopAndroidShortcuts.launchIntent(app, BroopShortcutAction.Sync))
        BroopAndroidShortcuts.dispatchIntent(BroopAndroidShortcuts.launchIntent(app, BroopShortcutAction.Mark))
        assertEquals(listOf(BroopShortcutAction.Sync, BroopShortcutAction.Mark), NoopRouteBus.shortcuts.value)
    }

    @Test fun unrelatedAndUnknownIntentsCannotRunAShortcut() {
        val ordinary = Intent(Intent.ACTION_MAIN).putExtra(BroopAndroidShortcuts.actionExtra, "broop.buzz")
        assertNull(BroopAndroidShortcuts.consumeIntent(ordinary))
        assertFalse(ordinary.hasExtra(BroopAndroidShortcuts.actionExtra))
        val unknown = Intent(BroopAndroidShortcuts.intentAction).putExtra(BroopAndroidShortcuts.actionExtra, "delete")
        assertNull(BroopAndroidShortcuts.consumeIntent(unknown))
        assertNull(BroopAndroidShortcuts.consumeIntent(null))
        assertTrue(NoopRouteBus.shortcuts.value.isEmpty())
    }

    @Test fun everyActionInvokesOnlyItsCorrespondingExistingFunnel() {
        for (action in BroopShortcutAction.entries) {
            val events = mutableListOf<String>()
            action.perform(sync = { events += "sync" }, buzz = { events += "buzz" }, mark = { events += "mark" })
            assertEquals(listOf(action.id.substringAfter('.')), events)
        }
    }
}
