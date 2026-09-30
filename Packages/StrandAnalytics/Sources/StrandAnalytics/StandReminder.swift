import Foundation
import WhoopProtocol

// StandReminder.swift — the pure core of the hourly "stand and move" reminder (2026-09-26).
//
// The shape follows Apple Watch's stand reminder and Fitbit's reminders to move: each hour inside the
// user's day has a small movement goal, and if it is still unmet at :50 the user gets one nudge with
// ten minutes left to earn the hour. What this engine adds is that the day is not a fixed 9-to-5:
//
//  1. UP MINUTES. A wrist strap cannot see posture, so "standing" means an upright, moving minute: at
//     least `gaitTicksPerUpMinute` walk/run ticks from the strap's activity class (WHOOP 5/MG), or a
//     mean per-sample gravity delta of at least `upDeltaG` (every strap, including WHOOP 4.0, which has
//     no activity class). Calibrated on 21 days of 1 Hz 5/MG data: gait minutes read 0.28 g median,
//     desk minutes 0.06, sleep 0.001.
//  2. A LEARNED DAY. Every finished hour is folded into a compact history with its covered, up and
//     still minute counts. An hour where under half the covered minutes are dead still is an awake,
//     worn hour (98% agreement with recorded sleep sessions on the same data). The reminder window is
//     the longest run of hours awake on at least 80% of recent days, learned separately for weekdays
//     and weekends, minus its last hour, which is left for winding down.
//  3. LEARNED MUTING. HeartSteps (Klasnja et al. 2019) found activity prompts stop working once they
//     are ignored as routine. Each reminder's outcome is checked 15 min later; an hour slot whose last
//     three reminders were all ignored is muted for a week (a meeting, a lecture, a commute), then
//     probed again with one reminder.
//  4. LIVE GUARDS. No reminder when the strap is off, the data is stale, the last half hour looks like
//     sleep or a strap on a table, the user is walking right now, the daily cap is reached, or the user
//     paused reminders for the day.
//
// PURITY: no I/O, no clock reads. `nowSec` and `tzOffsetSec` (seconds east of UTC) are passed in. All
// timestamps are unix seconds. APPROXIMATE, not medical advice.

public enum StandReminder {

    // MARK: Calibration (see the header)

    /// Walk/run activity-class ticks (seconds, at 1 Hz) that make a minute an up minute.
    public static let gaitTicksPerUpMinute = 10
    /// Mean per-sample gravity delta (g) that makes a minute an up minute without gait ticks.
    public static let upDeltaG = 0.20
    /// Mean per-sample gravity delta (g) under which a minute is dead still (sleep, or strap off wrist).
    public static let stillDeltaG = 0.01
    /// Samples a minute needs before it counts as observed at all (WHOOP 4.0 records every ~3 s).
    public static let minSamplesPerMinute = 5
    /// Consecutive samples further apart than this contribute no delta.
    public static let maxSampleGapS = 10

    // MARK: Learning / guard constants

    /// Covered minutes an hour needs before it counts toward the learned day.
    public static let minCoveredPerHour = 45
    /// Share of recent days an hour must be awake on to be inside the learned window.
    public static let awakeShare = 0.8
    /// Distinct days of history before a learned window replaces the default.
    public static let minLearnDays = 5
    /// Hour records older than this are dropped.
    public static let historyDays = 35
    /// The window used until enough history exists: 09:00 to 18:00.
    public static let defaultWindow = Window(startHour: 9, endHour: 18)
    /// A reminder counts as answered when this many up minutes follow it within `responseWindowS`.
    public static let responseUpMinutes = 2
    public static let responseWindowS = 15 * 60
    /// A slot is muted after this many ignored reminders in a row…
    public static let muteAfterIgnored = 3
    /// …for this long after the last of them, then probed again.
    public static let muteForS = 7 * 86_400
    /// Outcomes older than this no longer count.
    public static let outcomeLookbackS = 21 * 86_400
    /// The newest data must be at most this old for the engine to act.
    public static let maxDataAgeS = 20 * 60
    /// Sleep / off-wrist guard: over the last `stillGuardS`, at least this share of covered minutes still.
    public static let stillGuardS = 30 * 60
    public static let stillGuardShare = 0.9

    // MARK: - Types

