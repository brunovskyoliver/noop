import Foundation
import WhoopProtocol

// WorkoutAutoLog.swift — what one day's detection logs as workouts, without asking.
//
// `WorkoutDetector.detect` finds sessions and `WorkoutAutoSave.verdict` decides which of them are lifts,
// runs or rides worth saving. On their own they saved one gym visit as up to five rows (the walk in, two
// lift halves, the walk out) and never saved a walk. This layer, run over the detector's output, makes
// the day's log:
//
//   1. one session per gym visit (`gymVisits`);
//   2. a lift must show the set/rest HR swing (`minLiftHRSwingBPM`);
//   3. optionally, lifts whose HR stays under the detector's activity floor (`lowHRLiftSpans`);
//   4. walks, from the strap's step counter (`walkSpans`), outside every saved session.
//
// Measured 2026-11-21 on one wearer's month (10-22 → 11-21): 13 Apple Watch-logged lifts with strap HR,
// and Apple Health step counts as the walking reference. All constants come from that one person's
// month (N=1); ~/agent-runs/2026-11-21-auto-workout-logging holds the replays.
//
// iPhone only: no Kotlin twin yet. Pure: no clock, no I/O.

public enum WorkoutAutoLog {

    // MARK: - Gym visits

    /// Lift pieces closer than this are one visit (a grip dropout or a long rest between them).
    public static let visitMergeGapS = 20 * 60
    /// How far before a visit's first piece the end of the walk in is looked for. The start moves to the
    /// first minute after that walk: the Watch starts a lift there, and the minutes between (changing,
    /// the first set, a still rest the motion gate dropped) belong to the lift.
    public static let visitLeadS = 20 * 60
    /// A walk piece within this of a visit is the walk to or from the gym: it gets no row of its own,
    /// and the visit does not grow over it. Ending the visit at the last lift minute, not after the walk
    /// home, is deliberate: with the walk out folded in the classifier called 9 of 11 visits a walk.
    public static let visitFoldGapS = 3 * 60

    /// One session per gym visit. Pieces `isLift` accepts join when within `visitMergeGapS`, with
    /// everything between; the start moves to the end of the walk in (`visitLeadS`); walk pieces touching
    /// a visit are dropped. Pieces the lift bar rejects are never joined on: the pottering after a lift
    /// reads like one to every feature here, and joining it moved the end by up to an hour.
    /// `gaitTs` sorted; output sorted by start.
    static func gymVisits(_ sessions: [ExerciseSession], gaitTs: [Int],
                          isWalk: (ExerciseSession) -> Bool, isLift: (ExerciseSession) -> Bool,
                          make: (Int, Int, Bool) -> ExerciseSession?) -> [ExerciseSession] {
        let sessions = sessions.sorted { $0.start < $1.start }
        let lift = sessions.map(isLift)
        guard lift.contains(true) else { return sessions }
        var visits: [(start: Int, end: Int, tier: Bool)] = []
        for (i, s) in sessions.enumerated() where lift[i] {
            if let v = visits.last, s.start - v.end <= visitMergeGapS {
                visits[visits.count - 1].end = max(v.end, s.end)
                visits[visits.count - 1].tier = v.tier && s.isActivityTier
            } else {
                visits.append((s.start, s.end, s.isActivityTier))
            }
        }
        for k in visits.indices {
            // The last sustained walking streak ending in [start - lead, start + 5 min], read from
            // `gaitStreakMinS` earlier so a walk ending at the window's edge still reads whole.
            let a = visits[k].start - visitLeadS - WorkoutDetector.gaitStreakMinS
            var walking = WorkoutDetector.walkingMinutes(start: a, end: visits[k].start + 5 * 60, gaitTs: gaitTs)
            let raw = walking
            if raw.count > 2 { for m in 1..<(raw.count - 1) where !raw[m] && raw[m - 1] && raw[m + 1] { walking[m] = true } }
            var run = 0
            var lastEnd: Int? = nil
            for (m, w) in walking.enumerated() {
                run = w ? run + 1 : 0
                if run * 60 >= WorkoutDetector.gaitStreakMinS, m + 1 == walking.count || !walking[m + 1] {
                    lastEnd = a + (m + 1) * 60
                }
            }
            let floor = k > 0 ? visits[k - 1].end + 1 : Int.min
            if let e = lastEnd { visits[k].start = max(e, floor) }
        }
        var out = visits.compactMap { make($0.start, $0.end, $0.tier) }
        for (i, s) in sessions.enumerated() where !lift[i] {
            let inside = visits.contains { s.start >= $0.start - 60 && s.end <= $0.end + 60 }
            let touches = isWalk(s) && visits.contains { s.start < $0.end + visitFoldGapS && s.end > $0.start - visitFoldGapS }
            if !inside && !touches { out.append(s) }
        }
        return out.sorted { $0.start < $1.start }
    }

