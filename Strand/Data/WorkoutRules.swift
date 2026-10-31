import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum WorkoutRules {
    /// #797: trailing-day window the FIRST workouts read is bounded to, so first paint never sorts a
    /// multi-thousand-workout history. Comfortably covers the default range (the tightest range with ≥2
    /// sessions, almost always ≤90 days); a wider pick pages the rest in via `expandWindow`. 400 days
    /// covers the 1Y range plus headroom.
    static let firstPaintWindowDays = 400
    /// Sessions inside a given range, RELATIVE TO THE LATEST session, then passed through the active
    /// filter. `.all` = all. The window anchor (`latestTs`) is the newest of ALL loaded rows so the
    /// window doesn't shift when a filter narrows the set.
    /// Which slice of the history the list is showing.
    ///
    /// A VIEW split, never a delete. Archived rows stay in the database untouched and are one tap away,
    /// which is the whole reason the request for "keep the last 10 and auto-delete the rest" is answered
    /// this way instead: NOOP has no server and no cloud copy, so pruning real training history would be
    /// irreversible, and hiding it costs nothing.
    enum Scope: String, CaseIterable, Identifiable {
        case current, archived
        var id: String { rawValue }
        /// `LocalizedStringKey` rather than `String`, because this is only ever handed to `Text`, so the
        /// resolution belongs to the view environment.
        ///
        /// The sibling enums on other screens return `String(localized:)` instead, which is equally correct
        /// for a value that has to be a String. What is NOT correct, and is what this property shipped as
        /// first, is a BARE literal returned as a String: it renders in English forever, and the i18n gate
        /// does not catch it, because a literal in that position is not somewhere the scanner looks. The
        /// gate flagged the Picker's "Scope" key and said nothing about these two, which are the words
        /// actually printed on the tabs.
        var label: LocalizedStringKey { self == .current ? "Current" : "Archived" }
    }
    /// How many of the most recent sessions "Current" holds.
    static let currentScopeCount = 10
    /// Split rows into the most recent `currentCount` and everything older.
    ///
    /// Pure and order-preserving: membership is decided by ranking on `startTs`, but the rows come back in
    /// the order they arrived, so the caller's sort still decides what the screen shows. Ranking rather
    /// than comparing against a cutoff timestamp is what makes ties safe: two sessions that start in the
    /// same second cannot both sneak past a threshold and hand "Current" an eleventh row.
    ///
    /// Applied AFTER the range and sport filters, so each tab means "the 10 most recent of what you are
    /// currently looking at" rather than silently showing an empty Current when a filter excludes the
    /// newest sessions.
    nonisolated static func scopedRows(_ rows: [WorkoutRow], scope: Scope,
                                       currentCount: Int = currentScopeCount) -> [WorkoutRow] {
        guard rows.count > currentCount else { return scope == .current ? rows : [] }
        let key: (WorkoutRow) -> String = { "\($0.startTs)|\($0.sport)" }
        let newest = Set(rows.sorted { $0.startTs > $1.startTs }.prefix(currentCount).map(key))
        return rows.filter { scope == .current ? newest.contains(key($0)) : !newest.contains(key($0)) }
    }
}