    /// One observed minute. `start` is the unix second the minute begins at (a multiple of 60).
    public struct Minute: Equatable, Sendable {
        public let start: Int
        public let up: Bool
        public let still: Bool
        public init(start: Int, up: Bool, still: Bool) { self.start = start; self.up = up; self.still = still }
    }

    /// One local clock hour of history. `day` is the local day number (days since 1970-01-01 local).
    public struct HourRecord: Equatable, Codable, Sendable {
        public var day: Int
        public var hour: Int
        public var covered: Int
        public var up: Int
        public var still: Int
        public init(day: Int, hour: Int, covered: Int, up: Int, still: Int) {
            self.day = day; self.hour = hour; self.covered = covered; self.up = up; self.still = still
        }
        /// Worn and awake: enough coverage, and under half of it dead still.
        public var awake: Bool { covered >= StandReminder.minCoveredPerHour && still * 2 < covered }
        public var observed: Bool { covered >= StandReminder.minCoveredPerHour }
    }

    /// The hours reminders may fire in: `startHour` ..< `endHour`, local clock hours.
    public struct Window: Equatable, Codable, Sendable {
        public var startHour: Int
        public var endHour: Int
        public init(startHour: Int, endHour: Int) { self.startHour = startHour; self.endHour = endHour }
        public func contains(_ hour: Int) -> Bool { hour >= startHour && hour < endHour }
    }

    /// What happened after one reminder.
    public struct Outcome: Equatable, Codable, Sendable {
        public var ts: Int
        public var hour: Int
        public var weekend: Bool
        public var responded: Bool
        public init(ts: Int, hour: Int, weekend: Bool, responded: Bool) {
            self.ts = ts; self.hour = hour; self.weekend = weekend; self.responded = responded
        }
    }

    /// User settings.
    public struct Config: Equatable, Sendable {
        public var enabled: Bool
        /// Up minutes that earn the hour.
        public var goalMinutes: Int
        /// Minute past the hour the reminder fires at.
        public var remindAtMinute: Int
        /// Use the learned window; false uses `manualWindow` for every day.
        public var learnWindow: Bool
        public var manualWindow: Window
        public var maxPerDay: Int
        /// Mute slots the user keeps ignoring.
        public var learnMuting: Bool
        public init(enabled: Bool = false, goalMinutes: Int = 5, remindAtMinute: Int = 50,
                    learnWindow: Bool = true, manualWindow: Window = StandReminder.defaultWindow,
                    maxPerDay: Int = 8, learnMuting: Bool = true) {
            self.enabled = enabled; self.goalMinutes = goalMinutes; self.remindAtMinute = remindAtMinute
            self.learnWindow = learnWindow; self.manualWindow = manualWindow
            self.maxPerDay = maxPerDay; self.learnMuting = learnMuting
        }
    }

    /// Everything carried between evaluations. The caller persists it verbatim.
    public struct State: Equatable, Codable, Sendable {
        public var history: [HourRecord] = []
        public var outcomes: [Outcome] = []
        /// Fire time of the reminder currently scheduled with the OS (0 = none).
        public var scheduledFireAt = 0
        /// When the last reminder fired (0 = never), and whether its outcome has been recorded.
        public var lastReminderTs = 0
        public var lastReminderResolved = true
        /// Reminders fired on local day `countDay`.
        public var countDay = 0
        public var countToday = 0
        /// No reminders before this instant ("Pause for today").
        public var pausedUntil = 0
        public init() {}
    }

    public enum Action: Equatable, Sendable {
        /// Nothing to change.
        case keep
        /// Remove any scheduled reminder.
        case clear
        /// Schedule (or keep) the reminder at `fireAt`.
        case schedule(fireAt: Int)
        /// The reminder time has passed with the goal unmet: remind now.
        case remindNow
    }

    public struct Decision: Equatable, Sendable {
        public let action: Action
        /// Why, for the strap log. Names only what the engine observed.
        public let reason: String
        /// Up minutes so far in the current hour.
        public let upThisHour: Int
        public let nextState: State
    }

    // MARK: - Minutes

