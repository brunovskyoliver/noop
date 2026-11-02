import Foundation

// CyclePhaseEngine.swift — on-device menstrual-cycle PHASE AWARENESS from the nightly skin-temperature
// series, corroborated by the luteal resting-HR rise and the luteal HRV drop. Pure, deterministic, DB-free.
//
// INDEPENDENT implementation of a publicly documented method (wrist skin-temperature cycle tracking,
// e.g. PMC11294004, and the broader biphasic-ovulatory-shift literature): skin temperature runs roughly
// 0.3–0.5 °C HIGHER in the luteal phase than the follicular phase, with a nadir around ovulation,
// mirrored by a luteal RESTING-HR RISE and a luteal HRV (RMSSD) DROP. NOOP re-derives this from the
// user's OWN banked nightly signals against their OWN baseline — it reproduces no competitor's model.
//
// WELLNESS / AWARENESS ONLY — APPROXIMATE. This is NOT contraception, NOT a fertility/ovulation predictor,
// NOT a medical device, and NOT a diagnosis. It never frames a "fertile window" or "safe days," never
// emits a single confident period DATE (only a probabilistic WINDOW), and never diagnoses PCOS,
// pregnancy, perimenopause or any condition — when the signal is flat/irregular it says "no clear
// pattern," never a verdict. All of this is the load-bearing legal/ethical framing.
public enum CyclePhaseEngine {

    // MARK: - Tuning constants (pinned by test; iPhone only, the Kotlin twin no longer mirrors these)

    /// Weights for the fused luteal index z = wTemp·zTemp + wRHR·zRHR + wHRV·(−zHRV). Temperature is
    /// dominant (it is the pillar's signal); RHR and HRV corroborate. The HRV term is NEGATED so a drop
    /// pushes the index UP (luteal-ward), matching temp ↑ and RHR ↑.
    public static let wTemp: Double = 0.6
    public static let wRHR: Double = 0.2
    public static let wHRV: Double = 0.2

    /// Persistence rule for a temperature shift, after the wrist-temperature work in PMC8238491: this many
    /// consecutive valid nights each above the highest of the previous `shiftPriorNights`. The paper's
    /// 0.2 °C margin is dropped because the series here is a fused z, not °C. That study reported 0.62
    /// sensitivity and 0.26 specificity against LH tests, so a shift is an observation, never a date.
    public static let shiftConfirmNights: Int = 3
    public static let shiftPriorNights: Int = 6
    /// A shift counts once its run has stayed above the prior nights' mean for this many valid nights.
    public static let minRunNights: Int = 5
    /// Cadence gate (unvalidated, chosen to reject noise): at least this share of onset gaps must be
    /// plausible cycle lengths, and those plausible gaps must spread by no more than `maxGapSpreadDays`.
    public static let minPlausibleGapShare: Double = 2.0 / 3.0
    public static let maxGapSpreadDays: Int = 9

    /// Plausibility clamp on the estimated cycle length (days). Anything outside is treated as "no clear
    /// pattern" rather than a fabricated cadence.
    public static let minCycleDays: Int = 21
    public static let maxCycleDays: Int = 40
    /// Typical cycle length used as the prior for the next-period WINDOW when the personal median isn't
    /// yet reliable. Deliberately a textbook average, not a claim about this user.
    public static let defaultCycleDays: Int = 28
    /// Typical luteal-phase length (days): the temperature shift sits near ovulation and menses follows
    /// about 12 days later (Bull 2019, 612,613 cycles: 12.4 ± 2.4 d). Used for the next-period window when
    /// the anchor is the shift itself rather than a logged period start.
    public static let lutealDays: Int = 12

    /// Minimum number of nights of usable data before the engine will classify at all (~1.5 cycles).
    public static let minNightsToClassify: Int = 42

    // MARK: - Inputs

    /// One night's already-standardized inputs. `tempZ` / `rhrZ` / `hrvZ` are z-scores from
    /// `Baselines.deviation` against each metric's personal baseline (the caller computes them so the
    /// engine stays I/O-free). `day` is a "yyyy-MM-dd" key, oldest→newest in the array. A missing signal
    /// is nil and simply doesn't contribute to that night's fused index.
    public struct Night: Equatable, Sendable {
        public let day: String
        public let tempZ: Double?
        public let rhrZ: Double?
        public let hrvZ: Double?
        public init(day: String, tempZ: Double?, rhrZ: Double?, hrvZ: Double?) {
            self.day = day; self.tempZ = tempZ; self.rhrZ = rhrZ; self.hrvZ = hrvZ
        }
    }

