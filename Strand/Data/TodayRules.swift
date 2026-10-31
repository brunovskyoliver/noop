import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopProtocol
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum TodayRules {
    /// Pure carry-over selector behind `lastScoredRecoveryDay`, extracted so the gate + selection can be
    /// unit-tested without a live view (mirrors `buildingHintCopy` / the Android `lastScoredRecoveryDay`).
    /// Returns the freshest scored prior row to carry over, or nil. `days` is oldest→newest; the chosen
    /// row is the last with a non-nil recovery that ISN'T today's (still-nil) key. nil unless: it's today,
    /// today itself isn't scored, and we're not mid-calibration (calibration owns its own copy), so past
    /// days / a scored today / a calibrating today all carry nothing and live behaviour is unchanged.
    static func lastScoredRecoveryDay(days: [DailyMetric], selectedDayKey: String,
                                      isToday: Bool, todayScored: Bool, isCalibrating: Bool) -> DailyMetric? {
        guard isToday, !todayScored, !isCalibrating else { return nil }
        // Defensive future-day guard (#547): the carry-over must NEVER select a day after today's key, or a
        // stray future-dated row (a bad-clock strap that slipped past the ingest gate / pre-heal DB) would
        // surface as "last night · 12 Jul". `selectedDayKey` is today's logical-day key here (isToday), and
        // yyyy-MM-dd compares lexicographically, so `$0.day < selectedDayKey` keeps only genuine prior days.
        // Belt-and-suspenders on top of the gate + one-time heal, cheap and never wrong.
        return days.last(where: { $0.recovery != nil && $0.day < selectedDayKey })
    }
    /// Carry-over recency cap (#779): the "Last night" framing only holds when the carried scored day is
    /// within this many days of today. A weeks-old import is still carried so the recovery side isn't a bare
    /// blank, but it is relabelled "Latest sleep · <date>" so a stale number is NEVER passed off as today's.
    static let carryFreshnessDays = 2
    /// True when the carried scored day is OLDER than the freshness cap (#779), which drives the "Latest
    /// sleep" relabel. Pure + unit-testable. Both keys are "yyyy-MM-dd"; an unparseable key (or non-positive gap)
    /// reads as fresh so we never over-claim staleness. `todayKey` is today's logical-day key (carry-over is
    /// today-only). Mirror EXACTLY in Kotlin.
    static func isCarryStale(priorDayKey: String, todayKey: String) -> Bool {
        guard let prior = dayKeyParser.date(from: priorDayKey),
              let today = dayKeyParser.date(from: todayKey) else { return false }
        let days = Calendar.current.dateComponents([.day], from: prior, to: today).day ?? 0
        return days > carryFreshnessDays
    }
    /// #977 — HONEST Rest resolution for the selected day. Today's own scored Rest wins; otherwise, ONLY on
    /// today, tail-fall-back to the last scored night — but ONLY when that night is within the carry-freshness
    /// window (`isCarryStale == false`). A live 5.0 whose sleep never scores (no overnight gravity ⇒ no
    /// `sleep_performance` point ever written) used to pin Rest to a weeks-old scored night while Charge kept
    /// advancing; gating the tail-fallback lets the Rest hero fall through to its No-Data/calibrating state
    /// instead of freezing on a stale number. The legitimate morning carry of last night's Rest (before today
    /// scores) is preserved unchanged. Pure + unit-testable. Mirror EXACTLY in Kotlin.
    static func freshRestScore(todayValue: Double?, lastDay: String?, lastValue: Double?,
                               isTodaySelected: Bool, todayKey: String) -> Double? {
        if let v = todayValue { return v }
        guard isTodaySelected, let lastDay, let lastValue,
              !isCarryStale(priorDayKey: lastDay, todayKey: todayKey) else { return nil }
        return lastValue
    }
    /// The carried recovery caption stamp, keyed on that scored day's own date and its recency. Within the
    /// freshness cap it reads "Last night · <date>"; once the carried day is older than the cap (#779) it
    /// reads "Latest sleep · <date>" so a weeks-old import is never surfaced as "Last night". Shared by every
    /// carried recovery read-out so the prior-day provenance reads identically. Mirror EXACTLY in Kotlin.
    static func carriedCaption(priorDayKey: String, todayKey: String) -> String {
        let date = lastChargeDateFmt(priorDayKey)
        return isCarryStale(priorDayKey: priorDayKey, todayKey: todayKey)
            ? String(localized: "Latest sleep · \(date)")
            : String(localized: "Last night · \(date)")
    }
    /// #205 (one-word readiness read kept on the hero: Push / Maintain / Rest). PURE mapping of the
    /// existing `ReadinessEngine.Level` so the hero keeps a glanceable verdict even though the full
    /// Readiness card folds into the Charge breakdown sheet (S4). `insufficient` returns nil (the hero then
    /// shows no readiness word, matching the old card hiding itself). Mirror EXACTLY in Kotlin.
    static func readinessWord(_ level: ReadinessEngine.Level) -> String? {
        switch level {
        case .primed:       return String(localized: "Push")
        case .balanced:     return String(localized: "Maintain")
        case .strained:     return String(localized: "Rest")
        case .rundown:      return String(localized: "Rest")
        case .insufficient: return nil
        }
    }
    /// Parses a stored `yyyy-MM-dd` day key in the device-local zone (matching how DailyMetric.day
    /// is written), local so a key never shifts a day under timezone conversion.
    static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// "d MMM" for a stored `yyyy-MM-dd` day key, used by the carried-over Charge caption (#543). Falls
    /// back to the raw key if it can't be parsed so the caption is never empty.
    static func lastChargeDateFmt(_ dayKey: String) -> String {
        guard let date = dayKeyParser.date(from: dayKey) else { return dayKey }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    /// Product mark, never natural-language copy. Keeping it out of localization also makes source
    /// classification and tint selection stable when the app language changes.
    static let whoopBrandName = "WHOOP"
    /// PURE mapper (unit-testable), a raw resolver source id onto the spec's provenance labels, given
    /// the strap's real `deviceId`. ANY NOOP-computed strap sibling (a "-noop"-suffixed id, not just the
    /// active strap's) reads "On-device" — matching by suffix so a computed row from a non-active strap
    /// can't fall through to `FusionSource.noopComputed`'s raw "NOOP" displayName; the imported strap source
    /// (`deviceId`, normally "my-whoop") reads "Whoop"; the Apple-Health source reads "Apple Health".
    /// Any other real source (Mi Band, Health Connect, nutrition) keeps its `FusionSource.displayName`
    ///, still the genuine merge winner, never a blanket claim. Mirror EXACTLY in Kotlin.
    static func provenanceDisplayLabel(rawSource: String, deviceId: String) -> String {
        if rawSource.hasPrefix(vo2MaxAttributionPrefix) {
            let raw = String(rawSource.dropFirst(vo2MaxAttributionPrefix.count))
            let method = vo2MaxEstimatorDisplayName(Vo2MaxEstimator(rawValue: raw))
            return "\(String(localized: "On-device")) · \(method)"
        }
        // #103/queue-11a follow-up: the Explorer's spo2 candidate-fallback rows (see
        // `spo2CandidateAttributionSource`) must read "strap estimate (unverified)", the SAME copy every
        // other candidate-fallback surface uses — never a device name, which would misrepresent an
        // unvalidated estimate as a calibrated reading in this table's Source column.
        if rawSource == spo2CandidateAttributionSource {
            return String(localized: "strap estimate (unverified)")
        }
        if rawSource.hasSuffix("-noop") { return String(localized: "On-device") }
        if rawSource == deviceId || rawSource == Repository.whoopSource { return Self.whoopBrandName }
        if rawSource == Repository.appleHealthSource { return "Apple Health" }
        // Localize the non-brand source names here rather than exposing the analytics layer's
        // intentionally locale-free wire/display vocabulary on Home.
        switch FusionSource(rawValue: rawSource) {
        case .healthConnect: return "Health Connect"
        case .xiaomiBand:    return "Mi Band"
        case .nutritionCsv:  return String(localized: "Nutrition")
        case .localCache:    return String(localized: "Cached")
        case .whoopImport:   return Self.whoopBrandName
        case .noopComputed:  return String(localized: "On-device")
        case .appleHealth:   return "Apple Health"
        case nil:            return rawSource
        }
    }
}
