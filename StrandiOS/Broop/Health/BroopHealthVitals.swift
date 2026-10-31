#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

/// The vital signs every Broop Health surface shows, resolved once through `BodyVitalSigns` with the
/// same inputs the Health screen and `BroopStore` pass (unit prefs, the #1118 HRV over-count
/// flags and the default-off SpO₂ candidate). `core` is exactly `BroopVitals.readings`, so the Home tile,
/// the Health tab strip and the Health Monitor grid count the same five metrics.
struct BroopHealthVitalSet {
    var all: [BodyVitalReading] = []

    /// The five banded vitals, in WHOOP order (resp, SpO₂, RHR, HRV, skin temp).
    var core: [BodyVitalReading] {
        ["resp", "spo2", "rhr", "hrv", "skin"].compactMap { k in all.first { $0.key == k } }
    }
    /// The uncalibrated WHOOP 4.0 raw SpO₂ tile, only when it decoded a value.
    var raw: BodyVitalReading? { all.first { $0.key == "spo2raw" && $0.value != nil } }

    var withData: [BodyVitalReading] { core.filter { $0.banding.band != .noData } }
    var outliers: [BodyVitalReading] { core.filter { $0.banding.band == .outOfRange } }

    @MainActor
    static func load(repo: Repository) async -> BroopHealthVitalSet {
        let overCount = await repo.exploreSeries(key: "hrv_rr_overcount", source: "my-whoop", days: 14)
        let hrvOverCountByDay = Dictionary(overCount.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        var spo2CandidateByDay: [String: Double] = [:]
        if PuffinExperiment.spo2CandidateDisplayEnabled {
            let pts = await repo.exploreSeries(key: "spo2_candidate", source: "my-whoop", days: 14)
            spo2CandidateByDay = Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        let d = UserDefaults.standard
        let system = UnitSystem(rawValue: d.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let temperature = UnitPrefs.resolveTemperature(system: system, override: d.string(forKey: UnitPrefs.temperatureKey) ?? "")
        let skinPref = SkinTempDisplay.Kind(rawValue: d.string(forKey: UnitPrefs.skinTempDisplayKey) ?? "") ?? .absolute
        let readings = BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows, temperatureUnit: temperature,
                                               spo2CandidateByDay: spo2CandidateByDay,
                                               hrvOverCountByDay: hrvOverCountByDay,
                                               skinTempPreferred: skinPref)
        return BroopHealthVitalSet(all: readings)
    }
}

extension BodyVitalReading {
    /// WHOOP-style card label.
    var broopTitle: String {
        switch key {
        case "resp": return String(localized: "Respiratory Rate")
        case "spo2": return String(localized: "Blood Oxygen (SpO₂)")
        case "rhr": return String(localized: "RHR")
        case "hrv": return String(localized: "HRV")
        case "skin":
            return label == String(localized: "Skin Temp Δ")
                ? String(localized: "Skin Temp (from baseline)") : String(localized: "Skin Temp")
        default: return label
        }
    }

    /// Short label for the five-column strip.
    var broopShort: String {
        switch key {
        case "resp": return String(localized: "Resp")
        case "spo2": return "SpO₂"
        case "rhr": return String(localized: "RHR")
        case "hrv": return String(localized: "HRV")
        case "skin": return String(localized: "Temp")
        default: return label
        }
    }

    var broopSymbol: String {
        switch key {
        case "resp": return "lungs"
        case "spo2", "spo2raw": return "drop"
        case "rhr": return "arrow.down.heart"
        case "hrv": return "waveform.path.ecg"
        default: return "thermometer.medium"
        }
    }

    /// The catalog metric the vital's trend screen opens.
    var broopMetricKey: String? {
        switch key {
        case "resp": return "resp_rate"
        case "spo2": return "spo2"
        case "rhr": return "rhr"
        case "hrv": return "hrv"
        case "skin": return "skin_temp"
        default: return nil
        }
    }

    var broopTone: BroopHealthStatusPill.Tone {
        if key == "spo2raw" { return .none }
        switch banding.band {
        case .inRange: return .good
        case .outOfRange: return .warn
        case .noData: return .none
        }
    }

    /// The same words as the tile caption's state (which yardstick judged the value).
    var broopStateText: String {
        if key == "spo2raw" {
            return banding.band == .noData ? String(localized: "No data") : String(localized: "Uncalibrated")
        }
        switch (banding.band, banding.basis) {
        case (.noData, _): return String(localized: "No data")
        case (.inRange, .personal): return String(localized: "In your range")
        case (.outOfRange, .personal): return String(localized: "Off baseline")
        case (.inRange, .population): return String(localized: "Typical range")
        case (.outOfRange, .population): return String(localized: "Outside range")
        }
    }

    /// The day (and any secondary reading or caveat) under the pill; the missing-value line when empty.
    var broopFootnote: String {
        guard let day else { return missingCaption }
        var parts = secondary.map { [$0] } ?? []
        parts.append(Self.dayLabel(day))
        if let caveat { parts.append(caveat) }
        return parts.joined(separator: " · ")
    }
}
#endif
