import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
@MainActor enum HRVSnapshotRules {
    /// Length of a capture in seconds. Long enough to collect ≥minBeats clean intervals at a resting
    /// rate (≈60 beats at 60 bpm) with headroom for ectopic/range rejection.
    static let captureSeconds = 60
    /// The finish-time analysis over a completed capture, shared with the Broop sheet so both run the
    /// same gates. A capture whose collected beat time exceeds the wall clock it ran for held duplicated
    /// beats (e.g. overlapping live sources) and is refused rather than published.
    ///
    /// HRV & Autonomic test mode (Group G): when the mode is on, the cleaning trace (nInput / nClean /
    /// rejected fraction, the range + Malik ectopic counts, the minBeats + spot gates, RMSSD/SDNN/meanNN)
    /// goes to `traceLog` tagged `.hrv`. analyzeTrace returns the SAME HRVResult `analyze` would (it
    /// reuses analyze verbatim), so the headline RMSSD is byte-identical with the trace on or off. Zero
    /// cost when off: the gate is one UserDefaults bool read and analyzeTrace is never called.
    @MainActor
    static func analyzeCapture(rawRR: [Int], captureMs: Int,
                               traceLog: (String) -> Void) -> HRVAnalyzer.HRVResult {
        let raw = rawRR.map(Double.init)
        if HRVAnalyzer.spotCaptureOverCounted(beatTimeMs: raw.reduce(0, +),
                                              captureMs: Double(captureMs)) {
            return HRVAnalyzer.HRVResult(rmssd: nil, sdnn: nil, meanNN: nil, pnn50: nil,
                                         nInput: raw.count, nClean: 0)
        }
        if TestCentre.active(.hrv) {
            let (traced, lines) = HRVAnalyzer.analyzeTrace(
                rawRR: raw, maxRejectedFraction: HRVAnalyzer.defaultSpotMaxRejectedFraction, path: "spot")
            for line in lines { traceLog(line) }
            return traced
        }
        return HRVAnalyzer.analyze(rawRR: raw,
                                   maxRejectedFraction: HRVAnalyzer.defaultSpotMaxRejectedFraction)
    }
    /// Bank one snapshot RMSSD under today's day and refresh the repository. Returns false when the
    /// store is unavailable or the write fails. Shared with the Broop sheet so both write the same row.
    static func persist(rmssd: Double, repo: Repository) async -> Bool {
        let day = Repository.dayString(Date())
        let point = MetricPoint(day: day, key: HRVSnapshot.metricKey, value: rmssd)
        guard let store = await repo.storeHandle() else { return false }
        do {
            try await store.upsertMetricSeries([point], deviceId: HRVSnapshot.sourceId)
            await repo.refresh()
            return true
        } catch {
            return false
        }
    }
    static func format(_ value: Double?, _ fmt: String) -> String {
        guard let value else { return "—" }
        return String(format: fmt, value)
    }
    /// Mean heart rate (bpm) from the mean NN interval (ms): 60000 / meanNN. nil when meanNN is missing
    /// or non-positive.
    static func meanHR(meanNN: Double?) -> Double? {
        guard let meanNN, meanNN > 0 else { return nil }
        return 60_000.0 / meanNN
    }
    /// Whole seconds left for a monotonic elapsed time, never negative. Mirrors Android
    /// `remainingCaptureSeconds`.
    static func remainingSeconds(elapsedMs: Int) -> Int {
        max(0, captureSeconds - elapsedMs / 1000)
    }
    /// The ingest gate: intervals on or after the 60-second deadline stay out, however late the
    /// countdown timer fires. Mirrors Android `captureWindowOpen`.
    static func captureWindowOpen(elapsedMs: Int) -> Bool {
        elapsedMs < captureSeconds * 1000
    }
}

/// Snapshot-write constants — the metric-series key + source id the manual HRV reading banks under.
/// Kept as a tiny namespace so the source id ("manual-hrv") and key ("hrv_snapshot") are single-sourced
/// and match the Android side value-for-value.
enum HRVSnapshot {
    /// Generic metric-series key for a manual HRV reading.
    static let metricKey = "hrv_snapshot"
    /// Source id this manual reading is stored under — its own source so it sits beside WHOOP / Apple
    /// for the per-source explorer, exactly like the other manual/imported sources.
    static let sourceId = "manual-hrv"
}
