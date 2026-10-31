import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopStore

/// The W/2W/3W/M/3M/6M/1Y/ALL window, driving the single SegmentedPillControl.
enum ExploreRange: Int, CaseIterable, Identifiable, Hashable {
    case week = 7, twoWeeks = 14, threeWeeks = 21, month = 30, quarter = 90, half = 180, year = 365, all = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .twoWeeks: return String(localized: "2W"); case .threeWeeks: return String(localized: "3W")
        case .week: return String(localized: "W"); case .month: return String(localized: "M"); case .quarter: return String(localized: "3M")
        case .half: return String(localized: "6M"); case .year: return String(localized: "1Y"); case .all: return String(localized: "ALL")
        }
    }
    var name: String {
        switch self {
        case .twoWeeks: return String(localized: "2 weeks"); case .threeWeeks: return String(localized: "3 weeks")
        case .week: return String(localized: "week"); case .month: return String(localized: "month"); case .quarter: return String(localized: "quarter")
        case .half: return String(localized: "6 months"); case .year: return String(localized: "year"); case .all: return String(localized: "all time")
        }
    }
    /// Trailing days the window spans (nil = everything).
    var days: Int? { self == .all ? nil : rawValue }

    /// This range plus every LARGER range, ascending — the auto-expand search order
    /// when the selected window holds zero points. ALW always terminates the chain.
    var widening: [ExploreRange] {
        let order: [ExploreRange] = [.week, .month, .quarter, .half, .year, .all]
        guard let i = order.firstIndex(of: self) else { return [.all] }
        return Array(order[i...])
    }
}

/// The steps-specific adapter between the shared calendar projection and this screen. Keeping the
/// policy pure makes the renderer consume one authoritative bucket series for its chart, headline,
/// statistics and accessibility text while the readings table can continue to show daily inputs.
enum MetricDetailSteps {
    enum Resolution: Equatable {
        case daily
        case weekly
        case monthly
    }

    struct Presentation {
        let buckets: [StepsDetailBucket]
        let resolution: Resolution

        var series: [(day: String, value: Double)] {
            buckets.map { (day: $0.displayDay, value: Double($0.mean)) }
        }

        var accessibilitySummary: String {
            guard let latest = buckets.last else { return String(localized: "Steps chart, no data") }
            let noun = buckets.count == 1 ? String(localized: "bar") : String(localized: "bars")
            let period = MetricDetailSteps.periodLabel(day: latest.displayDay, resolution: resolution)
            switch resolution {
            case .daily:
                return String(localized: "Steps chart, \(buckets.count) daily \(noun), latest \(latest.mean) steps, \(period)")
            case .weekly:
                return String(localized: "Steps chart, \(buckets.count) weekly \(noun), latest \(latest.mean) average steps per observed day, \(period)")
            case .monthly:
                return String(localized: "Steps chart, \(buckets.count) monthly \(noun), latest \(latest.mean) average steps per observed day, \(period)")
            }
        }
    }

    static func isMetric(_ metricKey: String) -> Bool {
        metricKey == "steps" || metricKey == "steps_est"
    }

    static func range(_ range: ExploreRange) -> StepsDetailRange {
        switch range {
        case .week: return .week
        case .twoWeeks: return .twoWeeks
        case .threeWeeks: return .threeWeeks
        case .month: return .month
        case .quarter: return .threeMonths
        case .half: return .sixMonths
        case .year: return .year
        case .all: return .all
        }
    }

    static func resolution(for range: ExploreRange) -> Resolution {
        switch range {
        case .week, .twoWeeks, .threeWeeks, .month: return .daily
        case .quarter: return .weekly
        case .half, .year, .all: return .monthly
        }
    }

    static func widening(from range: ExploreRange) -> [ExploreRange] {
        let order = ExploreRange.allCases
        guard let index = order.firstIndex(of: range) else { return [.all] }
        return Array(order[index...])
    }

    static func presentation(readings: [(day: String, value: Double)], range: ExploreRange,
                             anchorDay: String? = nil) -> Presentation {
        let buckets = StepsDetailDensity.project(
            readings: readings.map { StepsDetailReading(day: $0.day, value: $0.value) },
            range: self.range(range), anchorDay: anchorDay)
        return Presentation(buckets: buckets, resolution: resolution(for: range))
    }

    static func latestValidDay(readings: [(day: String, value: Double)]) -> String? {
        StepsDetailDensity.project(
            readings: readings.map { StepsDetailReading(day: $0.day, value: $0.value) },
            range: .week).last?.displayDay
    }

