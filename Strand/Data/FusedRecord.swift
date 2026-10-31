import StrandAnalytics
import StrandDesign
import SwiftUI

/// One resolved metric row for the fused record — the engine's `FusedMetricPoint` plus the display
/// label + unit this screen needs to render it. The Wave 3 Repository adapter builds these from the
/// rows it already loads (it owns the metric→label/unit mapping there, or reuses this one).
public struct FusedRow: Identifiable, Equatable {
    public let point: FusedMetricPoint
    /// Human label for the metric ("Resting HR", "Steps", "Sleep").
    public let label: String
    /// Optional accent colour world for the row's value (per-metric tint), defaulted to primary text.
    public let accentHex: String?

    public var id: String { point.metric }

    public init(point: FusedMetricPoint, label: String, accentHex: String? = nil) {
        self.point = point
        self.label = label
        self.accentHex = accentHex
    }
}

/// The whole fused day-record this screen renders. Built by the Wave 3 Repository adapter; passed in
/// via init so the view stays pure and previewable.
public struct FusedRecord: Equatable {
    /// The resolved rows, in display order (importance-first, per the hub rule).
    public let rows: [FusedRow]
    /// The device that OWNS the day's scores (from `DayOwnerResolver`) — shown as the day badge so the
    /// scores' single-owner invariant stays honest. Nil when no scored owner exists yet.
    public let dayOwner: FusionSource?
    /// How many distinct sources contributed across the whole record. Drives the single-source
    /// degradation: when ≤ 1 the screen shows a plain record with no provenance noise.
    public let contributingSourceCount: Int

    public init(rows: [FusedRow], dayOwner: FusionSource?, contributingSourceCount: Int) {
        self.rows = rows
        self.dayOwner = dayOwner
        self.contributingSourceCount = contributingSourceCount
    }
}

/// Formats a fused metric's `Double` value for display by its resolver key. Pure + local to this
/// screen: the engine deals in numbers, the UI owns units. Sleep/duration keys read as "7h 12m";
/// temp as "34.1 °C" / "93.4 °F" per the reader's preference; HR/HRV/steps as plain
/// integers with the right unit.
enum FusionFormat {
    static func value(_ v: Double, metricKey: String, temperature: TemperatureUnit) -> String {
        switch MetricArbitrationPolicy.kind(forKey: metricKey) {
        case .restingHR, .heartRate:
            return "\(Int(v.rounded())) bpm"
        case .hrv:
            return "\(Int(v.rounded())) ms"
        case .spo2:
            return "\(Int(v.rounded()))%"
        case .skinTemp:
            // #111/#622: this column is BIMODAL — CSV/Health imports carry an ABSOLUTE wrist °C (~30-35),
            // the live BLE pipeline a signed DEVIATION from baseline. Fusion is the one screen that can
            // show both at once, side by side, so the conversion cannot be assumed: +32 belongs only to
            // the absolute reading, and applying it to a −4.2 deviation is what once printed "24.4 °F".
            // SkinTempDisplay picks the conversion AND the chip ("°F" vs "Δ°F") from the value itself.
            return SkinTempDisplay.format(v, fahrenheit: temperature == .fahrenheit)
        case .steps:
            return integerGrouped(v)
        case .sleep:
            return duration(minutes: v)
        case .calories:
            return "\(integerGrouped(v)) kcal"
        case .other:
            // Unknown unit: a trimmed number, no fake unit.
            return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        }
    }

    /// "8,420" — grouped integer.
    private static func integerGrouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }

    /// "7h 12m" from a minutes value; "52m" under an hour; "0m" for nothing.
    private static func duration(minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }
}
