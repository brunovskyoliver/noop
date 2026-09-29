import Foundation

// SleepConsistency.swift — the Sleep screen's consistency %, as one pure resolver.
//
// Moved verbatim out of the app target's `SleepModel.consistencySeries` so the Sleep screen and Healthspan
// (Broop Age's sleep-consistency factor) read the SAME value and cannot disagree:
//   • when the imported `sleep_consistency` series covers the newest day, the imported values win;
//   • otherwise the APPROXIMATE rolling bedtime-spread score: for each night, the population SD of the
//     bedtimes over that night and the 13 before it, scored 100 · (1 − SD / 120 min), clamped 0…100, and
//     only once at least 3 nights are in the window.
public enum SleepConsistency {

    /// Rolling window length, nights (the current night plus the 13 before it).
    public static let windowNights = 14
    public static let minNights = 3

    /// Bedtime as minutes on one continuous evening scale: onsets before noon wrap past midnight
    /// (00:30 → 1470), so a 23:30 and a 00:30 bedtime sit 60 minutes apart.
    public static func bedMinutes(hour: Int, minute: Int) -> Double {
        var m = Double(hour * 60 + minute)
        if m < 12 * 60 { m += 24 * 60 }
        return m
    }

    /// One night: the local day it is keyed to and its bedtime on the `bedMinutes` scale.
    public struct Night: Equatable, Sendable {
        public var day: String
        public var bedMinutes: Double
        public init(day: String, bedMinutes: Double) { self.day = day; self.bedMinutes = bedMinutes }
    }

    /// Rolling bedtime-spread score for each night in `bedMinutes` (oldest first); nil for the first
    /// nights, before `minNights` are in the window.
    public static func rollingScores(bedMinutes mins: [Double]) -> [Double?] {
        guard mins.count >= minNights else { return Array(repeating: nil, count: mins.count) }
        var out: [Double?] = []
        out.reserveCapacity(mins.count)
        for i in mins.indices {
            let lo = Swift.max(0, i - (windowNights - 1))
            let window = Array(mins[lo...i])
            guard window.count >= minNights else { out.append(nil); continue }
            let m = window.reduce(0, +) / Double(window.count)
            let variance = window.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(window.count)
            let sd = variance.squareRoot()
            out.append(Swift.max(0, Swift.min(100, 100 * (1 - sd / 120))))
        }
        return out
    }

    /// The consistency series the Sleep screen shows, keyed by day, oldest first.
    /// - Parameters:
    ///   - dayKeys: the merged daily rows' days, oldest first (the newest decides imported vs computed).
    ///   - importedPct: imported `sleep_consistency` by day.
    ///   - nights: one entry per night, oldest first.
    public static func resolve(dayKeys: [String], importedPct: [String: Double],
                               nights: [Night]) -> [(day: String, pct: Double)] {
        if let last = dayKeys.last, importedPct[last] != nil {
            return dayKeys.compactMap { d in importedPct[d].map { (day: d, pct: $0) } }
        }
        let scores = rollingScores(bedMinutes: nights.map(\.bedMinutes))
        var out: [(day: String, pct: Double)] = []
        for (n, s) in zip(nights, scores) { if let s { out.append((day: n.day, pct: s)) } }
        return out
    }
}
