import XCTest
@testable import Strand

/// Pins the pure gate + copy of the 2026-09-21 detected-workout notification — the twin of
/// Android `WorkoutDetectedPolicyTest` (same constants, same semantics). The notifier wires these
/// to UNUserNotificationCenter + the persisted settled tokens, so all the decision logic is
/// verified here with no UserNotifications types.
///
/// The contract under test:
///  - ONE notification per pass: the NEWEST eligible bout, and every eligible span settles at once
///    so a multi-bout pass can never drip extras out later;
///  - a bout only notifies once its end is >= notifySettleSec old (can't fire mid-workout);
///  - dismissed / real-overlapping / already-settled spans never fire — all by OVERLAP, not exact
///    tokens, so a drifted re-detect stays silent;
///  - copy states only measured facts: duration always, avg/peak bpm only when present; a classifier
///    `suggestedClass` names the activity but only hedged ("looks like"), never as a measured fact.
final class WorkoutDetectedPolicyTests: XCTestCase {

    private typealias C = WorkoutDetectedPolicy.Candidate

    private func decide(
        _ now: Int,
        _ candidates: [C],
        real: [(start: Int, end: Int)] = [],
        dismissed: [(start: Int, end: Int)] = [],
        settled: [(start: Int, end: Int)] = []
    ) -> WorkoutDetectedPolicy.Decision {
        WorkoutDetectedPolicy.decide(nowSec: now, candidates: candidates,
                                     realSpans: real, dismissedSpans: dismissed,
                                     settledSpans: settled)
    }

    // MARK: - settle window (600 s)

    func testFiresOnceBoutIsSettled() {
        let now = 1_000_000
        let d = decide(now, [C(startTs: 900_000, endTs: now - 601, avgHr: nil, maxHr: nil)])
        XCTAssertEqual(d.notify?.startTs, 900_000)
        XCTAssertEqual(d.settledTokens, ["900000:\(now - 601)"])
    }

    func testSuppressedInsideSettleWindow() {
        let now = 1_000_000
        // Ended 599 s ago — a live bout can extend across a sync boundary; too early to claim it ended.
        let d = decide(now, [C(startTs: 900_000, endTs: now - 599, avgHr: nil, maxHr: nil)])
        XCTAssertNil(d.notify)
        XCTAssertTrue(d.settledTokens.isEmpty)
    }

    func testBoundaryExactlyAtSettleIsEligible() {
        let now = 1_000_000
        let d = decide(now, [C(startTs: 900_000, endTs: now - 600, avgHr: nil, maxHr: nil)])
        XCTAssertEqual(d.notify?.startTs, 900_000)
    }

    // MARK: - newest-wins + settle-all (one notification per pass)

    func testNotifiesNewestEligibleBoutOnly() {
        let now = 1_000_000
        let older = C(startTs: 800_000, endTs: now - 5_000, avgHr: nil, maxHr: nil)
        let newer = C(startTs: 900_000, endTs: now - 1_000, avgHr: nil, maxHr: nil)
        let d = decide(now, [older, newer])
        XCTAssertEqual(d.notify, newer)
        // BOTH settle — the pass can't later fire the older sibling as a second notification.
        XCTAssertEqual(d.settledTokens.count, 2)
    }

    func testUnsettledBoutIsNotMarkedAndMayFireNextPass() {
        let now = 1_000_000
        let live = C(startTs: 900_000, endTs: now - 60, avgHr: nil, maxHr: nil)   // still inside the window
        let done = C(startTs: 800_000, endTs: now - 5_000, avgHr: nil, maxHr: nil)
        let d = decide(now, [live, done])
        XCTAssertEqual(d.notify, done)
        XCTAssertEqual(d.settledTokens, [WorkoutDetectedPolicy.token(startTs: done.startTs, endTs: done.endTs)])
    }

    // MARK: - suppression spans (all overlap, never exact)

    func testDismissedSpanSuppressesByOverlap() {
        let now = 1_000_000
        // Marker spans drifted boundaries — overlap, not token equality, must suppress.
        let d = decide(now, [C(startTs: 900_000, endTs: now - 1_000, avgHr: nil, maxHr: nil)],
                       dismissed: [(899_990, now - 990)])
        XCTAssertNil(d.notify)
        XCTAssertTrue(d.settledTokens.isEmpty)
    }

    func testRealSessionSpanSuppressesByOverlap() {
        let now = 1_000_000
        let d = decide(now, [C(startTs: 900_000, endTs: now - 1_000, avgHr: nil, maxHr: nil)],
                       real: [(905_000, now - 500)])
        XCTAssertNil(d.notify)
    }

    func testSettledSpanSuppressesDriftedReDetect() {
        let now = 1_000_000
        // A bout already notified re-derives with a startTs a few minutes earlier — overlap means
        // it can never fire again.
        let d = decide(now, [C(startTs: 898_000, endTs: now - 2_000, avgHr: nil, maxHr: nil)],
                       settled: [(900_000, now - 1_900)])
        XCTAssertNil(d.notify)
        XCTAssertTrue(d.settledTokens.isEmpty)
    }

