package com.noop.ui

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.widget.Toast
import androidx.annotation.StringRes
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.noop.R

internal enum class BroopShortcutAction(val id: String, @StringRes val title: Int, @StringRes val detail: Int) {
    Sync("broop.sync", R.string.broop_shortcut_sync, R.string.broop_shortcut_sync_detail),
    Buzz("broop.buzz", R.string.broop_shortcut_buzz, R.string.broop_shortcut_buzz_detail),
    Mark("broop.mark", R.string.broop_shortcut_mark, R.string.broop_shortcut_mark_detail);

    fun perform(sync: () -> Unit, buzz: () -> Unit, mark: () -> Unit) = when (this) {
        Sync -> sync()
        Buzz -> buzz()
        Mark -> mark()
    }
}

/** Pinned launcher actions are local, explicit activity intents; creating one never runs it. */
internal object BroopAndroidShortcuts {
    const val intentAction = "com.noop.action.BROOP_SHORTCUT"
    const val actionExtra = "com.noop.extra.BROOP_SHORTCUT"

    fun launchIntent(context: Context, action: BroopShortcutAction): Intent =
        Intent(context, MainActivity::class.java).apply {
            this.action = intentAction
            putExtra(actionExtra, action.id)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    /** Remove the payload before dispatch so rotation and activity recreation cannot replay a cue. */
    fun consumeIntent(intent: Intent?): BroopShortcutAction? {
        val raw = intent?.getStringExtra(actionExtra)
        intent?.removeExtra(actionExtra)
        return if (intent?.action == intentAction) BroopShortcutAction.entries.firstOrNull { it.id == raw } else null
    }

    fun dispatchIntent(intent: Intent?) {
        consumeIntent(intent)?.let(NoopRouteBus::postShortcut)
    }

    fun canPin(context: Context): Boolean =
        context.getSystemService(ShortcutManager::class.java)?.isRequestPinShortcutSupported == true

    fun requestPin(context: Context, action: BroopShortcutAction): Boolean {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return false
        if (!manager.isRequestPinShortcutSupported) return false
        val shortcut = ShortcutInfo.Builder(context, action.id)
            .setShortLabel(context.getString(action.title))
            .setLongLabel(context.getString(action.title))
            .setIcon(Icon.createWithResource(context, R.mipmap.broop_launcher))
            .setIntent(launchIntent(context, action))
            .build()
        return runCatching { manager.requestPinShortcut(shortcut, null) }.getOrDefault(false)
    }
}

/** Shares the same consent gates and ViewModel in Broop and classic mode. */
@Composable
internal fun BroopShortcutHandler(vm: AppViewModel) {
    val context = LocalContext.current
    LaunchedEffect(vm) {
        NoopRouteBus.shortcuts.collect { pending ->
            val action = pending.firstOrNull() ?: return@collect
            NoopRouteBus.consumeShortcut()
            val connected = vm.live.value.let { it.connected && it.bonded }
            val message = if (action != BroopShortcutAction.Mark && !connected) {
                R.string.broop_shortcut_connect_first
            } else {
                action.perform(vm::syncNow, vm::buzzStrapOnce, vm::markMoment)
                when (action) {
                    BroopShortcutAction.Sync -> R.string.broop_shortcut_sync_requested
                    BroopShortcutAction.Buzz -> R.string.broop_shortcut_buzz_requested
                    BroopShortcutAction.Mark -> R.string.broop_shortcut_marked
                }
            }
            Toast.makeText(context, context.getString(message), Toast.LENGTH_SHORT).show()
        }
    }
}

@Composable
fun BroopAndroidShortcutsScreen(onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val supported = remember(context) { BroopAndroidShortcuts.canPin(context) }
    BroopPage(stringResource(R.string.broop_account_android_shortcuts)) {
        BroopCard {
            Text(stringResource(R.string.broop_shortcut_summary), style = BroopType.body, color = BroopPalette.textBody)
        }
        if (!supported) BroopCard {
            Text(stringResource(R.string.broop_shortcut_unsupported), style = BroopType.body, color = BroopPalette.textBody)
        }
        BroopShortcutAction.entries.forEach { action ->
            BroopCard {
                Text(stringResource(action.title), style = BroopType.demi, color = BroopPalette.textPrimary)
                Text(stringResource(action.detail), style = BroopType.body, color = BroopPalette.textBody)
                NoopButton(text = stringResource(R.string.broop_shortcut_pin), enabled = supported,
                    kind = NoopButtonKind.Secondary, fullWidth = true,
                    onClick = {
                        val requested = BroopAndroidShortcuts.requestPin(context, action)
                        Toast.makeText(context, context.getString(if (requested) R.string.broop_shortcut_confirm else R.string.broop_shortcut_failed), Toast.LENGTH_SHORT).show()
                    })
            }
        }
        BroopRow(stringResource(R.string.nav_automations)) { onNavigate(Destination.Automations.route) }
    }
}
