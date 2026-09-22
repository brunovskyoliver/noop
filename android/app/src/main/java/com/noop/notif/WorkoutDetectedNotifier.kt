package com.noop.notif

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.noop.NoopApplication
import com.noop.R
import com.noop.data.WhoopRepository
import com.noop.ui.NoopPrefs
import com.noop.ui.NoopRouteBus
import com.noop.ui.WorkoutDetectedRoute
import com.noop.ui.appLaunchIntent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// MARK: - Detected-workout notification (2026-09-21)
//
// A single opt-in, default-OFF FYI: after an analysis pass persists `sport="detected"` bouts
// (IntelligenceEngine re-derives them every run), post one local notification for the newest
// detected bout whose end is at least [WorkoutDetectedPolicy.NOTIFY_SETTLE_SEC] old. The row is
// already saved — the notification is informational, with Edit / "Not a workout" actions so the
// user can relabel or durably dismiss it. WHOOP auto-saves detected "Activity" rows the same way;
// the wording below is NOOP's own.
//
// Battery contract: this adds NO work of its own — no alarm, no BLE, no sensor reads. The check
// rides the existing analyze cadence (post-offload pass + the 15-min tick): when the preference is
// OFF it costs one SharedPreferences read per call; when ON it adds two bounded workouts reads over
// a 36-hour window.
//
// Dedup is by SPAN OVERLAP, not exact tokens: the engine's re-detect can drift a bout's startTs by
// minutes between passes, so the persisted "startTs:endTs" set is consulted the same way the
// dismissed-detected table is (WhoopDao read-time overlap filter). Once a span is settled, every
// overlapping re-derive stays silent — and every eligible token from the pass is marked, so the
// same pass can never trickle out extra notifications on later passes.
//
// Swift twin: Strand/System/WorkoutDetectedNotifier.swift (same constants, same semantics).

/** Pure, JVM-testable policy + copy for the detected-workout notification — no Android types, so
 *  the decision logic is pinned by WorkoutDetectedPolicyTest independently of the plumbing. */
object WorkoutDetectedPolicy {

    /** One detected-bout candidate, built from a persisted `sport="detected"` row. */
    data class Candidate(
        val startTs: Long,
        val endTs: Long,
        val avgHr: Int?,
        val maxHr: Int?,
        /** The classifier's advisory token ("walk"/"run"/"strength"/"cycle"/"ski"), copied from the
         *  row's `suggestedClass`. null when the classifier had nothing to say — the copy then makes
         *  no activity claim at all. */
        val suggestedClass: String? = null,
    )

    /** The pass decision: the single bout to notify about (newest eligible), plus EVERY eligible
     *  span token to mark settled — not just the notified one, so a pass with several fresh bouts
     *  can never trickle out extra notifications on later passes. */
    data class Decision(val notify: Candidate?, val settledTokens: List<String>)

    /** A bout must have been over this long before we talk about it: the detector extends a live
     *  bout across a sync boundary, so notifying on first sight could fire mid-workout. 600 s also
     *  lands the notification ~10-25 min post-exercise on the normal offload cadence. */
    const val NOTIFY_SETTLE_SEC = 600L
    /** Candidates are only considered inside this lookback — an ancient re-detect never notifies. */
    const val CANDIDATE_WINDOW_SEC = 36L * 3600L
    /** Persisted-token hygiene: spans older than this are pruned and the set is capped, so the
     *  SharedPreferences list can't grow without bound across process restarts. */
    const val MAX_TOKEN_AGE_SEC = 30L * 86_400L
    const val MAX_TOKENS = 200

    /** The "startTs:endTs" token persisted for a settled span — same shape as the dismissed-detected
     *  markers, so the two span lists share one overlap grammar. */
    fun token(startTs: Long, endTs: Long): String = "$startTs:$endTs"

    /** Half-open overlap test — identical to the dismissed-detected read-time filter. */
    fun overlaps(aStart: Long, aEnd: Long, bStart: Long, bEnd: Long): Boolean =
        aStart < bEnd && bStart < aEnd

