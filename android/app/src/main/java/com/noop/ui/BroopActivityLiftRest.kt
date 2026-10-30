package com.noop.ui

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.noop.R
import com.noop.analytics.LiftSessionEngine
import com.noop.analytics.LiftSessionFinish

/** Rest alarms are local and remain scheduled when Android removes the app process. */
class BroopLiftRestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WARNING && intent.action != END) return
        val device = intent.getStringExtra("device") ?: return
        val session = intent.getStringExtra("session") ?: return
        val end = intent.getLongExtra("end", 0)
        val now = System.currentTimeMillis() / 1000
        val prefs = NoopPrefs.of(context)
        val key = "noop.activeLiftSession.$device"
        val restored = BroopLiftSnapshot.decode(prefs.getString(key, null), now) ?: return
        if (!matches(restored, session, device, end)) return
        val warning = intent.action == WARNING
        if (warning) {
            if (end - now > 5 || restored.warnedFor == end) return
            if (liveWarning?.invoke(session, device, end) != true) {
                if (!prefs.edit().putString(key, BroopLiftSnapshot.encode(restored.copy(warnedFor = end))).commit()) return
            }
        } else if (end > now) return
        show(context, restored, ready = end <= now, alert = true)
    }
    companion object {
        private const val WARNING = "com.noop.LIFT_REST_WARNING"
        private const val END = "com.noop.LIFT_REST_END"
        internal var liveWarning: ((String, String, Long) -> Boolean)? = null
        internal fun matches(value: BroopLiftSnapshot.Restored, session: String, device: String, end: Long): Boolean =
            value.sessionId == session && value.deviceId == device && (value.engine.stage as? LiftSessionEngine.Stage.Resting)?.endsAt == end
        internal fun schedule(context: Context, value: BroopLiftSnapshot.Restored, now: Long) {
            cancel(context)
            val end = (value.engine.stage as? LiftSessionEngine.Stage.Resting)?.endsAt ?: return
            val times = LiftSessionFinish.restEventTimes(end, now)
            val manager = context.getSystemService(AlarmManager::class.java)
            for ((action, stamp) in listOf(WARNING to times.first, END to times.second)) {
                if (stamp == null) continue
                val pending = pending(context, action, value.sessionId, value.deviceId, end)
                try {
                    if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stamp * 1000, pending)
                    else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stamp * 1000, pending)
                } catch (_: SecurityException) { manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, stamp * 1000, pending) }
            }
        }
        internal fun cancel(context: Context) {
            val manager = context.getSystemService(AlarmManager::class.java)
            for (action in listOf(WARNING, END)) manager.cancel(pending(context, action, "", "", 0))
        }
        private fun pending(context: Context, action: String, session: String, device: String, end: Long) = PendingIntent.getBroadcast(
            context, if (action == WARNING) 6242 else 6243,
            Intent(context, BroopLiftRestReceiver::class.java).setAction(action).putExtra("session", session).putExtra("device", device).putExtra("end", end),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        internal fun show(context: Context, value: BroopLiftSnapshot.Restored, ready: Boolean, alert: Boolean = false) {
            val end = (value.engine.stage as? LiftSessionEngine.Stage.Resting)?.endsAt ?: return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel("noop_lift_rest", context.getString(R.string.broop_lift_rest_notification), NotificationManager.IMPORTANCE_DEFAULT))
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.putExtra("com.noop.lift.RESUME", true)
            val intent = launch?.let { PendingIntent.getActivity(context, 6241, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
            val line = value.engine.currentSlot?.let { value.engine.item(it)?.exercise }.orEmpty()
            val notification = NotificationCompat.Builder(context, "noop_lift_rest")
                .setSmallIcon(android.R.drawable.ic_media_play).setContentTitle(line)
                .setContentText(context.getString(if (ready) R.string.broop_lift_rest_ready else R.string.broop_lift_resting))
                .setWhen(end * 1000).setUsesChronometer(!ready).setChronometerCountDown(true).setSilent(!alert)
                .setOngoing(!ready).setContentIntent(intent).setCategory(NotificationCompat.CATEGORY_PROGRESS).build()
            try { NotificationManagerCompat.from(context).notify(6241, notification) } catch (_: SecurityException) { }
        }
    }
}
