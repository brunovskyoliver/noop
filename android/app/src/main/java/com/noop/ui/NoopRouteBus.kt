package com.noop.ui

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

// MARK: - Cross-entrypoint route bus (2026-09-21)
//
// A process-local, one-pending-route channel between a system entry point (a notification
// PendingIntent landing on MainActivity) and the Compose shell. The detected-workout notification
// is the first consumer: its tap / Edit action carries a (startTs, endTs) span, AppRoot navigates
// to the Workouts destination, and WorkoutsScreen resolves the span against its loaded rows —
// overlap, not exact tokens, since the engine's re-detect can drift a bout's boundary.
//
// StateFlow (not SharedFlow) on purpose: the route must SURVIVE a cold launch — the intent can
// arrive before the NavHost composes, so the last posted route replays to the first collector.
// Consumers clear it with [consumeWorkoutDetected] so the route fires exactly once per post.

/** A pending deep-link into the Workouts screen: the notified bout's span plus whether to land on
 *  the read-only detail (tap) or the edit/relabel dialog (Edit action). */
data class WorkoutDetectedRoute(
    val startTs: Long,
    val endTs: Long,
    val edit: Boolean,
)

object NoopRouteBus {
    private val _shortcuts = MutableStateFlow<List<BroopShortcutAction>>(emptyList())
    internal val shortcuts: StateFlow<List<BroopShortcutAction>> = _shortcuts
    internal fun postShortcut(action: BroopShortcutAction) { _shortcuts.update { it + action } }
    internal fun consumeShortcut() { _shortcuts.update { it.drop(1) } }

    private val _resumeLift = MutableStateFlow(false)
    val resumeLift: StateFlow<Boolean> = _resumeLift
    fun postLiftResume() { _resumeLift.value = true }
    fun consumeLiftResume() { _resumeLift.value = false }


    private val _workoutDetected = MutableStateFlow<WorkoutDetectedRoute?>(null)

    /** The outstanding detected-workout route, or null. Replays the last post to new collectors. */
    val workoutDetected: StateFlow<WorkoutDetectedRoute?> = _workoutDetected

    fun postWorkoutDetected(route: WorkoutDetectedRoute) {
        _workoutDetected.value = route
    }

    fun consumeWorkoutDetected() {
        _workoutDetected.value = null
    }
}