    /** Pick the newest notify-eligible bout and every eligible token to settle.
     *
     *  A candidate is eligible when ALL hold:
     *   - it ended at least [NOTIFY_SETTLE_SEC] ago (can't fire mid-workout);
     *   - it does not overlap a dismissed span (the user already said "not a workout" — matching
     *     the read-time filter that hides it from the Workouts list);
     *   - it does not overlap a real (manual / imported / strap-native) session span — mirrors the
     *     engine's own persist-time overlap suppression and covers a real row imported after the
     *     detected twin was persisted;
     *   - it does not overlap an already-settled span (drift-tolerant re-notification guard).
     *
     *  [realSpans] / [dismissedSpans] / [settledSpans] are (start,end) pairs. Deterministic: newest
     *  by endTs, then startTs. */
    fun decide(
        nowSec: Long,
        candidates: List<Candidate>,
        realSpans: List<Pair<Long, Long>>,
        dismissedSpans: List<Pair<Long, Long>>,
        settledSpans: List<Pair<Long, Long>>,
    ): Decision {
        val eligible = candidates.filter { c ->
            c.endTs <= nowSec - NOTIFY_SETTLE_SEC &&
                dismissedSpans.none { overlaps(c.startTs, c.endTs, it.first, it.second) } &&
                realSpans.none { overlaps(c.startTs, c.endTs, it.first, it.second) } &&
                settledSpans.none { overlaps(c.startTs, c.endTs, it.first, it.second) }
        }
        val notify = eligible.maxWithOrNull(compareBy<Candidate> { it.endTs }.thenBy { it.startTs })
        return Decision(
            notify = notify,
            settledTokens = eligible.map { token(it.startTs, it.endTs) }.sorted(),
        )
    }

    /** Parse "startTs:endTs" tokens into (start,end) pairs, dropping malformed entries. */
    fun parseSpans(tokens: Collection<String>): List<Pair<Long, Long>> =
        tokens.mapNotNull { t ->
            val p = t.split(':')
            val a = p.getOrNull(0)?.toLongOrNull() ?: return@mapNotNull null
            val b = p.getOrNull(1)?.toLongOrNull() ?: return@mapNotNull null
            if (p.size != 2 || b <= a) null else a to b
        }

    /** Prune the persisted settled-token set: drop malformed entries, spans older than
     *  [MAX_TOKEN_AGE_SEC], and overflow beyond [MAX_TOKENS] keeping the newest starts. Returns a
     *  sorted list so the persisted value is deterministic and testable. */
    fun prunedTokens(tokens: Collection<String>, nowSec: Long): List<String> {
        val spans = tokens.mapNotNull { t ->
            val p = t.split(':')
            val a = p.getOrNull(0)?.toLongOrNull() ?: return@mapNotNull null
            val b = p.getOrNull(1)?.toLongOrNull() ?: return@mapNotNull null
            if (p.size != 2 || b <= a) null else Triple(a, b, t)
        }
        return spans.filter { it.second > nowSec - MAX_TOKEN_AGE_SEC }
            .sortedByDescending { it.first }
            .take(MAX_TOKENS)
            .map { it.third }
            .sorted()
    }

    /** "47 min" / "1 h 23 min" — mirrors [ScheduledReportPolicy.durationLabel] so the notification
     *  body reads identically on both platforms. */
    fun durationLabel(minutes: Int): String = ScheduledReportPolicy.durationLabel(minutes)

    /** The measured-facts fragment ("47 min · avg 104 bpm · peaked 140 bpm"). avg/peak are omitted
     *  when absent, never invented, and no sport is claimed — attribution discipline: only what the
     *  detector measured. */
    fun metricsText(c: Candidate): String {
        val parts = ArrayList<String>(3)
        parts.add(durationLabel(((c.endTs - c.startTs) / 60L).toInt()))
        c.avgHr?.let { parts.add("avg $it bpm") }
        c.maxHr?.let { parts.add("peaked $it bpm") }
        return parts.joinToString(" · ")
    }

    /** English display name for a classifier token, posted verbatim. null for "other"/unknown
     *  tokens — they make no claim. Swift twin `WorkoutDetectedPolicy.classLabel`. */
    fun classLabel(token: String?): String? = when (token) {
        "walk" -> "Walking"
        "run" -> "Running"
        "strength" -> "Strength Training"
        "cycle" -> "Cycling"
        "ski" -> "Skiing"
        else -> null
    }

