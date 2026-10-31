import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// #833 (Insights freeze): the snapshot InsightsView.load() builds, parked on the long-lived Repository so a
/// re-mount (macOS keys the NavigationSplitView detail with `.id`, so every sidebar switch cold-mounts the
/// screen) can RESTORE it in-memory instead of re-running the full history read on the @MainActor. The exact
/// twin of Today's `TodayHistoryWideCache` for #849; holds load()'s six computed outputs. Consumed only when
/// the seq AND the dayKey still match (see `Repository.insightsLoadedSeq` / `insightsLoadedDayKey`).
struct InsightsLoadCache {
    let behaviours: [String: Set<String>]
    /// Per behaviour, the days it was logged NO. Cached alongside `behaviours` because a restore that
    /// dropped it would leave the ranker with no controls and silently produce no insights at all.
    let controls: [String: Set<String>]
    let importedQuestions: [String]
    let dayAnswers: [String: Bool]
    /// The journal day offset the `dayAnswers` were read for (0 = today, 1 = yesterday, -1 = tomorrow). The
    /// restore guards on it so a re-mount, which resets `journalDayOffset` to 0, only reuses the cache when
    /// the cached answers match that reset day, otherwise it falls through to a fresh read (#833).
    let journalDayOffset: Int
    let outcomeByKey: [String: [String: Double]]
    let seriesByKey: [String: [(day: String, value: Double)]]
    let activityCosts: [ActivityCost]
    /// #322: per-question numeric journal series (question → [day: value]) for numeric journal items
    /// (e.g. "caffeine mg", "alcohol units"). A numeric series feeds the same effect ranker the metric
    /// outcomes do, so a numeric behaviour can rank in Insights. Empty for a yes/no-only journal.
    let numericJournalByKey: [String: [String: Double]]
}
