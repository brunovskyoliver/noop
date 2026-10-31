import XCTest
import Foundation
@testable import Strand

/// #127 manual HRV snapshot — pins the pure view helpers that turn an `HRVResult` into the
/// read-out: the mean-HR derivation from the mean NN interval and the null-safe formatter. The
/// capture/analysis maths themselves live in (and are tested by) `HRVAnalyzer`; this only covers
/// the presentation logic the snapshot view adds on top.
@MainActor
final class HRVSnapshotViewTests: XCTestCase {

    // MARK: - meanHR (60000 / meanNN)

    func testMeanHRConvertsMeanNNToBPM() {
        // 1000 ms mean NN → exactly 60 bpm.
        XCTAssertEqual(HRVSnapshotRules.meanHR(meanNN: 1000)!, 60, accuracy: 1e-9)
        // 800 ms → 75 bpm.
        XCTAssertEqual(HRVSnapshotRules.meanHR(meanNN: 800)!, 75, accuracy: 1e-9)
    }

    func testMeanHRIsNilForMissingOrNonPositiveNN() {
        XCTAssertNil(HRVSnapshotRules.meanHR(meanNN: nil))
        XCTAssertNil(HRVSnapshotRules.meanHR(meanNN: 0))
        XCTAssertNil(HRVSnapshotRules.meanHR(meanNN: -5))
    }

    // MARK: - format

    func testFormatRendersEmDashForNil() {
        XCTAssertEqual(HRVSnapshotRules.format(nil, "%.0f"), "—")
    }

    func testFormatRoundsToTheGivenPrecision() {
        XCTAssertEqual(HRVSnapshotRules.format(42.4, "%.0f"), "42")
        XCTAssertEqual(HRVSnapshotRules.format(42.6, "%.0f"), "43")
    }

    // MARK: - Capture window (monotonic deadline)

    func testRemainingSecondsDerivesFromElapsedTime() {
        XCTAssertEqual(HRVSnapshotRules.remainingSeconds(elapsedMs: 0), 60)
        XCTAssertEqual(HRVSnapshotRules.remainingSeconds(elapsedMs: 1_000), 59)
        XCTAssertEqual(HRVSnapshotRules.remainingSeconds(elapsedMs: 59_999), 1)
        XCTAssertEqual(HRVSnapshotRules.remainingSeconds(elapsedMs: 60_000), 0)
    }

    func testACallbackDelayedPastTheDeadlineFinishesImmediately() {
        // A delayed callback at 75 s jumps to done — no decrementing a stale counter.
        XCTAssertEqual(HRVSnapshotRules.remainingSeconds(elapsedMs: 75_000), 0)
    }

    func testIngestWindowClosesExactlyAtTheDeadline() {
        XCTAssertTrue(HRVSnapshotRules.captureWindowOpen(elapsedMs: 0))
        XCTAssertTrue(HRVSnapshotRules.captureWindowOpen(elapsedMs: 59_999))
        XCTAssertFalse(HRVSnapshotRules.captureWindowOpen(elapsedMs: 60_000))
        XCTAssertFalse(HRVSnapshotRules.captureWindowOpen(elapsedMs: 75_000))
    }

    // MARK: - Snapshot constants match the Android twin

    func testSnapshotKeyAndSourceAreStable() {
        // These strings are the cross-platform contract for the saved metric series; if either
        // changes, the Android `HRV_SNAPSHOT_*` constants must change in lockstep.
        XCTAssertEqual(HRVSnapshot.metricKey, "hrv_snapshot")
        XCTAssertEqual(HRVSnapshot.sourceId, "manual-hrv")
    }
}