    /** Title + full body. The frame tells the user the row is already saved, so the tap reads as
     *  review, not approval. When the bout carried a classifier suggestion the body names it —
     *  hedged ("looks like") because it is an advisory guess, not a measured fact. */
    fun copy(c: Candidate): Pair<String, String> {
        val tail = "Saved to Workouts — tap to review."
        val label = classLabel(c.suggestedClass)
            ?: return "Activity detected" to metricsText(c) + ". " + tail
        return "Activity detected" to metricsText(c) + " — looks like $label. " + tail
    }
}

object WorkoutDetectedNotifier {

    private const val CHANNEL_ID = "noop_detected_workouts"
    // #297 map: 4201 connection, 4202 illness, 4203 inactivity, 4204 smart alarm, 4205/4206/4207
    // battery, 4208 morning recap, 4209 post-workout summary.
    internal const val NOTIF_ID = 4210

    /** Intent action + extras. The default tap and Edit both launch MainActivity with the span
     *  extras; "Not a workout" is a broadcast so dismissal works cold (no UI). */
    const val ACTION_DISMISS = "com.noop.workoutDetected.DISMISS"
    const val EXTRA_START_TS = "com.noop.workoutDetected.startTs"
    const val EXTRA_END_TS = "com.noop.workoutDetected.endTs"
    const val EXTRA_EDIT = "com.noop.workoutDetected.edit"
    const val EXTRA_NOTIF_ID = "com.noop.workoutDetected.notifId"

    /**
     * Post-pass eligibility check. Called after every analysis-pass boundary — real passes and
     * fingerprint-skipped ticks alike — because a bout's 600 s settle window can elapse during
     * quiet ticks with no new data. One notification per call at most; safe to call from any pass
     * because the settled-token set dedupes across process death.
     *
     * Reads the same union sources the Workouts list merges (detected under "<id>-noop", real
     * sessions under the raw ids) plus the dismissed marker table, so a bout is notified exactly as
     * the user will see it, and a dismissed or later-imported-overlapping row can never fire. When
     * the preference is OFF the whole thing is one bool read.
     */
    suspend fun onAnalysisPass(
        context: Context,
        repository: WhoopRepository,
        strapDeviceId: String,
        trace: ((String) -> Unit)? = null,
    ) {
        if (!NoopPrefs.workoutDetectedNotifyEnabled(context)) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val now = System.currentTimeMillis() / 1000L
        val from = now - WorkoutDetectedPolicy.CANDIDATE_WINDOW_SEC
        val detected = runCatching {
            repository.detectedWorkoutsUnion(strapDeviceId, from, now)
        }.getOrDefault(emptyList())
        if (detected.isEmpty()) return
        val candidates = detected.map {
            WorkoutDetectedPolicy.Candidate(it.startTs, it.endTs, it.avgHr, it.maxHr,
                                            it.suggestedClass)
        }
        val realSpans = runCatching {
            repository.workoutsUnion(strapDeviceId, from, now)
        }.getOrDefault(emptyList())
            .map { it.startTs to it.endTs }
        val dismissedSpans = runCatching { repository.dismissedDetected(strapDeviceId) }
            .getOrDefault(emptyList())
            .map { it.startTs to it.endTs }
        val settledSpans = WorkoutDetectedPolicy.parseSpans(
            NoopPrefs.workoutDetectedSettledTokens(context))

        val decision = WorkoutDetectedPolicy.decide(
            nowSec = now, candidates = candidates, realSpans = realSpans,
            dismissedSpans = dismissedSpans, settledSpans = settledSpans)
        val bout = decision.notify ?: return

        runCatching {
            post(context, bout)
            // Mark settled only after a successful post (StrainTarget idiom): a suppressed or
            // denied delivery still gets its chance once notifications are usable again.
            val tokens = NoopPrefs.workoutDetectedSettledTokens(context) + decision.settledTokens
            NoopPrefs.setWorkoutDetectedSettledTokens(
                context, WorkoutDetectedPolicy.prunedTokens(tokens, now))
            trace?.invoke(
                com.noop.analytics.WorkoutsTrace.detectedNotifyLine(
                    durMin = ((bout.endTs - bout.startTs) / 60L).toInt(),
                    settledCount = decision.settledTokens.size))
        }
    }

    /** Tap intent: open the app on the Workouts screen focused on this span (detail). */
    fun openIntent(context: Context, startTs: Long, endTs: Long): Intent =
        appLaunchIntent(context).apply {
            putExtra(EXTRA_START_TS, startTs)
            putExtra(EXTRA_END_TS, endTs)
            putExtra(EXTRA_EDIT, false)
        }

