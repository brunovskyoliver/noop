import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics

struct SleepHeartRateNight: Identifiable, Sendable {
    let day: String
    let preSleep: PreSleepHeartRateFeedback.Feedback?
    let contrast: SleepHeartRateContrast.Result?
    var id: String { day }
}

/// Presentation inputs for the existing descriptive engines. No stored or scoring values are changed.
enum SleepHeartRateWindows {
    struct Night: Sendable {
        let day: String
        let start: Int
        let end: Int
    }

    nonisolated static func primary(sessions: [CachedSleepSession], habitual: Int?) -> [Night] {
        SleepModel.navDays(navSessions: sessions).compactMap { blocks in
            let group = SleepView.mainNightGroup(blocks, habitualMidsleepSec: habitual)
            guard let start = group.map(\.effectiveStartTs).min(), let end = group.map(\.endTs).max(), end > start else { return nil }
            return Night(day: Repository.localDayKey(Date(timeIntervalSince1970: Double(end))), start: start, end: end)
        }.sorted { $0.start < $1.start }
    }

    /// Full five-minute epochs only; missing buckets remain nil. Sleep/naps are excluded from waking time.
    nonisolated static func grid(from: Int, to: Int, buckets: [Int: Double], excluding: [Range<Int>] = []) -> [Double?] {
        let cadence = 300
        let first = ((from + cadence - 1) / cadence) * cadence
        guard to - first >= cadence else { return [] }
        return stride(from: first, through: to - cadence, by: cadence).compactMap { ts -> Double?? in
            let epoch = ts..<(ts + cadence)
            if excluding.contains(where: { $0.overlaps(epoch) }) { return nil }
            return .some(buckets[ts])
        }
    }
}

extension Repository {
    /// One load for both Sleep cards and their trends, capped at 65 nights for the prior baseline.
    func sleepHeartRateHistory(through day: String, preSleepEnabled: Bool) async -> [SleepHeartRateNight] {
        let sessions = await allSleepSessions(days: 70)
        let habitual = await habitualMidsleepSec()
        let nights = await CancellableAnalysis.run {
            Array(SleepHeartRateWindows.primary(sessions: sessions, habitual: habitual).filter { $0.day <= day }.suffix(65))
        }
        guard let first = nights.first, let last = nights.last else { return [] }
        let buckets = await hrBuckets(from: first.start - 86_400, to: last.end, bucketSeconds: 300)
        let byTime = await CancellableAnalysis.run { Dictionary(buckets.map { ($0.ts, $0.bpm) }, uniquingKeysWith: { a, _ in a }) }
        let sleepRanges = sessions.compactMap { $0.endTs > $0.effectiveStartTs ? $0.effectiveStartTs..<$0.endTs : nil }
        var history: [PreSleepHeartRateFeedback.HistoricalReading] = []
        var output: [SleepHeartRateNight] = []
        for (index, night) in nights.enumerated() {
            guard !Task.isCancelled else { return [] }
            let raw = preSleepEnabled ? await hrSamples(from: night.start - 1800, to: night.start - 1, limit: 10_000) : []
            let prior = history
            let previous = index > 0 ? nights[index - 1] : nil
            let result = await CancellableAnalysis.run { () -> SleepHeartRateNight in
                let session = SleepSession(start: night.start, end: night.end, efficiency: 0,
                                           stages: [], restingHR: nil, avgHRV: nil)
                let feedback = preSleepEnabled ? PreSleepHeartRateFeedback.evaluate(
                    enabled: true, sessions: [session], hr: raw, history: prior, journalEntries: [], day: night.day) : nil
                var contrast: SleepHeartRateContrast.Result?
                if let previous, previous.end < night.start, night.start - previous.end <= 86_400 {
                    let wake = SleepHeartRateWindows.grid(from: previous.end, to: night.start, buckets: byTime, excluding: sleepRanges)
                    let sleep = SleepHeartRateWindows.grid(from: night.start, to: night.end, buckets: byTime)
                    contrast = SleepHeartRateContrast.evaluate(wakeHR: wake, primarySleepHR: sleep)
                }
                return SleepHeartRateNight(day: night.day, preSleep: feedback, contrast: contrast)
            }
            if let observation = result.preSleep?.observation {
                history.append(.init(day: night.day, meanBpm: observation.meanBpm))
            }
            output.append(result)
        }
        guard let end = VitalityEngine.epochDay(day) else { return [] }
        return output.filter { row in VitalityEngine.epochDay(row.day).map { $0 > end - 30 } ?? false }
    }
}