    /// One stored day, before standardizing. `skinTempDevC` is bimodal: an imported row holds absolute
    /// °C and a live row a signed deviation (`VitalBands.isAbsoluteSkinTemp`).
    public struct DayRow: Equatable, Sendable {
        public let day: String
        public let skinTempDevC: Double?
        public let restingHr: Double?
        public let hrv: Double?
        public init(day: String, skinTempDevC: Double?, restingHr: Double?, hrv: Double?) {
            self.day = day; self.skinTempDevC = skinTempDevC; self.restingHr = restingHr; self.hrv = hrv
        }
    }

    /// Standardize stored days for `classify`. Live deviations and imported absolutes fold separately,
    /// each against its own baseline, so neither is scored on the other's scale.
    public static func assemble(_ rows: [DayRow]) -> (nights: [Night], curve: [Double], baselineUsable: Bool) {
        let sorted = rows.sorted { $0.day < $1.day }
        guard let absoluteCfg = Baselines.metricCfg["skin_temp"],
              let rhrCfg = Baselines.metricCfg["resting_hr"],
              let hrvCfg = Baselines.metricCfg["hrv"] else { return ([], [], false) }
        let skin = sorted.map(\.skinTempDevC)
        let deviationState = Baselines.foldHistory(skin.map { $0.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? nil : $0 } },
                                                   cfg: VitalBands.skinTempDeviationCfg)
        let absoluteState = Baselines.foldHistory(skin.map { $0.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil } },
                                                  cfg: absoluteCfg)
        let rhrState = Baselines.foldHistory(sorted.map(\.restingHr), cfg: rhrCfg)
        let hrvState = Baselines.foldHistory(sorted.map(\.hrv), cfg: hrvCfg)

        var nights: [Night] = []
        var curve: [Double] = []
        for row in sorted {
            let tempZ = row.skinTempDevC.flatMap { v -> Double? in
                let state = VitalBands.isAbsoluteSkinTemp(v) ? absoluteState : deviationState
                return state.usable ? Baselines.deviation(v, state: state).z : nil
            }
            let rhrZ = rhrState.usable ? row.restingHr.map { Baselines.deviation($0, state: rhrState).z } : nil
            let hrvZ = hrvState.usable ? row.hrv.map { Baselines.deviation($0, state: hrvState).z } : nil
            nights.append(Night(day: row.day, tempZ: tempZ, rhrZ: rhrZ, hrvZ: hrvZ))
            if let fused = fusedIndex(tempZ: tempZ, rhrZ: rhrZ, hrvZ: hrvZ) { curve.append(fused) }
        }
        return (nights, curve, deviationState.usable || absoluteState.usable)
    }

    // MARK: - Output

    public enum Phase: String, Equatable, Sendable, Codable {
        case follicular
        case periOvulatory
        case luteal
        case unknown        // no clear pattern — NEVER a fabricated phase
        case learning       // not enough data yet
    }

    public enum Confidence: String, Equatable, Sendable, Codable {
        case learning       // < minNightsToClassify, or baseline not usable
        case building       // classifies, but the cadence is still coarse (one elevation seen)
        case solid          // a stable repeating shift detected
    }

    /// A detected follicular→luteal temperature shift onset (for the curve markers).
    public struct ShiftMarker: Equatable, Sendable {
        public let day: String
        public init(day: String) { self.day = day }
    }

    /// A probabilistic next-period WINDOW. Always a range of days, never a single confident date.
    public struct NextPeriodWindow: Equatable, Sendable {
        public let earliestDay: String
        public let latestDay: String
        public init(earliestDay: String, latestDay: String) {
            self.earliestDay = earliestDay; self.latestDay = latestDay
        }
    }

    public struct Result: Equatable, Sendable {
        public let phase: Phase
        public let confidence: Confidence
        /// Inclusive cycle-day estimate as a RANGE, not a point (nil when unknown/learning).
        public let cycleDayLow: Int?
        public let cycleDayHigh: Int?
        /// Estimated personal cycle length in days (nil until a repeat is seen).
        public let cycleLengthDays: Int?
        /// Probabilistic next-period window (nil unless a usable cadence + recent elevation exist).
        public let nextPeriodWindow: NextPeriodWindow?
        /// Temperature-shift onsets across the window (oldest→newest) for the detail curve.
        public let shiftMarkers: [ShiftMarker]
        /// A short, non-clinical status line.
        public let note: String

        public init(phase: Phase, confidence: Confidence, cycleDayLow: Int?, cycleDayHigh: Int?,
                    cycleLengthDays: Int?, nextPeriodWindow: NextPeriodWindow?,
                    shiftMarkers: [ShiftMarker], note: String) {
            self.phase = phase; self.confidence = confidence
            self.cycleDayLow = cycleDayLow; self.cycleDayHigh = cycleDayHigh
            self.cycleLengthDays = cycleLengthDays; self.nextPeriodWindow = nextPeriodWindow
            self.shiftMarkers = shiftMarkers; self.note = note
        }
    }

    /// Standing awareness-only line shown on every cycle surface (legal/ethical framing).
    public static let awarenessLine =
        "For awareness only. Not a medical device, not contraception, not a substitute for professional care."

    // MARK: - Classify

    /// Classify the most recent night from the trailing series.
    ///
    /// - Parameters:
    ///   - nights: oldest→newest nightly inputs.
    ///   - baselineUsable: whether the personal skin-temp baseline is at least `usable` (the caller
    ///     passes `BaselineState.usable`). Below this we stay in `.learning` and never invent a phase.
    ///   - loggedPeriodStarts: optional "yyyy-MM-dd" period-start days the user logged. When present, the
    ///     most recent one anchors cycle-day 1 and we CROSS-VALIDATE it against the detected shift, flagging
    ///     a mistimed log rather than trusting it blindly. Optional — the engine works temperature-only.
    public static func classify(_ nights: [Night],
                                baselineUsable: Bool,
                                loggedPeriodStarts: [String] = []) -> Result {
        // Gate: need a usable baseline and ~1.5 cycles of data.
        guard baselineUsable, nights.count >= minNightsToClassify else {
            return Result(phase: .learning, confidence: .learning, cycleDayLow: nil, cycleDayHigh: nil,
                          cycleLengthDays: nil, nextPeriodWindow: nil, shiftMarkers: [],
                          note: "Learning your pattern from your nightly temperature - keep wearing it overnight.")
        }

        // Fuse each night, keeping valid nights only: a missing night neither breaks a run nor starts one.
        let fused: [(day: String, value: Double)] = nights.compactMap { n in
            fusedIndex(tempZ: n.tempZ, rhrZ: n.rhrZ, hrvZ: n.hrvZ).map { (n.day, $0) }
        }
        guard fused.count >= minNightsToClassify else {
            return Result(phase: .learning, confidence: .learning, cycleDayLow: nil, cycleDayHigh: nil,
                          cycleLengthDays: nil, nextPeriodWindow: nil, shiftMarkers: [],
                          note: "Learning your pattern from your nightly temperature - keep wearing it overnight.")
        }

        let shifts = detectShifts(fused.map(\.value))
        let shiftMarkers = shifts.confirmed.map { ShiftMarker(day: fused[$0].day) }
        let lastNightDay = fused.last!.day

        // Personal cycle length from the median gap between successive confirmed onsets.
        var onsetGaps: [Int] = []
        if shifts.confirmed.count >= 2 {
            for k in 1..<shifts.confirmed.count {
                if let d = daysBetween(fused[shifts.confirmed[k - 1]].day, fused[shifts.confirmed[k]].day) {
                    onsetGaps.append(d)
                }
            }
        }
        let plausibleGaps = onsetGaps.filter { (minCycleDays...maxCycleDays).contains($0) }
        let cadenceRegular = !onsetGaps.isEmpty
            && Double(plausibleGaps.count) / Double(onsetGaps.count) >= minPlausibleGapShare
            && (plausibleGaps.max() ?? 0) - (plausibleGaps.min() ?? 0) <= maxGapSpreadDays
        let hasLoggedStart = mostRecentOnOrBefore(loggedPeriodStarts, day: lastNightDay) != nil
        let recentEnough = shifts.confirmed.last
            .flatMap { daysBetween(fused[$0].day, lastNightDay) }.map { $0 <= maxCycleDays } ?? false

        // Without a repeating shift, or one shift backed by a logged period, the honest answer is
        // "no clear pattern". A shift seen once on noise is common and says nothing about a cycle.
        guard recentEnough, cadenceRegular || (onsetGaps.isEmpty && hasLoggedStart) else {
            return Result(phase: .unknown, confidence: .building, cycleDayLow: nil, cycleDayHigh: nil,
                          cycleLengthDays: nil, nextPeriodWindow: nil, shiftMarkers: shiftMarkers,
                          note: "No clear temperature pattern yet - this can happen with irregular cycles, "
                              + "hormonal birth control, or shift work.")
        }
        // A pending shift (too young to confirm) is the newest temperature turn, so it anchors the estimate.
        let lastOnsetIdx = shifts.pending ?? shifts.confirmed.last!
        let cycleLength: Int? = plausibleGaps.isEmpty ? nil : Int(median(plausibleGaps.map(Double.init)).rounded())
        let confidence: Confidence = cycleLength != nil ? .solid : .building

        // Optional logged-period cross-validation (better mode). The most recent logged start that falls
        // on/before the latest night anchors cycle-day 1; we compare it to the detected onset.
        var note = ""
        var anchorDay = fused[lastOnsetIdx].day      // default anchor = the temperature shift onset
        var anchoredByLog = false
        if let loggedStart = mostRecentOnOrBefore(loggedPeriodStarts, day: lastNightDay) {
            anchorDay = loggedStart
            anchoredByLog = true
            let delta = daysBetween(loggedStart, fused[lastOnsetIdx].day)
            // The temperature SHIFT (luteal onset) sits well after period-start in a normal cycle; an
            // implausible offset OR a logged start older than a full cycle before the latest night (a
            // newer period is overdue) means the log is likely mistimed — FLAG it, don't silently trust.
            let sinceLog = daysBetween(loggedStart, lastNightDay) ?? 0
            if (delta.map { $0 < 0 || $0 > maxCycleDays } ?? false) || sinceLog > maxCycleDays {
                note = "Your temperature shift came at a different time than your logged date - "
                    + "the logged start may be off."
            }
        }

        // Cycle-day estimate as a RANGE. If anchored by a log we count from day 1 at the log; in
        // temperature-only mode we count from the shift onset, which in a typical cycle is the start of
        // the luteal phase (~day 14–16), so we offset by a coarse follicular-length prior.
        let daysSinceAnchor = daysBetween(anchorDay, lastNightDay) ?? 0
        let (cycleDayLow, cycleDayHigh): (Int?, Int?) = {
            if anchoredByLog {
                let d = max(1, daysSinceAnchor + 1)
                return (max(1, d - 1), d + 1)             // ±1 day band
            } else {
                // Shift onset ≈ luteal start; place it near a typical follicular length, widen the band.
                let lutealStartDay = (cycleLength ?? defaultCycleDays) / 2
                let d = lutealStartDay + daysSinceAnchor
                return (max(1, d - 2), d + 2)             // ±2 day band (coarser without a log)
            }
        }()

        // Phase of the most recent night. A shift still short of `minRunNights` is reported as around the
        // turn, not as luteal, because it cannot yet be told from a wobble.
        let phase: Phase = shifts.pending != nil ? .periOvulatory : (shifts.inRunAtEnd ? .luteal : .follicular)

        // Probabilistic next-period WINDOW. Always a RANGE, never a date. A logged period start is day 1,
        // so the next one is about one cycle length on. A temperature-shift anchor sits near ovulation, so
        // the next period is about one luteal phase on; adding a full cycle there landed on the NEXT
        // ovulation instead, roughly two weeks late.
        var window: NextPeriodWindow? = nil
        if let len = cycleLength {
            // Window = ±2 days around the expected start, surfaced once we're within range.
            let ahead = anchoredByLog ? len : lutealDays
            if let earliest = shiftDay(anchorDay, by: ahead - 2),
               let latest = shiftDay(anchorDay, by: ahead + 2),
               latest >= lastNightDay {
                window = NextPeriodWindow(earliestDay: max(lastNightDay, earliest), latestDay: latest)
            }
        }

        if note.isEmpty {
            note = phaseNote(phase)
        }

        return Result(phase: phase, confidence: confidence,
                      cycleDayLow: cycleDayLow, cycleDayHigh: cycleDayHigh,
                      cycleLengthDays: cycleLength, nextPeriodWindow: window,
                      shiftMarkers: shiftMarkers, note: note)
    }

    // MARK: - Shift detection

    /// Find temperature shifts in a series of valid nights, oldest first. Local to a trailing window, so
    /// seasonal drift cannot hold a run high the way a global median does.
    static func detectShifts(_ v: [Double]) -> (confirmed: [Int], pending: Int?, inRunAtEnd: Bool) {
        var confirmed: [Int] = []
        var pending: Int? = nil
        var inRunAtEnd = false
        var i = shiftPriorNights
        while i + shiftConfirmNights <= v.count {
            let prior = v[(i - shiftPriorNights)..<i]
            let top = prior.max()!
            guard v[i..<(i + shiftConfirmNights)].allSatisfy({ $0 > top }) else { i += 1; continue }
            let level = prior.reduce(0, +) / Double(prior.count)
            var end = i + shiftConfirmNights
            while end < v.count, v[end] > level { end += 1 }
            if end - i >= minRunNights {
                confirmed.append(i)
                inRunAtEnd = end == v.count
            } else if end == v.count {
                pending = i
            }
            i = end
        }
        return (confirmed, pending, inRunAtEnd)
    }

    // MARK: - Fusion

    /// Weighted fused luteal index for one night. The HRV z is negated (a drop is luteal-ward). Weights
    /// are renormalised over only the signals that are present, so a temp-only night still scores.
    public static func fusedIndex(tempZ: Double?, rhrZ: Double?, hrvZ: Double?) -> Double? {
        var weighted = 0.0
        var wSum = 0.0
        if let t = tempZ { weighted += wTemp * t; wSum += wTemp }
        if let r = rhrZ { weighted += wRHR * r; wSum += wRHR }
        if let h = hrvZ { weighted += wHRV * (-h); wSum += wHRV }
        guard wSum > 0 else { return nil }
        return weighted / wSum
    }

    // MARK: - Copy

    static func phaseNote(_ phase: Phase) -> String {
        switch phase {
        case .follicular:
            return "Follicular range - temperature sitting at your baseline."
        case .periOvulatory:
            return "Around your mid-cycle shift - temperature is turning."
        case .luteal:
            return "Luteal range - temperature is running above your baseline."
        case .unknown:
            return "No clear pattern yet."
        case .learning:
            return "Learning your pattern - keep wearing it overnight."
        }
    }

    // MARK: - Small stats / day helpers (self-contained so the engine stays I/O-free and parity-clean)

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }

    /// Calendar days from `a` to `b` ("yyyy-MM-dd"), b − a. nil if either is unparseable. UTC, pure.
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = parseDay(a), let db = parseDay(b) else { return nil }
        let secs = db.timeIntervalSince(da)
        return Int((secs / 86_400).rounded())
    }

    /// Most recent entry in `days` that is on or before `day` (string compare is valid for ISO dates).
    static func mostRecentOnOrBefore(_ days: [String], day: String) -> String? {
        days.filter { $0 <= day }.max()
    }

    static func parseDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1, d <= 31 else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)
    }

    /// Shift a "yyyy-MM-dd" by `delta` days. UTC, deterministic. nil if unparseable.
    static func shiftDay(_ day: String, by delta: Int) -> String? {
        guard let base = parseDay(day) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let shifted = cal.date(byAdding: .day, value: delta, to: base) else { return nil }
        let out = cal.dateComponents([.year, .month, .day], from: shifted)
        guard let oy = out.year, let om = out.month, let od = out.day else { return nil }
        return String(format: "%04d-%02d-%02d", oy, om, od)
    }
}
