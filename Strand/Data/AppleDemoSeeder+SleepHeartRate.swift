#if DEBUG
import Foundation
import WhoopProtocol
import WhoopStore

extension AppleDemoSeeder {
    /// Raw synthetic inputs for the descriptive Sleep cards and the existing body-clock phase fit.
    /// No card result is seeded: the Repository adapters and production engines calculate them.
    static func seedSleepHeartRate(into store: WhoopStore, sleeps: [CachedSleepSession]) async throws {
        let now = Int(Date().timeIntervalSince1970)
        let from = now - 40 * 86_400
        let nights = sleeps.filter { $0.endTs >= from && $0.endTs - $0.effectiveStartTs >= 4 * 3600 }
        let ranges = sleeps.map { $0.effectiveStartTs..<$0.endTs }
        var samples: [Int: HRSample] = [:]
        for ts in stride(from: (from / 300 + 1) * 300, to: now, by: 300) {
            let localHour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: Double(ts)))
            let wave = cos((Double(localHour) - 15) / 24 * 2 * .pi)
            let asleep = ranges.contains { $0.contains(ts) }
            let baseline = nights.first { $0.effectiveStartTs <= ts && ts < $0.endTs }?.restingHr ?? 54
            let bpm = asleep ? baseline : Int((72 + 12 * wave).rounded())
            samples[ts] = HRSample(ts: ts, bpm: bpm)
        }
        for (index, night) in nights.enumerated() {
            let mean = 62 + index % 7
            for ts in stride(from: night.effectiveStartTs - 1800, to: min(night.effectiveStartTs, now), by: 60) {
                samples[ts] = HRSample(ts: ts, bpm: mean + (ts / 60 % 3) - 1)
            }
        }
        var streams = Streams()
        streams.hr = samples.values.sorted { $0.ts < $1.ts }
        _ = try await store.insert(streams, deviceId: whoop)
    }
}
#endif
