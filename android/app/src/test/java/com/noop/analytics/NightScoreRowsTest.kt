package com.noop.analytics

import org.junit.Assert.*
import org.junit.Test

class NightScoreRowsTest {
    @Test fun absentMeasurementsDoNotInventWitnesses() {
        assertTrue(NightScoreRows.witnesses("2026-10-19", "s-noop", null, null, null, null).isEmpty())
    }
    @Test fun cleanRrExplicitlyClearsPriorOvercountAndCoverageKeepsItsUnits() {
        val rows = NightScoreRows.witnesses("2026-10-19", "s-noop", 97, false, 56.25,
            PrimarySessionRestingHR.Coverage(400, 3600.0))
        assertTrue(rows.all { it.deviceId == "s-noop" && it.day == "2026-10-19" })
        assertEquals(mapOf("spo2_candidate" to 97.0, "hrv_rr_overcount" to 0.0,
            "rhr_primary_session" to 56.25, "rhr_primary_session_valid_samples" to 400.0,
            "rhr_primary_session_duration_s" to 3600.0), rows.associate { it.key to it.value })
    }
}
