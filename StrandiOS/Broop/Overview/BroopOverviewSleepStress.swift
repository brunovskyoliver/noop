#if os(iOS)
import Foundation

/// Rating for the Rest v2 "High Sleep Stress" contributor: the share of the main sleep in HIGH stress.
/// Under 5 % reads optimal (WHOOP: good sleep sits low on the scale), 5–15 % sufficient, above that poor.
/// The score's own credit is `AnalyticsEngine.RestV2.sleepStressCredit`; this only colours the row.
enum BroopOverviewSleepStressRating {
    static func rating(_ pct: Double) -> BroopOverviewRating {
        pct < 5 ? .optimal : (pct < 15 ? .sufficient : .poor)
    }
}
#endif
