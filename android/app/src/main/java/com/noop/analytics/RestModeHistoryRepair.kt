package com.noop.analytics

/** Rest mode changes affect every stored Rest score and the Charge scores that depend on it. */
object RestModeHistoryRepair {
    const val completedKey = "intelligence.stressRestV2.sri.backfill.done"
    const val restModeHistoryDays = 4000

    /** Rearm before dispatch so interruption or a changed preference remains repairable on launch. */
    // Swift twin `IntelligenceEngine.rescoreForRestModeChange(historyDays:)`.
    suspend fun run(
        capturedMode: Boolean,
        currentMode: () -> Boolean,
        markComplete: (Boolean) -> Unit,
        rescore: suspend () -> Boolean,
    ) {
        markComplete(false)
        if (rescore()) markComplete(capturedMode == currentMode())
    }
}