    func testNonOverlappingSpansDoNotSuppress() {
        let now = 1_000_000
        let d = decide(now, [C(startTs: 900_000, endTs: now - 1_000, avgHr: nil, maxHr: nil)],
                       dismissed: [(100_000, 200_000)], settled: [(300_000, 400_000)])
        XCTAssertEqual(d.notify?.startTs, 900_000)
    }

    // MARK: - token + prune hygiene

    func testPrunedTokensDropsMalformedAndAncient() {
        let now = 3_000_000
        let kept = WorkoutDetectedPolicy.prunedTokens(
            ["garbage", "a:b", "5:4", "900000:999000", "1:100"], nowSec: now)
        // "1:100" ended before now-maxTokenAgeSec (408000) so it prunes; malformed + inverted drop.
        XCTAssertEqual(kept, ["900000:999000"])
    }

    func testPrunedTokensCapsAtMaxKeepingNewest() {
        let now = 10_000_000
        // 250 fresh spans, oldest-first input — the cap must keep the 200 NEWEST starts.
        let tokens = (1...250).map {
            WorkoutDetectedPolicy.token(startTs: now - $0 * 1_000, endTs: now - $0 * 1_000 + 500)
        }
        let kept = WorkoutDetectedPolicy.prunedTokens(tokens, nowSec: now)
        XCTAssertEqual(kept.count, WorkoutDetectedPolicy.maxTokens)
        XCTAssertTrue(kept.contains(WorkoutDetectedPolicy.token(startTs: now - 1_000, endTs: now - 500)))
        XCTAssertFalse(kept.contains(WorkoutDetectedPolicy.token(startTs: now - 250_000, endTs: now - 249_500)))
    }

    // MARK: - copy (measured facts only)

    func testCopyShowsDurationAndHrWhenPresent() {
        let (title, body) = WorkoutDetectedPolicy.copy(
            C(startTs: 0, endTs: 47 * 60, avgHr: 104, maxHr: 140))
        XCTAssertEqual(title, "Activity detected")
        XCTAssertTrue(body.contains("47 min"))
        XCTAssertTrue(body.contains("avg 104 bpm"))
        XCTAssertTrue(body.contains("peaked 140 bpm"))
        XCTAssertTrue(body.contains("Saved to Workouts"))
    }

    func testCopyOmitsHrWhenAbsentNeverInvents() {
        let (_, body) = WorkoutDetectedPolicy.copy(
            C(startTs: 0, endTs: 68 * 60, avgHr: nil, maxHr: nil))
        XCTAssertTrue(body.contains("1 h 8 min"))
        XCTAssertFalse(body.contains("bpm"))
    }

    func testCopyClaimsNoSport() {
        let (title, body) = WorkoutDetectedPolicy.copy(
            C(startTs: 0, endTs: 3_600, avgHr: 150, maxHr: 170))
        for word in ["run", "ride", "cycle", "swim", "lift", "walk", "hike"] {
            XCTAssertFalse(title.lowercased().contains(word))
            XCTAssertFalse(body.lowercased().contains(word))
        }
    }

    // MARK: - suggested class in copy (advisory, hedged)

    func testCopyNamesSuggestedClassHedged() {
        // A classifier suggestion appears as "looks like X" — advisory wording, never a claim.
        let (_, body) = WorkoutDetectedPolicy.copy(
            C(startTs: 0, endTs: 47 * 60, avgHr: 104, maxHr: 140, suggestedClass: "walk"))
        XCTAssertTrue(body.contains("looks like Walking"))
        XCTAssertTrue(body.contains("47 min"))
    }

    func testCopyOtherAndUnknownClassesMakeNoClaim() {
        // "other" is the classifier declining to pick; unknown tokens (a future class) too — the
        // body must fall back to the no-claim form rather than printing a raw token.
        for token in ["other", "other.thing", "yoga", ""] {
            let (_, body) = WorkoutDetectedPolicy.copy(
                C(startTs: 0, endTs: 2_400, avgHr: 110, maxHr: 130, suggestedClass: token))
            XCTAssertFalse(body.contains("looks like"), "token \(token) must not name a class")
            XCTAssertTrue(body.contains("Saved to Workouts"))
        }
    }

    func testClassLabelCoversEveryConcreteClass() {
        // The notification can only name classes the classifier can emit — keep the map complete.
        XCTAssertEqual(WorkoutDetectedPolicy.classLabel("walk"), "Walking")
        XCTAssertEqual(WorkoutDetectedPolicy.classLabel("run"), "Running")
        XCTAssertEqual(WorkoutDetectedPolicy.classLabel("strength"), "Strength Training")
        XCTAssertEqual(WorkoutDetectedPolicy.classLabel("cycle"), "Cycling")
        XCTAssertEqual(WorkoutDetectedPolicy.classLabel("ski"), "Skiing")
        XCTAssertNil(WorkoutDetectedPolicy.classLabel("other"))
        XCTAssertNil(WorkoutDetectedPolicy.classLabel(nil))
    }
}
