import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopProtocol
import WhoopStore

/// #849: an in-memory snapshot of everything `loadHistoryWide()` computes: the ~40 history-wide reads +
/// the per-workout strap-HR derivation. Held on the long-lived `Repository` (NOT TodayView's `@State`),
/// keyed by the `refreshSeq` it was built at, so a Today RE-MOUNT (TabView/module switch, or an
/// Apple-Health import that recreates the view, both tear down `@State`) can RESTORE these values without
/// re-running the heavy query pass. Restoring is a handful of in-memory assignments; the old code instead
/// re-ran the full history-wide reload on every re-mount, which is the lag #849 reports returning to Today
/// after an import. Built only after a real `loadHistoryWide()`; consumed when the seq still matches.
struct TodayHistoryWideCache {
    let sparks: [String: [Double]]
    let stepsEstByDay: [String: Int]
    let workouts: [WorkoutRow]
    let appleDays: [AppleDaily]
    let xiaomiDays: Int
    let xiaomiSleeps: Int
    let stressToday: Double?
    let fitnessAgeToday: Double?
    let vo2maxToday: Double?
    let vitalityToday: Double?
    // Hydration total/goal intentionally absent (#989): mutations don't bump refreshSeq, so a cached
    // value could restore stale. TodayView re-reads hydration live on restore instead.
}

/// #849/#932: an in-memory snapshot of everything `loadDayScoped()` computes for ONE viewed day: the Rest
/// score + its tile spark, the provenance winners, the selected day's 5-minute HR buckets, the day's step
/// activity class, the live Effort, the pinned chart axis and the overlapping sleep band. Held on the
/// long-lived `Repository` (NOT TodayView's `@State`), keyed by the (`refreshSeq`, viewed-day key) it was
/// built at, so a Today RE-MOUNT with unchanged data (macOS cold-mounts the screen on every sidebar switch)
/// can RESTORE these values without re-running the heavy `hrBuckets`/`hrSamples` reads, 170k+ HR rows/day
/// on a big library, the measured #932 frame degradation. The day key half of the pair is what makes day
/// navigation safe: another day's snapshot can never be served because its key differs. Built only after a
/// real `loadDayScoped()`; consumed when BOTH the seq AND the day key still match (see
/// `Repository.todayDayScopedLoadedSeq` / `todayDayScopedLoadedDayKey`).
struct TodayDayScopedCache {
    let restSpark: [Double]
    let restScore: Double?
    let provenanceByMetric: [String: String]
    let providerByMetric: [String: ScoreInputProvider]
    let hrPoints: [TrendPoint]
    let stepActivityClassToday: Int?
    let liveTodayStrain: Double?
    let hrAxis: ClosedRange<Date>
    let sleepToday: CachedSleepSession?
    /// When the snapshot was banked. TODAY hits are age-gated on this (`todayCacheMaxAge`): live banking
    /// does not bump `refreshSeq`, so an unbounded today snapshot would drift behind the 1Hz stream.
    let bankedAt: Date
}

/// #245: the sync-status state used by the Devices screen's larger sync card, resolved once from
/// `LiveState`. THREE states mean the ABSENCE of active syncing reads as "caught up", not
/// "missing indicator" (the real #245 confusion): actively offloading → `⟳ N`; idle with a known
/// last-sync → `✓ Xm`; a 5/MG whose history sync is experimental (live-connected, no completed offload
/// yet) → `✓ live`. `.hidden` only on a true cold start (the building-scores note owns that case). Twin
/// of Android `SyncStatusChip`.
enum SyncChipState: Equatable {
    /// #689/#815 follow-up: `pagesBehind` is the strap's GET_DATA_RANGE ring backlog, sampled once at
    /// connect (`LiveState.pagesBehindAtConnect`) and never re-polled, so the copy reports it "at
    /// connect" rather than as a live figure. nil when no reply has landed this session, when the frame
    /// did not decode, AND when the backlog is zero: a chip that is actively syncing while claiming
    /// "0 pages behind" contradicts itself, and a zero sample carries nothing a reader can act on.
    /// `resolve` applies that rule so both platforms drop the same case. Twin of Android
    /// `SyncChipState.Syncing`.
    case syncing(chunks: Int, pagesBehind: Int?)
    case synced(agoText: String)
    case experimentalLive
    case hidden

    @MainActor
    static func resolve(live: LiveState) -> SyncChipState {
        if live.backfilling {
            // The zero rule above. Negative cannot come off the wire (the decoder returns a ring delta),
            // but the bound reads the same either way. Android spells this `?.takeIf { it > 0 }`.
            return .syncing(chunks: live.syncChunksThisSession,
                            pagesBehind: live.pagesBehindAtConnect.flatMap { $0 > 0 ? $0 : nil })
        }
        if let ts = live.lastSyncedAt { return .synced(agoText: shortAgo(ts)) }
        if live.historySyncExperimental { return .experimentalLive }
        return .hidden
    }

    /// Compact relative age for the status card ("<1m" / "Nm" / "Nh" / "Nd") — deliberately terse.
    ///
    /// EVERY branch must read correctly with a trailing "ago", because that is the only way this value is
    /// ever consumed (`DevicesView` wraps it in "Synced %@ ago" and "Strap history synced %@ ago"). The
    /// sub-minute branch used to return the word "now", which produced the user-visible "Synced now ago"
    /// for the first minute after any sync (#1472). "<1m" composes; it also needs no catalog entry, being
    /// digits and symbols in every language.
    private static func shortAgo(_ ts: TimeInterval) -> String {
        let secs = max(0, Int(Date().timeIntervalSince1970 - ts))
        if secs < 60 { return "<1m" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}
