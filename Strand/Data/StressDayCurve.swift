import Foundation
import StrandAnalytics

/// Scores today's stress for the surfaces that draw it, and does it as rarely as it can get away with.
///
/// The Kotlin `StressWidgetProducer` still scores day-relative; this no longer mirrors it (iPhone only).
///
/// THE GATE IS THE POINT. Scoring a day means reading today's heart rate, R-R and gravity, three reads
/// bounded at 200 000 rows each, which is the work the Stress screen does when you open it. The screen
/// does that once, on a deliberate act. A widget producer runs on the publish path, which fires when
/// the app becomes active and after every Health sync, so nothing is read until `Repository`'s cheap
/// union heart-rate witness — one COUNT and one MAX per source id, over an indexed column, no rows —
/// says today's heart rate actually moved. A publish that changed nothing costs those queries and
/// reuses the previous curve.
///
/// ONE CURVE. This no longer scores anything itself. It maps `Repository.stressToday`, the analysis the
/// Stress screen, Home and Health read, so a widget and the app cannot show different values for an hour.
/// During the cold start the result is empty: a surface shows no level rather than a day-relative guess.
enum StressDayCurve {

    /// What the last scoring saw and produced, swapped in as ONE value.
    ///
    /// Separate fields could tear: a second call arriving between two assignments would read one
    /// call's fingerprint beside another's result and serve a curve for a day it was not scored
    /// against. Both callers are `@MainActor` today, so the window is narrow, but an immutable holder
    /// closes it for free.
    private struct Memo {
        let fingerprint: String
        let day: Int
        let result: DaytimeStress.Result
    }

    @MainActor private static var memo: Memo?

    /// Today's curve and the local day number it belongs to, or nil when it could not be scored.
    ///
    /// Nil is not "today scored nothing": it means "say nothing about stress right now", so a caller
    /// that persists this must carry forward what it already had rather than blanking. An EMPTY result
    /// with a day is the real "nothing scored today" answer.
    ///
    /// Returns the analytics `Result` rather than any one drawing's point type, because two surfaces
    /// read it: the iOS widget, which maps it into its own `StressPoint`, and the Today host card,
    /// which hands `timeline` straight to `DaytimeLoadLine`. Keeping the widget's type here would have
    /// kept this file iOS-only, and the Today card is shared with macOS.
    @MainActor
    static func today(repo: Repository, now: Date = Date(),
                      calendar: Calendar = .current) async -> (result: DaytimeStress.Result, day: Int)? {
        let startOfDay = calendar.startOfDay(for: now)
        let from = Int(startOfDay.timeIntervalSince1970)
        let to = Int(now.timeIntervalSince1970)
        let day = localDayNumber(now, calendar: calendar)

        // UNION, and per source id rather than collapsed into one pair. A gate narrower than the read
        // it guards is worse than none: `hrSamples` below walks every raw source, so a witness that
        // summed those ids could hold steady while the window's composition changed under it. This is
        // the twin of the Kotlin producer's witness.
        //
        // An EMPTY string means there is no store yet, which a caller must read as "cannot tell"
        // rather than "unchanged": nil here is the same refusal the summed witness returned.
        let fingerprint = await repo.hrFingerprintUnion(from: from, to: to)
        guard !fingerprint.isEmpty else { return nil }
        // Same day, same heart rate: nothing can have changed the score, so nothing is read. The day is
        // part of the check because a fingerprint that happened to match across midnight would otherwise
        // serve yesterday's curve as today's.
        if let memo, memo.day == day, memo.fingerprint == fingerprint {
            return (memo.result, day)
        }

        // nil only when there is no store or no day to read: "say nothing", as above.
        guard let analysis = await repo.stressToday(now: now) else { return nil }
        let scored = StressMonitor.curve(analysis, tzOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
        memo = Memo(fingerprint: fingerprint, day: day, result: scored)
        return (scored, day)
    }

    /// Days since the epoch on the LOCAL calendar.
    ///
    /// RESTATED from `WidgetSnapshot.localDayNumber` rather than shared, because there is no module
    /// both readers can see: `WidgetSnapshot` lives in the iOS/widget sources, which the macOS app does
    /// not compile, and the widget extension links no packages, so it cannot reach this file either.
    ///
    /// The two MUST agree. The widget stores the day this returns and later compares it against
    /// `WidgetSnapshot.localDayNumber` to decide whether the stored curve is still today's, so a
    /// divergence would silently drop a valid curve. `HostedCardPrefsTests` pins them equal from the
    /// app target, which can see both.
    ///
    /// Counted by the calendar rather than by dividing by 86 400, because that arithmetic is wrong on a
    /// DST day: `Europe/London` produces one day a year whose number would equal the previous day's.
    static func localDayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: epoch,
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Drops the memo so a test starts from a known state.
    @MainActor
    static func resetForTest() { memo = nil }
}