    // MARK: - Set/rest HR swing

    /// Spread of HR around its own 6 min moving mean (bpm) a saved lift must show. Lifts read 7.5–13.9,
    /// the pottering after a gym visit 4.0–6.0 and morning routines 4.0–7.2. It removed two of three
    /// lifts saved over no Watch workout; a bar fitted on October alone kept every November lift.
    public static let minLiftHRSwingBPM = 6.5

    /// HR in 10 s bins over `[start, end)`, gaps filled linearly, minus a centred 6 min moving mean; the
    /// population SD of what is left. Nil under 600 HR samples (10 min at 1 Hz).
    public static func hrSwingSD(hr: [HRSample], start: Int, end: Int) -> Double? {
        let w = hr.filter { $0.ts >= start && $0.ts < end }
        guard w.count >= 600, let last = w.map(\.ts).max() else { return nil }
        let n = (last - start) / 10 + 1
        var sum = [Double](repeating: 0, count: n), cnt = [Int](repeating: 0, count: n)
        for s in w { let b = (s.ts - start) / 10; sum[b] += Double(s.bpm); cnt[b] += 1 }
        let known = (0..<n).filter { cnt[$0] > 0 }
        var x = [Double](repeating: 0, count: n)
        for i in known { x[i] = sum[i] / Double(cnt[i]) }
        // Linear fill between known bins, flat beyond the ends (numpy `interp`).
        var j = 0
        for i in 0..<n where cnt[i] == 0 {
            while j + 1 < known.count, known[j + 1] < i { j += 1 }
            let lo = known[j]
            if lo > i { x[i] = x[lo]; continue }
            guard j + 1 < known.count else { x[i] = x[lo]; continue }
            let hi = known[j + 1]
            x[i] = x[lo] + (x[hi] - x[lo]) * Double(i - lo) / Double(hi - lo)
        }
        let k = 36
        guard n > k + 1 else { return nil }
        // Residual at i against the mean of x[i-18 ... i+17], for every i whose window is whole.
        var prefix = [0.0]
        for v in x { prefix.append(prefix[prefix.count - 1] + v) }
        var r: [Double] = []
        for i in (k / 2)..<(n - k / 2) { r.append(x[i] - (prefix[i + k / 2] - prefix[i - k / 2]) / Double(k)) }
        guard !r.isEmpty else { return nil }
        let mean = r.reduce(0, +) / Double(r.count)
        return (r.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(r.count)).squareRoot()
    }

    // MARK: - Lifts under the activity floor

    /// HR floor of a lift-like minute, as a fraction of HR reserve over resting. The detector's own floor
    /// is 0.40; two of 13 Watch lifts (11-01, 11-21) never cleared it.
    public static let lowLiftHRRFraction = 0.30
    /// Shortest block, share of lift-like minutes in it, and mean gravity-delta variance it must hold.
    public static let lowLiftMinMin = 25
    public static let lowLiftMinShare = 0.6
    public static let lowLiftMinMotionVariance = 0.08
    /// Non-lift minutes a block may cross, when no 5 min walk sits in them.
    public static let lowLiftJoinGapMin = 5