    /** Edit-action intent: same landing, but the Workouts screen opens the edit dialog. */
    fun editIntent(context: Context, startTs: Long, endTs: Long): Intent =
        appLaunchIntent(context).apply {
            putExtra(EXTRA_START_TS, startTs)
            putExtra(EXTRA_END_TS, endTs)
            putExtra(EXTRA_EDIT, true)
        }

    /** Dismiss-action intent: broadcast to [WorkoutDetectedActionReceiver], no UI. */
    fun dismissIntent(context: Context, startTs: Long, endTs: Long): Intent =
        Intent(context, WorkoutDetectedActionReceiver::class.java).apply {
            action = ACTION_DISMISS
            putExtra(EXTRA_START_TS, startTs)
            putExtra(EXTRA_END_TS, endTs)
            putExtra(EXTRA_NOTIF_ID, NOTIF_ID)
        }

    @SuppressLint("MissingPermission") // guarded by areNotificationsEnabled() + runCatching
    private fun post(context: Context, bout: WorkoutDetectedPolicy.Candidate) {
        ensureChannel(context)
        val (title, body) = WorkoutDetectedPolicy.copy(bout)
        // Distinct requestCodes per action+span so PendingIntent extras can never collide/reuse a
        // stale intent; FLAG_UPDATE_CURRENT keeps the latest span if a re-post lands.
        val open = PendingIntent.getActivity(
            context, 40,
            openIntent(context, bout.startTs, bout.endTs),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val edit = PendingIntent.getActivity(
            context, 41,
            editIntent(context, bout.startTs, bout.endTs),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val dismiss = PendingIntent.getBroadcast(
            context, 42,
            dismissIntent(context, bout.startTs, bout.endTs),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_heart)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .addAction(0, context.getString(R.string.workout_detected_action_edit), edit)
            .addAction(0, context.getString(R.string.workout_detected_action_dismiss), dismiss)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        // A stable tag per bout means a re-post for the same span replaces rather than stacks.
        NotificationManagerCompat.from(context).notify(
            "workout.detected.${bout.startTs}", NOTIF_ID, n)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
            mgr.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.workout_detected_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = context.getString(R.string.workout_detected_channel_desc)
                },
            )
        }
    }
}

/** "Not a workout" action: durably suppresses the notified span WITHOUT opening the app — the same
 *  end state as dismissing the row from the Workouts list (a span marker survives the engine's
 *  re-derive, and the current row is deleted). Not exported; only our own PendingIntent fires it. */
class WorkoutDetectedActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WorkoutDetectedNotifier.ACTION_DISMISS) return
        val start = intent.getLongExtra(WorkoutDetectedNotifier.EXTRA_START_TS, -1L)
        val end = intent.getLongExtra(WorkoutDetectedNotifier.EXTRA_END_TS, -1L)
        if (start < 0 || end <= start) return
        NotificationManagerCompat.from(context).cancel(
            "workout.detected.$start", WorkoutDetectedNotifier.NOTIF_ID)
        val pending = goAsync()
        val app = context.applicationContext
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val strapId = (app as? NoopApplication)?.activeDeviceId
                    ?.takeIf { it.isNotEmpty() } ?: WhoopRepository.WHOOP_SOURCE
                WhoopRepository.from(app).dismissDetectedSpan(start, end, strapId)
            } finally {
                pending.finish()
            }
        }
    }
}

/** Parse the launch intent a notification tap delivered, if any. Centralised so the tap, the Edit
 *  action, and a cold start all resolve identically. */
fun workoutDetectedRouteFrom(intent: Intent?): WorkoutDetectedRoute? {
    intent ?: return null
    val start = intent.getLongExtra(WorkoutDetectedNotifier.EXTRA_START_TS, -1L)
    val end = intent.getLongExtra(WorkoutDetectedNotifier.EXTRA_END_TS, -1L)
    if (start < 0 || end <= start) return null
    return WorkoutDetectedRoute(
        startTs = start, endTs = end,
        edit = intent.getBooleanExtra(WorkoutDetectedNotifier.EXTRA_EDIT, false))
}

/** Feed the route bus from an incoming intent (MainActivity onCreate / onNewIntent). */
fun dispatchWorkoutDetectedRoute(intent: Intent?) {
    workoutDetectedRouteFrom(intent)?.let { NoopRouteBus.postWorkoutDetected(it) }
}
