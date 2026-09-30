import Foundation
import StrandAnalytics

extension Repository {
    /// The production SWC readout. Calendar windows and freshness gates belong to HRVStatus.
    func hrvReadiness(asOf day: String, flaggedDays: Set<String> = []) async -> HRVStatus.Outcome? {
        let nights = days.map { HRVStatus.Night(day: $0.day, rmssd: $0.avgHrv) }
        return await CancellableAnalysis.run {
            HRVStatus.evaluate(nights: nights, asOf: day, flaggedDays: flaggedDays)
        }
    }
}