    /// Fold raw samples into observed minutes. Samples need not be sorted; steps may be empty (WHOOP 4.0).
    public static func minutes(gravity: [GravitySample], steps: [StepSample]) -> [Minute] {
        var n: [Int: Int] = [:], sum: [Int: Double] = [:], gait: [Int: Int] = [:]
        var prev: GravitySample?
        for g in gravity.sorted(by: { $0.ts < $1.ts }) {
            let m = floorDiv(g.ts, 60) * 60
            n[m, default: 0] += 1
            if let p = prev, g.ts - p.ts <= maxSampleGapS {
                let dx = g.x - p.x, dy = g.y - p.y, dz = g.z - p.z
                let d = (dx * dx + dy * dy + dz * dz).squareRoot()
                if d.isFinite { sum[m, default: 0] += d }
            }
            prev = g
        }
        for s in steps where s.activityClass == 1 || s.activityClass == 2 {
            gait[floorDiv(s.ts, 60) * 60, default: 0] += 1
        }
        return n.keys.sorted().compactMap { m in
            let count = n[m]!
            guard count >= minSamplesPerMinute else { return nil }
            let mean = (sum[m] ?? 0) / Double(count)
            return Minute(start: m, up: (gait[m] ?? 0) >= gaitTicksPerUpMinute || mean >= upDeltaG,
                          still: mean < stillDeltaG)
        }
    }