    /// Lift-shaped blocks whose HR may sit under the detector's floor, as `[start, end]` seconds. A minute
    /// is lift-like when it holds 20+ HR readings, is not walking (`gaitMinuteTicks`), moves (any gait tick,
    /// or 10%+ of its gravity deltas over `motionThreshold`) and averages at least
    /// rest + `lowLiftHRRFraction` × reserve. Without the swing bar this added 9 false blocks a month, so a
    /// block must clear `minLiftHRSwingBPM` too. Rests on two lifts: behind a default-off toggle.
    public static func lowHRLiftSpans(hr: [HRSample], gravity: [GravitySample], steps: [StepSample],
                                      restingHR: Double, maxHR: Double) -> [(Int, Int)] {
        guard maxHR > restingHR, let t0 = hr.map(\.ts).min(), let t1 = hr.map(\.ts).max() else { return [] }
        let m0 = t0 / 60, n = t1 / 60 - m0 + 1
        func idx(_ ts: Int) -> Int? { let i = ts / 60 - m0; return i >= 0 && i < n ? i : nil }
        var hrSum = [Double](repeating: 0, count: n), hrN = [Int](repeating: 0, count: n)
        for s in hr { if let i = idx(s.ts) { hrSum[i] += Double(s.bpm); hrN[i] += 1 } }
        var gait = [Int](repeating: 0, count: n)
        for s in steps where WorkoutDetector.isGait(s.activityClass) { if let i = idx(s.ts) { gait[i] += 1 } }
        var dN = [Int](repeating: 0, count: n), dOver = [Int](repeating: 0, count: n)
        var dSum = [Double](repeating: 0, count: n), dSq = [Double](repeating: 0, count: n)
        var prev: GravitySample? = nil
        for g in gravity.sorted(by: { $0.ts < $1.ts }) {
            var d = 0.0
            if let p = prev, g.ts - p.ts <= 5 {
                d = ((g.x - p.x) * (g.x - p.x) + (g.y - p.y) * (g.y - p.y) + (g.z - p.z) * (g.z - p.z)).squareRoot()
            }
            prev = g
            guard let i = idx(g.ts) else { continue }
            dN[i] += 1; dSum[i] += d; dSq[i] += d * d
            if d > WorkoutDetector.motionThreshold { dOver[i] += 1 }
        }
        let walking = gait.map { $0 >= WorkoutDetector.gaitMinuteTicks }
        var walkB = walking
        if n > 2 { for m in 1..<(n - 1) where walking[m - 1] && walking[m + 1] { walkB[m] = true } }
        let floor = restingHR + lowLiftHRRFraction * (maxHR - restingHR)
        let liftLike: [Bool] = (0..<n).map { m in
            let moving = gait[m] > 0 || (dN[m] > 0 && Double(dOver[m]) / Double(dN[m]) > 0.1)
            return hrN[m] >= 20 && !walking[m] && moving && hrSum[m] / Double(hrN[m]) >= floor
        }
        let lift = (0..<n).filter { liftLike[$0] }
        guard var a = lift.first else { return [] }
        var b = a
        var out: [(Int, Int)] = []
        func close() {
            let len = b - a + 1
            guard len >= lowLiftMinMin else { return }
            let share = Double((a...b).filter { liftLike[$0] }.count) / Double(len)
            let vars = (a...b).filter { dN[$0] > 0 }.map { m -> Double in
                let mean = dSum[m] / Double(dN[m]); return dSq[m] / Double(dN[m]) - mean * mean
            }
            guard share >= lowLiftMinShare, !vars.isEmpty,
                  vars.reduce(0, +) / Double(vars.count) >= lowLiftMinMotionVariance else { return }
            let s = (m0 + a) * 60, e = (m0 + b) * 60 + 59
            guard (hrSwingSD(hr: hr, start: s, end: e) ?? 0) >= minLiftHRSwingBPM else { return }
            out.append((s, e))
        }
        for k in lift.dropFirst() {
            var run = 0, walked = false
            for m in (b + 1)..<k { run = walkB[m] ? run + 1 : 0; walked = walked || run >= 5 }
            if k - b - 1 <= lowLiftJoinGapMin && !walked { b = k; continue }
            close()
            a = k; b = k
        }
        close()
        return out
    }

