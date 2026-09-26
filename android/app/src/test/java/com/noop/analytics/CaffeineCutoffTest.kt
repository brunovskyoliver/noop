package com.noop.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the PR#566 caffeine cutoff-window math added to [CaffeineDecay] — the latest caffeine time before
 * bed and the "this intake is past the cutoff" test. Pure (no android.*); the cross-platform contract is
 * that the Swift twin in CaffeineLog.swift returns the same numbers. The cutoff is just a reframing of the
 * existing half-life decay, so the honest framing ("a guide, not a rule") carries over from the model.
 */
class CaffeineCutoffTest {

    // Dose-aware cutoff; twin of the Swift CaffeineDecayTests cutoff block.

    @Test fun leadReproducesTheMetaAnalysisCutoffs() {
        assertEquals(8.8, CaffeineDecay.cutoffLeadHours(doseMg = 107.0), 0.05)
        assertEquals(13.2, CaffeineDecay.cutoffLeadHours(doseMg = 217.5), 0.05)
        assertEquals(8.038488, CaffeineDecay.cutoffLeadHours(), 1e-5)
    }

    @Test fun leadIsClamped() {
        assertEquals(CaffeineDecay.MIN_CUTOFF_LEAD_HOURS, CaffeineDecay.cutoffLeadHours(doseMg = 20.0), 0.0)
        assertEquals(CaffeineDecay.MAX_CUTOFF_LEAD_HOURS, CaffeineDecay.cutoffLeadHours(doseMg = 5000.0), 0.0)
    }

    @Test fun cutoffIsBedtimeMinusLead() {
        assertEquals(898, CaffeineDecay.cutoffMinutesSinceMidnight(23 * 60))
    }

    @Test fun earlyBedtimeWrapsToPreviousEvening() {
        val cutoff = CaffeineDecay.cutoffMinutesSinceMidnight(6 * 60)
        assertEquals(1318, cutoff)
        assertTrue(cutoff in 0 until 1440)
    }

    @Test fun morningCoffeeIsNotLateAndAfternoonIs() {
        assertFalse(CaffeineDecay.isPastCutoff(intakeMinutes = 8 * 60, bedtimeMinutes = 23 * 60))
        assertTrue(CaffeineDecay.isPastCutoff(intakeMinutes = 16 * 60, bedtimeMinutes = 23 * 60))
    }

    @Test fun intakeExactlyAtCutoffIsNotLate() {
        assertFalse(CaffeineDecay.isPastCutoff(intakeMinutes = 898, bedtimeMinutes = 23 * 60))
        assertTrue(CaffeineDecay.isPastCutoff(intakeMinutes = 899, bedtimeMinutes = 23 * 60))
    }

    @Test fun bigDoseNeedsALongerLead() {
        assertFalse(CaffeineDecay.isPastCutoff(intakeMinutes = 10 * 60, bedtimeMinutes = 23 * 60, doseMg = 95.0))
        assertTrue(CaffeineDecay.isPastCutoff(intakeMinutes = 10 * 60, bedtimeMinutes = 23 * 60, doseMg = 400.0))
    }

    @Test fun earlyBedtimeMakesAnySameDayIntakeLate() {
        assertTrue(CaffeineDecay.isPastCutoff(intakeMinutes = 7 * 60, bedtimeMinutes = 9 * 60))
    }
}