    /// The finite comparison window ends one day before the current window and has the same number
    /// of local calendar days. The shared projector then applies the same daily/weekly/monthly fold.
    static func previousPresentation(readings: [(day: String, value: Double)], range: ExploreRange,
                                     currentAnchorDay: String) -> Presentation {
        let parts = currentAnchorDay.split(separator: "-")
        guard let dayCount = range.days, parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return Presentation(buckets: [], resolution: resolution(for: range))
        }
        let previousAnchor = LocalCalendarDate(year: year, month: month, day: day)
            .adding(days: -dayCount).key
        return presentation(readings: readings, range: range,
                            anchorDay: previousAnchor)
    }

    static func showsBars(metricKey: String, preferredStyleRaw: String) -> Bool {
        isMetric(metricKey) || TrendChartStyle(rawValue: preferredStyleRaw) == .bar
    }

    static func requiresFullHistory(metricKey: String, range: ExploreRange) -> Bool {
        isMetric(metricKey) && range == .all
    }

    static func loadIdentity(metricID: String, refreshSequence: Int,
                             skinTemperatureStyle: String, range: ExploreRange) -> String {
        let metricKey = metricID.split(separator: ":").last.map(String.init) ?? metricID
        let rangeIdentity = isMetric(metricKey)
            ? "|\(range.rawValue)" : ""
        return "\(metricID)|\(refreshSequence)|\(skinTemperatureStyle)\(rangeIdentity)"
    }

    static func periodLabel(day: String, resolution: Resolution) -> String {
        guard let date = parseDay(day) else { return day }
        switch resolution {
        case .daily:
            return String(localized: "as of \(longDate(date))")
        case .weekly:
            return String(localized: "week of \(longDate(date))")
        case .monthly:
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.activeLocale
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }

    static func countCaption(count: Int, resolution: Resolution, rangeName: String) -> String {
        let noun = count == 1 ? String(localized: "bar") : String(localized: "bars")
        switch resolution {
        case .daily:
            return String(localized: "\(count) daily \(noun) · \(rangeName)")
        case .weekly:
            return String(localized: "\(count) weekly \(noun) · average per observed day · \(rangeName)")
        case .monthly:
            return String(localized: "\(count) monthly \(noun) · average per observed day · \(rangeName)")
        }
    }

    static func valueLabel(_ value: Double, resolution: Resolution) -> String {
        let formatted = value.formatted(.number.locale(AppLanguage.activeLocale).precision(.fractionLength(0)))
        switch resolution {
        case .daily:
            return String(localized: "\(formatted) steps")
        case .weekly, .monthly:
            return String(localized: "\(formatted) average steps per observed day")
        }
    }
}

/// Pure #943 chip-coercion rule, extracted so it can be pinned by a test (the Swift twin of Android's
/// `coercedVitalRange` in HealthScreen.kt). Resolves a stored selection NON-DESTRUCTIVELY: an unlocked
/// selection is kept verbatim; a LOCKED one renders as the largest unlocked range with a real finite
/// window (`days != nil`, so never ALL) whose rawValue is <= the selection, else `.week`. Coercing a
/// locked default to ALL would jump a calibrating user to the everything view, so it is excluded.
enum ExploreRangeGating {
    static func coerced(selection: ExploreRange, isUnlocked: (ExploreRange) -> Bool) -> ExploreRange {
        if isUnlocked(selection) { return selection }
        return [ExploreRange.year, .half, .quarter, .month, .threeWeeks, .twoWeeks, .week]
            .first { $0.days != nil && $0.rawValue <= selection.rawValue && isUnlocked($0) } ?? .week
    }
}

/// One windowed reading behind a vital's detail chart: its day ("YYYY-MM-DD"), the value, and the RAW
/// source id it came from (a strap id, the "-noop" computed sibling, "apple-health", or "health-connect").
/// The readings TABLE and the "N readings" caption both derive from this ONE windowed list, so they can
/// never disagree; the raw source maps to a human label via `TodayRules.provenanceDisplayLabel` — the SAME
/// resolver Today uses, so no source vocabulary is invented. Swift twin of Android's `VitalReading`.
struct VitalReading: Equatable {
    let day: String
    let value: Double
    let source: String
}

// yyyy-MM-dd → Date, fixed UTC / en_US_POSIX (per task spec).
let strandDayParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

func parseDay(_ day: String) -> Date? { strandDayParser.date(from: day) }

/// Localized long date for the hero "as of" line, with a fixed calendar-day time zone.
func longDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = AppLanguage.activeLocale
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}