    // MARK: - Walks

    /// Steps a minute that make it a walking minute (strap locomotion ticks over `ticksPerStep`).
    public static let walkMinuteSteps = 80.0
    /// Non-walking minutes a walk may cross (a crossing, a door).
    public static let walkJoinGapMin = 2
    /// Shortest walk logged. 12 min skips the 6–11 min walks to and from the gym, and a strap often
    /// reads a walk a minute shorter than Health does, so 15 missed 7 of 62 walks of 15+ min.
    public static let walkMinMin = 12
    /// Share of a walk's minutes that are walking minutes.
    public static let walkMinShare = 0.6
    /// Share of a walk's minutes holding an HR reading, and how far its mean HR must sit over resting.
    public static let walkMinHRCoverage = 0.5
    public static let walkMinHRLiftBPM = 20.0

    /// Walks as `[start, end]` seconds: runs of walking minutes joined across `walkJoinGapMin`, at least
    /// `walkMinMin` long, never through a minute of `excluding` (a saved lift: the walk to the gym and the
    /// walk home stay walks of their own). On 31 days this logged 87 walks, 86 of them real, and found 70
    /// of the 72 Apple Health walks of 12+ min.
    public static func walkSpans(steps: [StepSample], excluding: [(Int, Int)], ticksPerStep: Double) -> [(Int, Int)] {
        let sorted = steps.sorted { $0.ts < $1.ts }
        guard sorted.count >= 2 else { return [] }
        let classed = StepsCounter.hasActivityClasses(sorted)
        var ticks: [Int: Int] = [:]
        for i in 1..<sorted.count {
            let delta = (sorted[i].counter - sorted[i - 1].counter) & 0xFFFF
            guard StepsCounter.shouldCountDelta(activityClass: sorted[i].activityClass, hasActivityClasses: classed),
                  StepsCounter.isPlausibleDelta(previousTs: sorted[i - 1].ts, currentTs: sorted[i].ts, delta: delta)
            else { continue }
            ticks[sorted[i].ts / 60, default: 0] += delta
        }
        let perStep = max(ticksPerStep, 0.5)
        func walkingMinute(_ m: Int) -> Bool {
            !excluding.contains { m * 60 + 59 >= $0.0 && m * 60 <= $0.1 }
                && Double(ticks[m] ?? 0) / perStep >= walkMinuteSteps
        }
        var bouts: [(Int, Int)] = []
        for m in ticks.keys.sorted() where walkingMinute(m) {
            if let last = bouts.last, m - last.1 - 1 <= walkJoinGapMin,
               !((last.1 + 1)..<m).contains(where: { m2 in excluding.contains { m2 * 60 + 59 >= $0.0 && m2 * 60 <= $0.1 } }) {
                bouts[bouts.count - 1].1 = m
            } else {
                bouts.append((m, m))
            }
        }
        return bouts.compactMap { b in
            let len = b.1 - b.0 + 1
            guard len >= walkMinMin,
                  Double((b.0...b.1).filter(walkingMinute).count) / Double(len) >= walkMinShare else { return nil }
            return (b.0 * 60, b.1 * 60 + 59)
        }
    }

    // MARK: - The day's log

    /// One session of the day, with what the classifier made of it and the class it is saved under
    /// (nil: it stays a suggestion).
    public struct Entry {
        public var session: ExerciseSession
        public let features: WorkoutClassFeatures?
        public let prediction: WorkoutClassPrediction?
        public let token: String?
    }

