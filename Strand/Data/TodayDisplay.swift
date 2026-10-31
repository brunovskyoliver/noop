import Foundation
import StrandAnalytics
import StrandDesign
import SwiftUI
import WhoopProtocol
import WhoopStore

/// Rules and formatting behind the screens, kept apart from any one interface.
enum TodayDisplay {
    static func clampedDayOffset(current: Int, delta: Int, maxOffset: Int) -> Int {
        min(max(0, maxOffset), max(0, current + delta))
    }
    static func maxDayOffset(earliestDayKey: String?, todayKey: String) -> Int {
        guard let earliestKey = earliestDayKey,
              let earliest = dayKeyParser.date(from: earliestKey),
              let today = dayKeyParser.date(from: todayKey) else { return 0 }
        let gap = Calendar.current.dateComponents([.day],
                                                  from: Calendar.current.startOfDay(for: earliest),
                                                  to: Calendar.current.startOfDay(for: today)).day ?? 0
        return max(0, gap)
    }
    static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// (A3/B2, docs/bugs/2026-07-15-strap-battery-backfill-observability.md)
    enum StrapBatteryDisplay: Equatable {
        /// No link — say nothing about charge. A stale % is worse than no %.
        case offline
        /// Linked, but no charge reading has landed yet. `charging` is still knowable on its own.
        case pending(charging: Bool)
        /// A reading from the current link. `isRing` says whose: the ring's own charge under an active
        /// ring, the strap's under an active strap — the label names the device the number belongs to.
        case charge(pct: Double, charging: Bool, isRing: Bool)
        /// The active device is neither the strap nor a ring that has reported its charge this link, so
        /// this control has nothing to say and is not drawn.
        ///
        /// Distinct from [offline], which asserts a strap that IS active is not connected. Collapsing the
        /// two put a crossed-out bolt and "strap not connected" on the header of a wearer whose ring was
        /// streaming, which is a different false claim from the one #2208 is about rather than a fix for
        /// it, and the only one a ring-only wearer would see every day. (@pipiche38 on #2216)
        case notActiveDevice

        /// #2208: `activeIsWhoop` is required, not defaulted. `connected` alone was never enough: it is
        /// true the moment ANY source streams, `batteryPct` is the strap's and is never cleared, so under
        /// an active ring both halves of the old gate passed and this drew the strap's charge. Charging
        /// is strap-only for the same reason, so a non-WHOOP active device reports neither of the strap's.
        ///
        /// A ring reports its OWN charge into `ringPct` (`LiveState.ouraBatteryPct`), cleared with the
        /// link, so under a non-WHOOP active device a non-nil `ringPct` is a reading from the ring that is
        /// live right now and is drawn as such; nil (no ring, or none has reported yet) keeps the control
        /// off the header. `ringCharging` is the ring's charger state (`OuraWearState.charging`), the only
        /// charging evidence a ring gives. Same resolution `LiveConsoleReadout.batteryPercent` applies.
        ///
        /// No default values on purpose. A defaulted flag is one a future call site can forget, and
        /// forgetting it reinstates exactly this bug in a form that still compiles.
        static func resolve(activeIsWhoop: Bool, connected: Bool,
                            batteryPct: Double?, charging: Bool?,
                            ringPct: Int?, ringCharging: Bool) -> StrapBatteryDisplay {
            guard activeIsWhoop else {
                guard let ringPct else { return .notActiveDevice }
                return .charge(pct: Double(ringPct), charging: ringCharging, isRing: true)
            }
            guard connected else { return .offline }
            guard let pct = batteryPct else { return .pending(charging: charging == true) }
            return .charge(pct: pct, charging: charging == true, isRing: false)
        }
    }
    /// What the Charge hero can honestly say for the selected day. Pure + static so the truth table is
    /// testable with no clock and no view (`LiquidChargeCarryTests`).
    ///
    /// See `LiquidChargeCarryTests` for the regression this closes: Liquid read `displayDay?.recovery`
    /// raw, so after the 04:00 rollover — or on any day with no scored night — Charge blanked while the
    /// Rest hero (`freshRestScore`) and the vitals (`Repository.lastVitalsDay`) carried right beside it,
    /// and the widget/watch/Live Activity (`Repository.widgetAnchor`, #911) all showed a number.
    ///
    /// The SELECTION is not re-implemented here: callers pass the row `TodayRules.lastScoredRecoveryDay`
    /// picked (its #547 future-day guard included) and the caption comes from `TodayRules.carriedCaption`,
    /// so the two Today screens cannot drift apart.
    enum ChargeDisplay: Equatable {
        /// The selected day scored its own Charge.
        case scored(pct: Double)
        /// No score for the selected day; showing a REAL prior night's, stamped with whose it is.
        case carried(pct: Double, caption: String)
        /// Pre-seed-gate: the baseline is still learning and owns its own "N of 4 nights" copy.
        case calibrating(nights: Int)
        /// Nothing honest to show — no score, no prior night, and not calibrating.
        case noData