    // MARK: - Local clock helpers

    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }

    /// Local day number of `ts`.
    public static func localDay(_ ts: Int, tzOffsetSec: Int) -> Int { floorDiv(ts + tzOffsetSec, 86_400) }
    /// Local clock hour of `ts`.
    public static func localHour(_ ts: Int, tzOffsetSec: Int) -> Int {
        (ts + tzOffsetSec - localDay(ts, tzOffsetSec: tzOffsetSec) * 86_400) / 3600
    }
    /// Saturday or Sunday. Day 0 (1970-01-01) was a Thursday.
    public static func isWeekend(day: Int) -> Bool {
        let wd = ((day + 4) % 7 + 7) % 7   // 0 = Sunday … 6 = Saturday
        return wd == 0 || wd == 6
    }
    /// Unix second the local hour `hour` of local day `day` starts at.
    public static func hourStart(day: Int, hour: Int, tzOffsetSec: Int) -> Int {
        day * 86_400 + hour * 3600 - tzOffsetSec
    }

    // MARK: - History

    /// Hour records for every local hour the minutes touch.
    public static func hourRecords(_ minutes: [Minute], tzOffsetSec: Int) -> [HourRecord] {
        var out: [String: HourRecord] = [:]
        var order: [String] = []
        for m in minutes {
            let day = localDay(m.start, tzOffsetSec: tzOffsetSec), hour = localHour(m.start, tzOffsetSec: tzOffsetSec)
            let key = "\(day):\(hour)"
            if out[key] == nil { out[key] = HourRecord(day: day, hour: hour, covered: 0, up: 0, still: 0); order.append(key) }
            out[key]!.covered += 1
            if m.up { out[key]!.up += 1 }
            if m.still { out[key]!.still += 1 }
        }
        return order.map { out[$0]! }
    }

    /// Replace same-hour records with `fresh` ones and drop records older than `historyDays`. A fresh
    /// record that covers fewer minutes than the stored one is a partial view of the hour (the oldest hour
    /// of a rolling lookback window) and does not replace it.
    public static func merged(_ history: [HourRecord], with fresh: [HourRecord], today: Int) -> [HourRecord] {
        var byKey: [Int: HourRecord] = [:]
        for r in history { byKey[r.day * 24 + r.hour] = r }
        for r in fresh {
            let key = r.day * 24 + r.hour
            if let kept = byKey[key], kept.covered > r.covered { continue }
            byKey[key] = r
        }
        return byKey.values.filter { $0.day > today - historyDays }
            .sorted { ($0.day, $0.hour) < ($1.day, $1.hour) }
    }

    // MARK: - Learned window

    /// Pseudo-days of the other day type's share mixed into each hour. Weekends are two days in seven,
    /// so on a month of history an hour may have been seen awake only two or three times; the prior
    /// keeps one odd Saturday from cutting the window, and fades as that day type's own days pile up.
    public static let otherDayTypePrior = 2.0

    /// The learned reminder window for weekdays or weekends, or nil while there is too little history
    /// (under `minLearnDays` observed days in total).
    public static func learnedWindow(_ history: [HourRecord], weekend: Bool) -> Window? {
        let observed = history.filter(\.observed)
        guard Set(observed.map(\.day)).count >= minLearnDays else { return nil }
        // nil = not enough evidence either way; such an hour neither starts nor breaks a run.
        var awakeHour = [Bool?](repeating: nil, count: 24)
        for h in 0..<24 {
            let rows = observed.filter { $0.hour == h }
            let same = rows.filter { isWeekend(day: $0.day) == weekend }
            let other = rows.filter { isWeekend(day: $0.day) != weekend }
            let k = other.isEmpty ? 0 : otherDayTypePrior
            guard Double(same.count) + k >= 3 else { continue }
            let otherShare = other.isEmpty ? 0 : Double(other.filter(\.awake).count) / Double(other.count)
            let share = (Double(same.filter(\.awake).count) + k * otherShare) / (Double(same.count) + k)
            awakeHour[h] = share >= awakeShare
        }
        // Longest run of awake hours, bridging unknown ones; its last hour is left for winding down.
        var best = (0, 0), start = -1, lastAwake = -1
        for h in 0...24 {
            let v: Bool? = h < 24 ? awakeHour[h] : false
            if v == true { if start < 0 { start = h }; lastAwake = h }
            else if v == false, start >= 0 {
                if lastAwake + 1 - start > best.1 - best.0 { best = (start, lastAwake + 1) }
                start = -1
            }
        }
        guard best.1 - best.0 >= 3 else { return nil }
        return Window(startHour: best.0, endHour: best.1 - 1)
    }

    /// The window in force for local day `day`.
    public static func window(for day: Int, config: Config, history: [HourRecord]) -> Window {
        guard config.learnWindow else { return config.manualWindow }
        return learnedWindow(history, weekend: isWeekend(day: day)) ?? defaultWindow
    }

    // MARK: - Learned muting

    /// True when the slot's last `muteAfterIgnored` reminders were all ignored and the newest of them is
    /// under `muteForS` old. Once the mute runs out, the next reminder is a probe: answer it and the slot
    /// is live again, ignore it and it is muted for another week.
    public static func isMuted(hour: Int, weekend: Bool, outcomes: [Outcome], nowSec: Int) -> Bool {
        let slot = outcomes.filter { $0.hour == hour && $0.weekend == weekend && $0.ts > nowSec - outcomeLookbackS }
            .sorted { $0.ts < $1.ts }.suffix(muteAfterIgnored)
        guard slot.count == muteAfterIgnored, slot.allSatisfy({ !$0.responded }) else { return false }
        return nowSec - slot.last!.ts < muteForS
    }

    /// Slots currently muted, as (weekend, hour), for the settings screen.
    public static func mutedSlots(outcomes: [Outcome], nowSec: Int) -> [(weekend: Bool, hour: Int)] {
        var out: [(Bool, Int)] = []
        for weekend in [false, true] {
            for h in 0..<24 where isMuted(hour: h, weekend: weekend, outcomes: outcomes, nowSec: nowSec) {
                out.append((weekend, h))
            }
        }
        return out.map { (weekend: $0.0, hour: $0.1) }
    }

    // MARK: - The decision

    /// Run one evaluation. `minutes` should cover at least the last few hours; `worn` is the live strap
    /// state. Folds finished hours into history, resolves the last reminder's outcome, then decides.
    public static func evaluate(nowSec: Int, tzOffsetSec: Int, minutes: [Minute], worn: Bool,
                                config: Config, state: State) -> Decision {
        var s = state
        let today = localDay(nowSec, tzOffsetSec: tzOffsetSec)
        let hour = localHour(nowSec, tzOffsetSec: tzOffsetSec)
        let thisHourStart = hourStart(day: today, hour: hour, tzOffsetSec: tzOffsetSec)
        let upThisHour = minutes.filter { $0.up && $0.start >= thisHourStart && $0.start <= nowSec }.count

        // A reminder the OS was holding has fired if its time passed without a clear.
        if s.scheduledFireAt > 0 && s.scheduledFireAt <= nowSec {
            record(fired: s.scheduledFireAt, into: &s, tzOffsetSec: tzOffsetSec)
            s.scheduledFireAt = 0
        }

        // Fold finished hours (the current one is still filling).
        let finished = hourRecords(minutes.filter { $0.start < thisHourStart }, tzOffsetSec: tzOffsetSec)
        s.history = merged(s.history, with: finished, today: today)

        // Resolve the last reminder once the data covers the 15 min after it.
        if !s.lastReminderResolved, let newest = minutes.last?.start,
           newest >= s.lastReminderTs + responseWindowS - 60 || nowSec - s.lastReminderTs > 2 * 3600 {
            let answered = minutes.filter {
                $0.up && $0.start >= s.lastReminderTs - 60 && $0.start < s.lastReminderTs + responseWindowS
            }.count >= responseUpMinutes
            let day = localDay(s.lastReminderTs, tzOffsetSec: tzOffsetSec)
            s.outcomes.append(Outcome(ts: s.lastReminderTs, hour: localHour(s.lastReminderTs, tzOffsetSec: tzOffsetSec),
                                      weekend: isWeekend(day: day), responded: answered))
            s.outcomes = s.outcomes.filter { $0.ts > nowSec - outcomeLookbackS }
            s.lastReminderResolved = true
        }
        if s.countDay != today { s.countDay = today; s.countToday = 0 }

        func out(_ a: Action, _ why: String) -> Decision {
            var n = s
            switch a {
            case .clear: n.scheduledFireAt = 0
            case .schedule(let at): n.scheduledFireAt = at
            case .remindNow: record(fired: nowSec, into: &n, tzOffsetSec: tzOffsetSec); n.scheduledFireAt = 0
            case .keep: break
            }
            return Decision(action: a, reason: why, upThisHour: upThisHour, nextState: n)
        }

        guard config.enabled else { return out(.clear, "off") }
        if nowSec < s.pausedUntil { return out(.clear, "paused for today") }
        let win = window(for: today, config: config, history: s.history)
        guard win.contains(hour) else { return out(.clear, "outside window \(win.startHour):00-\(win.endHour):00") }
        if s.lastReminderTs >= thisHourStart { return out(.keep, "already reminded this hour") }
        if s.countToday >= config.maxPerDay { return out(.clear, "daily cap \(config.maxPerDay) reached") }
        if config.learnMuting,
           isMuted(hour: hour, weekend: isWeekend(day: today), outcomes: s.outcomes, nowSec: nowSec) {
            return out(.clear, "hour \(hour) muted after \(muteAfterIgnored) ignored reminders")
        }
        guard worn else { return out(.clear, "strap not worn") }
        guard let newest = minutes.last?.start, nowSec - newest <= maxDataAgeS else {
            return out(.clear, "no motion data from the last \(maxDataAgeS / 60) min")
        }
        if upThisHour >= config.goalMinutes { return out(.clear, "goal met (\(upThisHour) up min)") }
        let recent = minutes.filter { $0.start > nowSec - stillGuardS }
        if recent.count >= 10, Double(recent.filter(\.still).count) >= stillGuardShare * Double(recent.count) {
            return out(.clear, "last 30 min dead still (asleep or strap off)")
        }
        if minutes.suffix(3).filter(\.up).count >= 2, newest >= nowSec - 5 * 60 {
            return out(.clear, "moving now")
        }
        let fireAt = thisHourStart + config.remindAtMinute * 60
        if nowSec < fireAt {
            return s.scheduledFireAt == fireAt ? out(.keep, "still due at :\(config.remindAtMinute)")
                                               : out(.schedule(fireAt: fireAt), "\(upThisHour)/\(config.goalMinutes) up min")
        }
        return out(.remindNow, "\(upThisHour)/\(config.goalMinutes) up min at :\(localMinute(nowSec, tzOffsetSec))")
    }

    static func localMinute(_ ts: Int, _ tz: Int) -> Int { ((ts + tz) % 3600 + 3600) % 3600 / 60 }

    private static func record(fired ts: Int, into s: inout State, tzOffsetSec: Int) {
        // An unresolved earlier reminder with no data after it counts as ignored.
        if !s.lastReminderResolved && s.lastReminderTs > 0 {
            let day = localDay(s.lastReminderTs, tzOffsetSec: tzOffsetSec)
            s.outcomes.append(Outcome(ts: s.lastReminderTs, hour: localHour(s.lastReminderTs, tzOffsetSec: tzOffsetSec),
                                      weekend: isWeekend(day: day), responded: false))
        }
        s.lastReminderTs = ts
        s.lastReminderResolved = false
        let day = localDay(ts, tzOffsetSec: tzOffsetSec)
        if s.countDay != day { s.countDay = day; s.countToday = 0 }
        s.countToday += 1
    }
}
