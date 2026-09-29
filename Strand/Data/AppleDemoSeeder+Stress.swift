#if DEBUG
import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

extension AppleDemoSeeder {
    /// Synthetic inputs go through the production engine so demo summaries and charts agree.
    static func stressDemoDay(dayKey: String, now: Date = Date()) -> StressMonitor.DayResult? {
        guard let b = Repository.stressDayBounds(dayKey, now: now), b.end > b.start else { return nil }
        let main = StressMonitor.Interval(start: b.start - 3600, end: b.start + 7 * 3600)
        let activity = StressMonitor.Interval(start: b.start + 17 * 3600, end: b.start + 18 * 3600)
        let dayIndex = b.start / 86_400
        let highEpochs = 3 + abs(dayIndex % 13)
        var hr: [HRSample] = []
        // 1 Hz input for one minute in each five-minute epoch satisfies the production coverage gate.
        for ts in stride(from: main.start, to: b.end, by: StressMonitor.epochSeconds) {
            let epoch = (ts - main.start) / StressMonitor.epochSeconds
            let hour = (ts - b.start) / 3600
            let bpm: Int
            if main.contains(ts) { bpm = epoch < highEpochs ? 64 : 52 }
            else if activity.contains(ts) { bpm = 130 }
            else if hour >= 11 && hour < 13 { bpm = 80 + abs(dayIndex % 4) }
            else if hour >= 19 { bpm = 55 }
            else { bpm = 62 + abs(dayIndex % 6) }
            for second in 0..<60 where ts + second < b.end { hr.append(HRSample(ts: ts + second, bpm: bpm)) }
        }
        let input = StressMonitor.DayInput(day: dayKey, dayStart: b.start, dayEnd: b.end,
                                          tzOffsetSeconds: TimeZone.current.secondsFromGMT(), hr: hr,
                                          rr: [], gravity: [], sleepWindows: [main], mainSleep: main,
                                          activityWindows: [activity])
        return StressMonitor.analyzeDay(input, priorFloors: Array(repeating: 60, count: 14),
                                        priorNights: Array(repeating: .init(hr: 52, hrSpread: 2, lnRMSSD: nil,
                                                                         lnRMSSDSpread: nil), count: 14))
    }

    static func seedStress(into store: WhoopStore, deviceId: String) async throws {
        let today = Repository.localDayKey(Date())
        var points: [MetricPoint] = []
        for back in (0..<120).reversed() {
            guard let key = Repository.stressDayKey(offset: -back, from: today),
                  let day = stressDemoDay(dayKey: key) else { continue }
            points += day.summary.storedPairs.map { MetricPoint(day: key, key: $0.key, value: $0.value) }
        }
        _ = try await store.upsertMetricSeries(points, deviceId: deviceId)
    }
}
#endif
