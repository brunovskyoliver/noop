package com.noop.analytics

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestModeHistoryRepairTest {
    @Test fun completesOnlyAfterTheCapturedModeWasPersisted() = runBlocking {
        var complete = true
        val events = mutableListOf<String>()
        RestModeHistoryRepair.run(true, { true }, { complete = it; events += "complete=$it" }) {
            assertFalse(complete)
            events += "persisted 4000 days"
            true
        }
        assertTrue(complete)
        assertEquals(listOf("complete=false", "persisted 4000 days", "complete=true"), events)
        assertEquals(4000, RestModeHistoryRepair.restModeHistoryDays)
    }

    @Test fun aPreferenceChangedDuringThePassRearmsLaunchRepair() = runBlocking {
        val completion = mutableListOf<Boolean>()
        RestModeHistoryRepair.run(true, { false }, completion::add) { true }
        assertEquals(listOf(false, false), completion)
    }

    @Test fun aSkippedOrFailedPassStaysPending() = runBlocking {
        val completion = mutableListOf<Boolean>()
        RestModeHistoryRepair.run(false, { false }, completion::add) { false }
        assertEquals(listOf(false), completion)
    }

    @Test fun cancellationCannotCompleteTheHistoryRepair() = runBlocking {
        val completion = mutableListOf<Boolean>()
        try {
            RestModeHistoryRepair.run(false, { false }, completion::add) {
                throw CancellationException("ViewModel cleared")
            }
            throw AssertionError("Cancellation must propagate")
        } catch (_: CancellationException) {
            assertEquals(listOf(false), completion)
        }
    }
}