        /// The number the hero vessel draws, or nil for the honest empty state. A carry draws the REAL
        /// prior value; the empty states draw nothing rather than a fabricated zero.
        var pct: Double? {
            switch self {
            case .scored(let p): return p
            case .carried(let p, _): return p
            case .calibrating, .noData: return nil
            }
        }

        /// The short Charge-state pill beside the greeting. It shares a row with the greeting under a
        /// `fixedSize`, so it stays SHORT — the carried day's full "Last night · <date>" stamp lives in
        /// `caption`, not here. Only `.calibrating` may say "Calibrating": the pill used to key off
        /// `recovery != nil` and so claimed a calibrating baseline on every unscored day, including a
        /// trusted wearer who simply hadn't worn the strap that night.
        var stateLabel: String {
            switch self {
            case .scored: return String(localized: "Solid")
            case .carried: return String(localized: "Last night")
            case .calibrating: return String(localized: "Calibrating")
            case .noData: return String(localized: "No data")
            }
        }

        /// The synthesis-card detail line while the baseline is still forming — the same "N of
        /// `Baselines.minNightsSeed` nights" progress classic `TodayView.calibrationDetail` surfaces, so a
        /// wearer in their first few nights reads identical calibration copy on both Today screens (before
        /// this, Liquid dropped the count and showed a bare "Calibrating"). Non-nil ONLY for `.calibrating`:
        /// the compact greeting pill stays short ("Calibrating") because it shares a `fixedSize` row with
        /// the greeting, so the count lives here in the card, exactly as classic keeps it out of its
        /// `ScoreStatePill`. Reuses classic's String Catalog key verbatim — one entry serves both screens.
        var calibrationDetail: String? {
            guard case .calibrating(let nights) = self else { return nil }
            return String(localized: "Learning your baseline, \(nights) of \(Baselines.minNightsSeed) nights.")
        }

        /// The reason half, when nights are arriving but most carry no HRV (see `TodayView`'s twin). Nil
        /// when every observed night counted, so a healthy calibration says nothing extra.
        func calibrationReason(dayKeys: [String], nightlyHrv: [Double?], today: String) -> String? {
            guard case .calibrating = self else { return nil }
            let cov = Baselines.recentHrvCoverage(dayKeys: dayKeys, nightlyHrv: nightlyHrv, today: today)
            guard cov.missing > 0, cov.observed > 0 else { return nil }
            return String(localized: "\(cov.missing) of the last \(cov.observed) nights recorded no HRV. Check the strap is worn overnight and syncing.")
        }

        static func resolve(todayRecovery: Double?, priorScored: DailyMetric?,
                            calibrationNights: Int?, todayKey: String) -> ChargeDisplay {
            if let pct = todayRecovery { return .scored(pct: pct) }
            // Calibration owns its own copy and beats the carry — mid-calibration there is no trustworthy
            // prior score to stand in. Mirrors `lastScoredRecoveryDay`, which returns nil when calibrating.
            if let n = calibrationNights { return .calibrating(nights: n) }
            // `lastScoredRecoveryDay` only ever selects a row whose recovery is non-nil, so the second bind
            // is belt-and-suspenders: a nil falls through to noData rather than fabricating a carry.
            guard let prior = priorScored, let pct = prior.recovery else { return .noData }
            return .carried(pct: pct,
                            caption: TodayRules.carriedCaption(priorDayKey: prior.day, todayKey: todayKey))
        }
    }
}
