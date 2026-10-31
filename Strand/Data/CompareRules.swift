import Charts
import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum CompareRules {
    /// Default starter selection (falls back gracefully if a key is missing).
    static let defaultKeys = ["recovery", "sleep_performance", "weight"]
    /// The persisted selection (comma-joined descriptor ids) resolved against the catalog, else the
    /// defaults. Evaluated at view creation (the `selected` initial value) so Compare renders the saved
    /// selection on the first frame. Twin of the Android `ComparePrefs.readSelection`. The literals
    /// mirror `minSelection` / `maxSelection` below (a static initial value can't read instance members).
    static func initialSelection() -> [MetricDescriptor] {
        let raw = UserDefaults.standard.string(forKey: "compare.selectedIds") ?? ""
        return restoreSelection(raw, minSelection: 2, maxSelection: 4) ?? defaultSelection()
    }
    /// The default starter selection from `defaultKeys` (graceful when a key is missing).
    static func defaultSelection() -> [MetricDescriptor] {
        var picks: [MetricDescriptor] = []
        for key in defaultKeys {
            if let m = MetricCatalog.all.first(where: { $0.key == key }) { picks.append(m) }
        }
        if picks.isEmpty { picks = Array(MetricCatalog.all.prefix(2)) }
        return Array(picks.prefix(4))   // maxSelection
    }
    /// Restore a persisted Compare selection (comma-joined descriptor ids), or nil to fall back to the
    /// defaults. Twin of the Android `parseCompareSelection` (#358): resolve each id against the catalog,
    /// dedupe, cap at `maxSelection`; restore when EVERY saved id still resolves (so a deliberate
    /// sub-minimum selection is honored) OR at least `minSelection` survive — nil only when a catalog
    /// change dropped the saved ids below the minimum (the stale-selection case). Pure for testability.
    static func restoreSelection(_ raw: String, minSelection: Int, maxSelection: Int) -> [MetricDescriptor]? {
        let tokens = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        var seen = Set<String>()
        var parsed: [MetricDescriptor] = []
        for id in tokens {
            guard seen.insert(id).inserted else { continue }   // first occurrence only (dedupe)
            if let m = MetricCatalog.all.first(where: { $0.id == id }) {
                parsed.append(m)
                if parsed.count == maxSelection { break }
            }
        }
        let uniqueSaved = Set(tokens).count
        return (parsed.count == uniqueSaved || parsed.count >= minSelection) ? parsed : nil
    }
}

/// The canonical Strand range window. `days == nil` means ALL of history.
enum CompareRange: String, CaseIterable, Identifiable {
    case week, month, quarter, half, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:    return String(localized: "W")
        case .month:   return String(localized: "M")
        case .quarter: return String(localized: "3M")
        case .half:    return String(localized: "6M")
        case .year:    return String(localized: "1Y")
        case .all:     return String(localized: "ALL")
        }
    }

    /// The trailing window length in days; nil = everything.
    var days: Int? {
        switch self {
        case .week:    return 7
        case .month:   return 30
        case .quarter: return 90
        case .half:    return 180
        case .year:    return 365
        case .all:     return nil
        }
    }

    /// A human phrase for sentences ("over 1Y").
    var phrase: String {
        switch self {
        case .week:    return String(localized: "the last 7 days")
        case .month:   return String(localized: "30 days")
        case .quarter: return String(localized: "3 months")
        case .half:    return String(localized: "6 months")
        case .year:    return String(localized: "1 year")
        case .all:     return String(localized: "all history")
        }
    }

    /// This range plus every LARGER range, ascending — the auto-expand search order
    /// when a selected window holds zero points for a series.
    var widening: [CompareRange] {
        let order: [CompareRange] = [.week, .month, .quarter, .half, .year, .all]
        guard let i = order.firstIndex(of: self) else { return [.all] }
        return Array(order[i...])
    }
}