    /// The day's log over one day's detector output, given the same streams `detect` was given. The app
    /// and WorkoutBench both call this, so a replay is the app's. Sorted by start; a suggestion that
    /// overlaps a saved entry is dropped (the saved one is the same activity).
    public static func plan(detected: [ExerciseSession], hr: [HRSample], gravity: [GravitySample],
                            steps: [StepSample], restingHR: Double?, maker: WorkoutDetector.SessionMaker,
                            ticksPerStep: Double, lowHRLifts: Bool) -> [Entry] {
        let gaitTs = Set(steps.lazy.filter { WorkoutDetector.isGait($0.activityClass) }.map(\.ts)).sorted()
        func entry(_ s: ExerciseSession) -> Entry {
            let (f, p) = WorkoutAutoSave.classify(s, hr: hr, gravity: gravity, steps: steps, restingHR: restingHR)
            var token: String? = nil
            if case .save(let t) = WorkoutAutoSave.verdict(session: s, features: f, prediction: p) { token = t }
            if token == CoarseWorkoutClass.strength.rawValue,
               (hrSwingSD(hr: hr, start: s.start, end: s.end + 1) ?? 0) < minLiftHRSwingBPM { token = nil }
            return Entry(session: s, features: f, prediction: p, token: token)
        }
        func isWalk(_ s: ExerciseSession) -> Bool {
            let minutes = WorkoutDetector.walkingMinutes(start: s.start, end: s.end, gaitTs: gaitTs)
            return Double(minutes.filter { $0 }.count) / Double(max(1, minutes.count)) >= WorkoutDetector.stitchWalkMinuteFrac
                && (2...5).reduce(0.0) { $0 + (s.zoneTimePct[$1] ?? 0) } / 100.0 < WorkoutDetector.minIntensityZ2Plus
        }
        let visits = gymVisits(detected, gaitTs: gaitTs, isWalk: isWalk, isLift: { s in
            let (f, p) = WorkoutAutoSave.classify(s, hr: hr, gravity: gravity, steps: steps, restingHR: restingHR)
            return WorkoutAutoSave.verdict(session: s, features: f, prediction: p) == .save(token: CoarseWorkoutClass.strength.rawValue)
        }, make: { maker.session(from: $0, to: $1, activityTier: $2) })
        var entries = visits.map(entry)

        if lowHRLifts, let maxHR = maker.effMaxHR {
            let strength = CoarseWorkoutClass.strength.rawValue
            var spans = entries.filter { $0.token == strength }.map { ($0.session.start, $0.session.end) }
            spans += lowHRLiftSpans(hr: hr, gravity: gravity, steps: steps, restingHR: maker.restHR, maxHR: maxHR)
            var merged: [(Int, Int)] = []
            for s in spans.sorted(by: { $0.0 < $1.0 }) {
                if let l = merged.last, s.0 - l.1 <= visitMergeGapS { merged[merged.count - 1].1 = max(l.1, s.1) }
                else { merged.append(s) }
            }
            for (s, e) in merged where !entries.contains(where: { $0.token == strength && $0.session.start == s && $0.session.end == e }) {
                guard let session = maker.session(from: s, to: e, activityTier: true) else { continue }
                let (f, p) = WorkoutAutoSave.classify(session, hr: hr, gravity: gravity, steps: steps, restingHR: restingHR)
                entries.removeAll { $0.token == strength && $0.session.start < e && s < $0.session.end }
                entries.append(Entry(session: session, features: f, prediction: p, token: strength))
            }
        }

        let saved = entries.filter { $0.token != nil }.map { ($0.session.start, $0.session.end) }
        for (s, e) in walkSpans(steps: steps, excluding: saved, ticksPerStep: ticksPerStep) {
            guard let session = maker.session(from: s, to: e, activityTier: true) else { continue }
            let seen = Set(hr.lazy.filter { $0.ts >= s && $0.ts <= e }.map { $0.ts / 60 }).count
            guard Double(seen) >= walkMinHRCoverage * Double((e - s + 1) / 60),
                  session.avgHR - maker.restHR >= walkMinHRLiftBPM else { continue }
            let (f, p) = WorkoutAutoSave.classify(session, hr: hr, gravity: gravity, steps: steps, restingHR: restingHR)
            entries.append(Entry(session: session, features: f, prediction: p, token: CoarseWorkoutClass.walk.rawValue))
        }

        let kept = entries.filter { $0.token != nil }
        return (kept + entries.filter { e in
            e.token == nil && !kept.contains { $0.session.start < e.session.end && e.session.start < $0.session.end }
        }).sorted { $0.session.start < $1.session.start }
    }
}
