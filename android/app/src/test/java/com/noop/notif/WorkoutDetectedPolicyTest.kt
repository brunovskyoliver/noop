package com.noop.notif

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the pure gate + copy of the 2026-09-21 detected-workout notification (the
 * ScheduledReportPolicyTest idiom — the notifier wires these to a channel + the persisted settled
 * tokens, so all the decision logic is verified here without android.*).
 *
 * The contract under test:
 *  - ONE notification per pass: the NEWEST eligible bout, and every eligible span settles at once
 *    so a multi-bout pass can never drip extras out later;
 *  - a bout only notifies once its end is >= NOTIFY_SETTLE_SEC old (can't fire mid-workout);
 *  - dismissed / real-overlapping / already-settled spans never fire — all by OVERLAP, not exact
 *    tokens, so a drifted re-detect stays silent;
 *  - copy states only measured facts: duration always, avg/peak bpm only when present; a classifier
 *    `suggestedClass` names the activity but only hedged ("looks like"), never as a measured fact.
 */
class WorkoutDetectedPolicyTest {

    private fun bout(
        start: Long, end: Long, avg: Int? = null, peak: Int? = null,
        suggestedClass: String? = null,
    ) = WorkoutDetectedPolicy.Candidate(start, end, avg, peak, suggestedClass)

    private fun decide(
        now: Long,
        vararg candidates: WorkoutDetectedPolicy.Candidate,
        real: List<Pair<Long, Long>> = emptyList(),
        dismissed: List<Pair<Long, Long>> = emptyList(),
        settled: List<Pair<Long, Long>> = emptyList(),
    ) = WorkoutDetectedPolicy.decide(
        nowSec = now, candidates = candidates.toList(),
        realSpans = real, dismissedSpans = dismissed, settledSpans = settled,
    )

    // MARK: - settle window (600 s)

    @Test fun firesOnceBoutIsSettled() {
        val now = 1_000_000L
        val d = decide(now, bout(900_000L, now - 601L))
        assertEquals(900_000L, d.notify?.startTs)
        assertEquals(listOf("900000:${now - 601}"), d.settledTokens)
    }

    @Test fun suppressedInsideSettleWindow() {
        val now = 1_000_000L
        // Ended 599 s ago — a live bout can extend across a sync boundary; too early to claim it ended.
        val d = decide(now, bout(900_000L, now - 599L))
        assertNull(d.notify)
        assertTrue(d.settledTokens.isEmpty())
    }

    @Test fun boundaryExactlyAtSettleIsEligible() {
        val now = 1_000_000L
        val d = decide(now, bout(900_000L, now - 600L))
        assertEquals(900_000L, d.notify?.startTs)
    }

    // MARK: - newest-wins + settle-all (one notification per pass)

    @Test fun notifiesNewestEligibleBoutOnly() {
        val now = 1_000_000L
        val older = bout(800_000L, now - 5_000L)
        val newer = bout(900_000L, now - 1_000L)
        val d = decide(now, older, newer)
        assertEquals(newer, d.notify)
        // BOTH settle — the pass can't later fire the older sibling as a second notification.
        assertEquals(2, d.settledTokens.size)
    }

    @Test fun unsettledBoutIsNotMarkedAndMayFireNextPass() {
        val now = 1_000_000L
        val live = bout(900_000L, now - 60L)          // still inside the window
        val done = bout(800_000L, now - 5_000L)
        val d = decide(now, live, done)
        assertEquals(done, d.notify)
        assertEquals(listOf(WorkoutDetectedPolicy.token(done.startTs, done.endTs)), d.settledTokens)
    }

    // MARK: - suppression spans (all overlap, never exact)

    @Test fun dismissedSpanSuppressesByOverlap() {
        val now = 1_000_000L
        // Marker spans drifted boundaries — overlap, not token equality, must suppress.
        val d = decide(
            now, bout(900_000L, now - 1_000L),
            dismissed = listOf(899_990L to (now - 990L)),
        )
        assertNull(d.notify)
        assertTrue(d.settledTokens.isEmpty())
    }

    @Test fun realSessionSpanSuppressesByOverlap() {
        val now = 1_000_000L
        val d = decide(
            now, bout(900_000L, now - 1_000L),
            real = listOf(905_000L to (now - 500L)),
        )
        assertNull(d.notify)
    }

    @Test fun settledSpanSuppressesDriftedReDetect() {
        val now = 1_000_000L
        // A bout already notified re-derives with a startTs a few minutes earlier — overlap means
        // it can never fire again.
        val d = decide(
            now, bout(898_000L, now - 2_000L),
            settled = listOf(900_000L to (now - 1_900L)),
        )
        assertNull(d.notify)
        assertTrue(d.settledTokens.isEmpty())
    }

    @Test fun nonOverlappingSpansDoNotSuppress() {
        val now = 1_000_000L
        val d = decide(
            now, bout(900_000L, now - 1_000L),
            dismissed = listOf(100_000L to 200_000L),
            settled = listOf(300_000L to 400_000L),
        )
        assertEquals(900_000L, d.notify?.startTs)
    }

    // MARK: - token + prune hygiene

    @Test fun prunedTokensDropsMalformedAndAncient() {
        val now = 3_000_000L
        val kept = WorkoutDetectedPolicy.prunedTokens(
            listOf("garbage", "a:b", "5:4", "900000:999000", "1:100"),
            nowSec = now,
        )
        // "1:100" ended before now-MAX_TOKEN_AGE_SEC (408000) so it prunes; malformed + inverted
        // entries drop; the valid token stays (single-element list is trivially sorted).
        assertEquals(listOf("900000:999000"), kept)
    }

    @Test fun prunedTokensCapsAtMaxKeepingNewest() {
        val now = 10_000_000L
        // 250 fresh spans, oldest-first input — the cap must keep the 200 NEWEST starts.
        val tokens = (1L..250L).map { WorkoutDetectedPolicy.token(now - it * 1_000L, now - it * 1_000L + 500L) }
        val kept = WorkoutDetectedPolicy.prunedTokens(tokens, nowSec = now)
        assertEquals(WorkoutDetectedPolicy.MAX_TOKENS, kept.size)
        assertTrue(kept.contains(WorkoutDetectedPolicy.token(now - 1_000L, now - 500L)))
        assertFalse(kept.contains(WorkoutDetectedPolicy.token(now - 250_000L, now - 249_500L)))
    }

    // MARK: - copy (measured facts only)

    @Test fun copyShowsDurationAndHrWhenPresent() {
        val (title, body) = WorkoutDetectedPolicy.copy(bout(0L, 47 * 60L, avg = 104, peak = 140))
        assertEquals("Activity detected", title)
        assertTrue(body.contains("47 min"))
        assertTrue(body.contains("avg 104 bpm"))
        assertTrue(body.contains("peaked 140 bpm"))
        assertTrue(body.contains("Saved to Workouts"))
    }

    @Test fun copyOmitsHrWhenAbsentNeverInvents() {
        val (_, body) = WorkoutDetectedPolicy.copy(bout(0L, 68 * 60L))
        assertTrue(body.contains("1 h 8 min"))
        assertFalse(body.contains("bpm"))
    }

    @Test fun copyClaimsNoSport() {
        val (title, body) = WorkoutDetectedPolicy.copy(bout(0L, 3_600L, avg = 150, peak = 170))
        listOf("run", "ride", "cycle", "swim", "lift", "walk", "hike").forEach {
            assertFalse(title.lowercase().contains(it))
            assertFalse(body.lowercase().contains(it))
        }
    }

    // MARK: - suggested class in copy (advisory, hedged)

    @Test fun copyNamesSuggestedClassHedged() {
        // A classifier suggestion appears as "looks like X" — advisory wording, never a claim.
        val (_, body) = WorkoutDetectedPolicy.copy(
            bout(0L, 47 * 60L, avg = 104, peak = 140, suggestedClass = "walk"))
        assertTrue(body.contains("looks like Walking"))
        assertTrue(body.contains("47 min"))
    }

    @Test fun copyOtherAndUnknownClassesMakeNoClaim() {
        // "other" is the classifier declining to pick; unknown tokens (a future class) too — the
        // body must fall back to the no-claim form rather than printing a raw token.
        for (token in listOf("other", "other.thing", "yoga", "")) {
            val (_, body) = WorkoutDetectedPolicy.copy(
                bout(0L, 2_400L, avg = 110, peak = 130, suggestedClass = token))
            assertFalse("token $token must not name a class", body.contains("looks like"))
            assertTrue(body.contains("Saved to Workouts"))
        }
    }

    @Test fun classLabelCoversEveryConcreteClass() {
        // The notification can only name classes the classifier can emit — keep the map complete.
        assertEquals("Walking", WorkoutDetectedPolicy.classLabel("walk"))
        assertEquals("Running", WorkoutDetectedPolicy.classLabel("run"))
        assertEquals("Strength Training", WorkoutDetectedPolicy.classLabel("strength"))
        assertEquals("Cycling", WorkoutDetectedPolicy.classLabel("cycle"))
        assertEquals("Skiing", WorkoutDetectedPolicy.classLabel("ski"))
        assertNull(WorkoutDetectedPolicy.classLabel("other"))
        assertNull(WorkoutDetectedPolicy.classLabel(null))
    }
}
