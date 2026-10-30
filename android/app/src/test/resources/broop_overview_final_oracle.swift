// Standalone oracle extracted from BroopOverviewCoupled.sleepNeed, OverviewHRChart annotation scoping,
// and RecoveryScorer.skinTempRelative on 2026-10-19. Foundation-only shape adapters replace UI/store types.
// Run: swiftc -O broop_overview_final_oracle.swift -o oracle && ./oracle
import Foundation
struct SleepSpan { let start: Date; let end: Date; let label: String }
struct WorkoutSpan { let start: Date; let end: Date; let symbol: String }
enum OverviewHRChart {
    public static func mainSleep(_ candidates: [SleepSpan], overlapping window: ClosedRange<Date>) -> SleepSpan? {
        candidates
            .filter { $0.end > window.lowerBound && $0.start < window.upperBound }
            .max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) })
    }

    /// The workout spans overlapping a visible window (a glyph for an out-of-window workout would be
    /// clamp-dragged to the plot edge and lie about its time). Edge-touching spans are kept — mirrors
    /// the classic Today's inclusive workout filter. Order preserved. Pure.
    public static func workouts(_ candidates: [WorkoutSpan], overlapping window: ClosedRange<Date>) -> [WorkoutSpan] {
        candidates.filter { $0.end >= window.lowerBound && $0.start <= window.upperBound }
    }

}
enum Coupled {
    static func sleepNeed(_ imported: Double?, _ bankedInput: [Double?]) -> Double {
        if let need = imported, need > 0 { return need }
        let banked = bankedInput.compactMap { $0 }.filter { $0 > 0 }
        return max(450, banked.isEmpty ? 450 : banked.reduce(0, +) / Double(banked.count))
    }
}

let needCases: [(Double?, [Double?])] = [(nil, []), (nil, [0, -2, nil]), (nil, [300, 400]), (nil, [480, 600, nil, 0]), (350, [800]), (0, [480]), (-1, [420, 600])]
for (imported, banked) in needCases { print(String(format: "%.3f", Coupled.sleepNeed(imported, banked))) }
let windows: [(Double, Double)] = [(100, 200), (0, 100), (200, 300), (101, 199), (-100, 0), (300, 400)]
let sleeps: [SleepSpan] = [(-100.0, 110.0, "long"), (100.0, 200.0, "main"), (120.0, 150.0, "nap"), (200.0, 260.0, "after"), (0.0, 100.0, "edge")].map { SleepSpan(start: Date(timeIntervalSince1970: $0.0), end: Date(timeIntervalSince1970: $0.1), label: $0.2) }
let workouts: [WorkoutSpan] = [(0.0, 100.0, "left"), (100.0, 200.0, "inside"), (200.0, 250.0, "right"), (300.0, 400.0, "outside")].map { WorkoutSpan(start: Date(timeIntervalSince1970: $0.0), end: Date(timeIntervalSince1970: $0.1), symbol: $0.2) }
for (lo, hi) in windows {
 let w = Date(timeIntervalSince1970: lo)...Date(timeIntervalSince1970: hi)
 print((OverviewHRChart.mainSleep(sleeps, overlapping: w)?.label ?? "nil") + "|" + OverviewHRChart.workouts(workouts, overlapping: w).map(\.symbol).joined(separator: ","))
}
let ties = [SleepSpan(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 150), label: "first"), SleepSpan(start: Date(timeIntervalSince1970: 120), end: Date(timeIntervalSince1970: 170), label: "second")]
print(OverviewHRChart.mainSleep(ties, overlapping: Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 200))?.label ?? "nil")

public struct SkinTempRelative: Equatable, Sendable, Codable {

    /// Relative tier: where tonight's skin temp sits versus the personal baseline. NOT a
    /// clinical absolute - purely a deviation band.
    public enum Tier: String, Equatable, Sendable, Codable {
        case cooler   // meaningfully below the personal baseline
        case typical  // within the normal personal range
        case warmer   // meaningfully above the personal baseline
    }

    /// Signed deviation from the personal baseline, in °C (value - baseline). + is warmer.
    public let deviationC: Double
    /// The relative tier for that deviation.
    public let tier: Tier

    public init(deviationC: Double, tier: Tier) {
        self.deviationC = deviationC
        self.tier = tier
    }
}


enum RecoveryScorer {
    public static let skinTempTypicalBandC: Double = 0.3

    /// Build the RELATIVE skin-temp marker from a signed deviation (°C from the personal
    /// baseline). Returns nil when no deviation is available (no baseline yet / not worn), so
    /// the UI shows nothing rather than a fake absolute. The tier is a deviation band only.
    public static func skinTempRelative(deviationC: Double?) -> SkinTempRelative? {
        guard let dev = deviationC else { return nil }
        let tier: SkinTempRelative.Tier
        if dev > skinTempTypicalBandC {
            tier = .warmer
        } else if dev < -skinTempTypicalBandC {
            tier = .cooler
        } else {
            tier = .typical
        }
        return SkinTempRelative(deviationC: dev, tier: tier)
    }

}
for value in [-0.31, -0.3, 0, 0.3, 0.31] { print(RecoveryScorer.skinTempRelative(deviationC: value)!.tier.rawValue) }
