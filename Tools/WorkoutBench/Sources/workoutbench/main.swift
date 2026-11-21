import Foundation
import StrandAnalytics
import WhoopProtocol

// workoutbench — replay workout detection over real recorded days and score it against the workouts the
// database carries as labels.
//
// USAGE:  workoutbench --db /path/to/whoop.sqlite [--stream-device <id>] [--age <y>] [--hrmax <bpm>]
//                       [--rest <bpm>] [--tz <identifier>] [--include-card-saved] [--list-unlabelled]
//                       [--funnel] [--csv out.csv] [--labels labels.csv]
//
// The database is never written to and never lives in this repository. Pass a COPY; never point this at
// a device's live database.
//
// WHAT IT REPLAYS. One `WorkoutDetector.detect` call per local calendar day over that day's HR, gravity
// and step streams, then `WorkoutTypeClassifier` per session: the shape of `AnalyticsEngine.analyzeDay`.
// It does not replay the suggestion card's rolling 48-hour scan, so a session across midnight is cut
// here exactly as daily scoring cuts it.

struct Args {
    var db = ""
    var streamDevice: String?
    var age: Double?
    var hrmax: Double?
    var rest: Double?
    var tz = TimeZone.current
    var includeCardSaved = false
    var listUnlabelled = false
    var funnel = false
    var csv: String?
    var labels: String?
    var from: String?
    var weight: Double?
    var height: Double?
    var lowHRLifts = false
    var ticksPerStep = 1.0
}
var a = Args()
var it = CommandLine.arguments.dropFirst().makeIterator()
while let k = it.next() {
    switch k {
    case "--db": a.db = it.next() ?? ""
    case "--stream-device": a.streamDevice = it.next()
    case "--age": a.age = Double(it.next() ?? "")
    case "--hrmax": a.hrmax = Double(it.next() ?? "")
    case "--rest": a.rest = Double(it.next() ?? "")
    case "--tz": a.tz = TimeZone(identifier: it.next() ?? "") ?? a.tz
    case "--include-card-saved": a.includeCardSaved = true
    case "--list-unlabelled": a.listUnlabelled = true
    case "--funnel": a.funnel = true
    case "--csv": a.csv = it.next()
    case "--labels": a.labels = it.next()
    case "--from": a.from = it.next()
    case "--weight": a.weight = Double(it.next() ?? "")
    case "--height": a.height = Double(it.next() ?? "")
    case "--low-hr-lifts": a.lowHRLifts = true
    case "--ticks-per-step": a.ticksPerStep = Double(it.next() ?? "") ?? 1
    default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
    }
}
guard !a.db.isEmpty else {
    print("""
    usage: workoutbench --db <sqlite> [--stream-device <id>] [--age <years>] [--hrmax <bpm>] [--rest <bpm>]
                        [--tz <identifier>] [--include-card-saved] [--list-unlabelled] [--funnel]
                        [--csv <path>] [--labels <csv>] [--from <yyyy-MM-dd>] [--weight <kg>] [--height <cm>]

      --stream-device       deviceId the raw streams are stored under (default: the one with most HR rows)
      --age / --hrmax       HRmax the days are scored against: --hrmax, else Tanaka from --age, else the
                            detector's own estimate. Pass what the app uses or the replay is not the app's.
      --rest                resting HR for every day (default: each day's stored dailyMetric.restingHr,
                            else the detector's own derivation)
      --from                first local day to replay. Use it when HR reaches further back than gravity
                            and steps (raw retention): a day without motion data can detect nothing and
                            only dilutes the per-day figures.
      --labels              extra labels the database does not hold (a watch workout never imported), one
                            per line: start,end,sport. start and end are unix seconds or
                            "yyyy-MM-dd HH:mm" in --tz. Lines starting with # are skipped, and so is a
                            header line whose first field is "start". Optional columns 4-6 are the
                            reference device's avg HR, max HR and active kcal for that session; when
                            present they are printed beside the detected session's own figures.
      --weight / --height   profile used for session calories (default 70 kg / 170 cm). Match the app.
      --low-hr-lifts        also log lifts under the activity floor (the app's default-off toggle)
      --ticks-per-step      strap locomotion ticks per step for walk logging (default 1). Match the app.
      --include-card-saved  also score rows saved from the suggestion card (manual rows that are a generic
                            "Workout" or still carry the classifier's class). They are the detector's own
                            output and inflate recall.
    """)
    exit(2)
}

let db = try ReadOnlyDB(path: a.db)
guard let device = try a.streamDevice ?? db.busiestStreamDevice(),
      let (firstHrTs, lastTs) = try db.hrRange(device: device) else {
    print("no HR samples in this database"); exit(1)
}
var firstTs = firstHrTs

var cal = Calendar(identifier: .gregorian)
cal.timeZone = a.tz
let dayKey = DateFormatter()
dayKey.calendar = cal; dayKey.timeZone = a.tz; dayKey.locale = Locale(identifier: "en_US_POSIX")
dayKey.dateFormat = "yyyy-MM-dd"
let clock = DateFormatter()
clock.calendar = cal; clock.timeZone = a.tz; clock.locale = Locale(identifier: "en_US_POSIX")
clock.dateFormat = "HH:mm"
func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
func hm(_ ts: Int) -> String { clock.string(from: date(ts)) }
func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

if let from = a.from {
    guard let d = dayKey.date(from: from) else {
        FileHandle.standardError.write(Data("--from expects yyyy-MM-dd\n".utf8)); exit(2)
    }
    firstTs = max(firstTs, Int(d.timeIntervalSince1970))
}
let restByDay = try db.restingHRByDay()
let maxHR = StrainScorer.effortMaxHR(override: a.hrmax, age: a.age ?? 0)
let profile = UserProfile(weightKg: a.weight ?? 70, heightCm: a.height ?? 170, age: a.age ?? 30)

// MARK: - Replay

struct Session {
    let day: String
    let s: ExerciseSession
    let cls: String?
    let conf: Double?
    var scores: [CoarseWorkoutClass: Double] = [:]
    var rest: Double? = nil
    var features: WorkoutClassFeatures? = nil
    var verdict: WorkoutAutoSave.Verdict = .suggest
    var saved: Bool { if case .save = verdict { return true } else { return false } }
    var detected: DetectedSpan { DetectedSpan(span: Span(start: s.start, end: s.end), suggestedClass: cls) }
}
var sessions: [Session] = []
var funnelTotals: [(key: String, value: Int)] = []
var days = 0
var dayStart = cal.startOfDay(for: date(firstTs))
while Int(dayStart.timeIntervalSince1970) <= lastTs {
    let next = cal.date(byAdding: .day, value: 1, to: dayStart)!
    let from = Int(dayStart.timeIntervalSince1970), to = Int(next.timeIntervalSince1970)
    let key = dayKey.string(from: dayStart)
    dayStart = next
    let st = try db.streams(device: device, from: from, to: to)
    guard !st.hr.isEmpty else { continue }
    days += 1
    let rest = a.rest ?? restByDay[key].map(Double.init)
    var funnel: WorkoutDetector.DetectionFunnel?
    let found = WorkoutDetector.detect(hr: st.hr, gravity: st.grav, restingHR: rest, maxHR: maxHR,
                                       age: a.age, profile: profile, funnel: { funnel = $0 },
                                       steps: st.steps)
    if let f = funnel {
        let line = WorkoutDetector.detectionFunnelLine(day: key, funnel: f)
        if a.funnel { print(line) }
        // Totals are summed from the line's own `key=value` fields rather than from the struct, so a
        // field added to the funnel shows up here without this tool being edited.
        for token in line.split(separator: " ") {
            let kv = token.split(separator: "=")
            guard kv.count == 2, let v = Int(kv[1]), !["restHR", "floor", "longestRunS", "meanRunS"].contains(String(kv[0]))
            else { continue }
            if let i = funnelTotals.firstIndex(where: { $0.key == String(kv[0]) }) { funnelTotals[i].value += v }
            else { funnelTotals.append((String(kv[0]), v)) }
        }
    }
    // The app's own day log (`WorkoutAutoLog.plan`): visits, the swing bar, walks, and the low-HR lift
    // tier with --low-hr-lifts, so the replay is the app's.
    guard let maker = WorkoutDetector.SessionMaker(hr: st.hr, restingHR: rest, maxHR: maxHR, age: a.age,
                                                   profile: profile) else { continue }
    let log = WorkoutAutoLog.plan(detected: found, hr: st.hr, gravity: st.grav, steps: st.steps, restingHR: rest,
                                  maker: maker, ticksPerStep: a.ticksPerStep, lowHRLifts: a.lowHRLifts)
    for e in log {
        var cls: String?, conf: Double?, scores: [CoarseWorkoutClass: Double] = [:]
        if let p = e.prediction {
            cls = p.predictedClass == .other ? nil : p.predictedClass.rawValue
            conf = p.confidence
            scores = p.scores
        }
        // A saved walk is a walk, whatever the classifier made of it.
        if e.token == CoarseWorkoutClass.walk.rawValue { cls = e.token }
        sessions.append(Session(day: key, s: e.session, cls: cls, conf: conf, scores: scores,
                                rest: rest ?? funnel?.restingHR, features: e.features,
                                verdict: e.token.map { .save(token: $0) } ?? .suggest))
    }
}

// MARK: - Labels

// Ordered by trust before the twin collapse: another device's recording first, then imports, then rows
// typed in by hand.
func trust(_ l: LabelRow) -> Int {
    if l.deviceId == "apple-health" || l.source == "apple-health" { return 0 }
    return l.source == "manual" ? 2 : 1
}
func isCardSaved(_ l: LabelRow) -> Bool { l.cardSaved }
var allLabels = try db.labels(from: firstTs, to: lastTs)
if let path = a.labels {
    let stamp = DateFormatter()
    stamp.calendar = cal; stamp.timeZone = a.tz; stamp.locale = Locale(identifier: "en_US_POSIX")
    stamp.dateFormat = "yyyy-MM-dd HH:mm"
    func ts(_ f: String) -> Int? { Int(f) ?? stamp.date(from: f).map { Int($0.timeIntervalSince1970) } }
    for (n, raw) in try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline).enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("start,") { continue }
        let f = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count >= 3, let s = ts(f[0]), let e = ts(f[1]), e > s else {
            FileHandle.standardError.write(Data("\(path):\(n + 1): expected start,end,sport\n".utf8)); exit(2)
        }
        // Filed under the watch's trust level: a label file exists to carry another device's recording.
        var row = LabelRow(deviceId: "label-file", startTs: s, endTs: e, sport: f[2], source: "apple-health")
        if f.count >= 6, let avg = Double(f[3]), let mx = Double(f[4]), let kcal = Double(f[5]) {
            row.reference = ReferenceStats(avgHR: avg, maxHR: mx, activeKcal: kcal)
        }
        allLabels.append(row)
    }
}
let cardSaved = allLabels.filter(isCardSaved)
let candidates = Scoring.dedup(
    allLabels.filter { a.includeCardSaved || !isCardSaved($0) }
        .enumerated().sorted { (trust($0.element), $0.offset) < (trust($1.element), $1.offset) }.map(\.element),
    span: \.span).sorted { $0.startTs < $1.startTs }

// A label the strap did not record cannot be found by any detector, so it is listed and left out of
// recall rather than counted as a miss.
var scorable: [(LabelRow, Double)] = []
var uncovered: [(LabelRow, Double)] = []
for l in candidates {
    let st = try db.streams(device: device, from: l.startTs, to: l.endTs)
    let cover = WorkoutDetector.hrCoveragePct(sampleTs: st.hr.map(\.ts), start: l.startTs, end: l.endTs) ?? 0
    if cover >= 50 { scorable.append((l, cover)) } else { uncovered.append((l, cover)) }
}

// MARK: - Report

print("WORKOUTBENCH  db=\((a.db as NSString).lastPathComponent)  streams=\(device)  tz=\(a.tz.identifier)")
print("  days with HR: \(days)  (\(dayKey.string(from: date(firstTs))) to \(dayKey.string(from: date(lastTs))))")
print("  HRmax: \(maxHR.map { String(format: "%.0f", $0) } ?? "detector estimate")"
      + "  resting HR: \(a.rest.map { String(format: "%.0f (fixed)", $0) } ?? "stored per day, \(restByDay.count) days known")")
print("  labels in range: \(allLabels.count)  scorable: \(scorable.count)  no strap HR: \(uncovered.count)"
      + "  card-saved \(a.includeCardSaved ? "included" : "excluded"): \(cardSaved.count)")

print("\nA. LABELLED WORKOUTS")
let detected = sessions.map(\.detected)
struct Scored { let label: LabelRow; let family: SportFamily; let score: LabelScore }
func signedMin(_ s: Int) -> String { (s >= 0 ? "+" : "-") + "\(abs(s) / 60)m" }
var mainErrors: [(Int, Int)] = []
var scored: [Scored] = []
if scorable.isEmpty { print("  none. Recall cannot be measured on this database.") }
for (l, cover) in scorable {
    let sc = Scoring.score(label: l.span, detected: detected)
    let fam = SportFamily.of(sport: l.sport)
    scored.append(Scored(label: l, family: fam, score: sc))
    let pieces = sessions.filter { $0.detected.span.overlap(l.span) > 0 }
        .map { "\(hm($0.s.start))-\(hm($0.s.end)) \($0.cls ?? "other")\($0.s.isActivityTier ? "" : "*")\($0.saved ? " SAVE" : "")" }
        .joined(separator: ", ")
    print("  \(dayKey.string(from: date(l.startTs))) \(hm(l.startTs))-\(hm(l.endTs))  \(pad(l.sport, 22)) "
          + "\(pad(fam.rawValue, 8)) hr=\(Int(cover))%  covered=\(Int((sc.coveredFrac * 100).rounded()))% "
          + "pieces=\(sc.pieces) spill=\(sc.spillS / 60)m  -> \(pieces.isEmpty ? "NOT DETECTED" : pieces)")
    // The session holding the most of the label is the one a wearer would see as "the workout": its own
    // bounds, HR and energy, beside the reference device's.
    if let main = sessions.filter({ $0.detected.span.overlap(l.span) > 0 })
        .max(by: { $0.detected.span.overlap(l.span) < $1.detected.span.overlap(l.span) }) {
        var line = "      main \(hm(main.s.start))-\(hm(main.s.end)) \(main.cls ?? "other") "
            + "\(main.conf.map { String(format: "%.2f", $0) } ?? "-")  start \(signedMin(main.s.start - l.startTs)) "
            + "end \(signedMin(main.s.end - l.endTs))  avg=\(Int(main.s.avgHR.rounded())) max=\(main.s.peakHR) "
            + "kcal=\(main.s.caloriesKcal.map { String(Int($0.rounded())) } ?? "-")"
        if let r = l.reference {
            line += "  | ref avg=\(Int(r.avgHR.rounded())) max=\(Int(r.maxHR.rounded())) activeKcal=\(Int(r.activeKcal.rounded()))"
        }
        let inLabel = (try? db.streams(device: device, from: l.startTs, to: l.endTs + 1).hr.map(\.bpm)) ?? []
        if !inLabel.isEmpty {
            line += "  | strap in label avg=\(inLabel.reduce(0, +) / inLabel.count) max=\(inLabel.max()!)"
        }
        print(line)
        mainErrors.append((main.s.start - l.startTs, main.s.end - l.endTs))
    }
}
if !scored.isEmpty {
    print("  (* = cleared the zone-2 workout bar; unmarked = activity tier; SAVE = auto-saved by WorkoutAutoSave)")
    print("\n  family     n  found  meanCover  meanPieces  classMatch")
    for fam in SportFamily.allCases {
        let rows = scored.filter { $0.family == fam }
        guard !rows.isEmpty else { continue }
        let found = rows.filter { $0.score.coveredFrac >= Scoring.foundCoverage }
        let cover = rows.reduce(0.0) { $0 + $1.score.coveredFrac } / Double(rows.count)
        let pieces = found.isEmpty ? 0 : Double(found.reduce(0) { $0 + $1.score.pieces }) / Double(found.count)
        // `other` has no class to match: the classifier is right there when it declines to name one.
        let match = found.filter { fam == .other ? $0.score.classByOverlap == nil : $0.score.classByOverlap == fam.rawValue }
        print("  \(pad(fam.rawValue, 9)) \(pad(String(rows.count), 3))\(pad("\(found.count)", 7))"
              + "\(pad(String(format: "%.0f%%", cover * 100), 11))\(pad(String(format: "%.1f", pieces), 12))"
              + "\(match.count)/\(found.count)")
    }
}
if !mainErrors.isEmpty {
    let n = Double(mainErrors.count)
    let ms = mainErrors.reduce(0.0) { $0 + Double(abs($1.0)) } / n / 60
    let me = mainErrors.reduce(0.0) { $0 + Double(abs($1.1)) } / n / 60
    let within = mainErrors.filter { abs($0.0) <= 300 && abs($0.1) <= 300 }.count
    print(String(format: "\n  main session: mean |start err| %.1f min, mean |end err| %.1f min, both within 5 min: %d/%d",
                 ms, me, within, mainErrors.count))
}
do {
    // Auto-save: one saved session per label is the goal. A label with two saved pieces is a duplicate
    // the wearer has to clean up; a saved session over no label is a workout they did not log.
    let savedPerLabel = scored.map { sc in sessions.filter { $0.saved && $0.detected.span.overlap(sc.label.span) > 0 }.count }
    let savedFree = sessions.filter { s in s.saved && !candidates.contains { $0.span.overlap(s.detected.span) > 0 } }
    print("\n  auto-save: \(sessions.filter(\.saved).count) sessions saved; labels with exactly one saved session "
          + "\(savedPerLabel.filter { $0 == 1 }.count)/\(scored.count), with two or more "
          + "\(savedPerLabel.filter { $0 > 1 }.count); saved over no label \(savedFree.count)")
    for s in savedFree {
        print("    \(s.day) \(hm(s.s.start))-\(hm(s.s.end))  \((s.s.end - s.s.start) / 60)m avg=\(Int(s.s.avgHR.rounded())) "
              + "peak=\(s.s.peakHR) \(s.cls ?? "other")")
    }
}
if !uncovered.isEmpty {
    print("\n  Not scorable (strap HR covers under half the label):")
    for (l, cover) in uncovered {
        print("  \(dayKey.string(from: date(l.startTs))) \(hm(l.startTs))-\(hm(l.endTs))  \(pad(l.sport, 22)) hr=\(Int(cover))%")
    }
}

print("\nB. DETECTION VOLUME")
let unl = Scoring.unlabelled(detected, labels: candidates.map(\.span))
let totalMin = sessions.reduce(0) { $0 + ($1.s.end - $1.s.start) } / 60
print("  sessions: \(sessions.count)  (\(String(format: "%.1f", Double(sessions.count) / Double(max(1, days)))) a day, \(totalMin) min)"
      + "  activity tier: \(sessions.filter { $0.s.isActivityTier }.count)")
print("  overlapping no label: \(unl.count), \(unl.reduce(0) { $0 + $1.span.length } / 60) min."
      + " Not false alarms by themselves: an unlogged walk is a real bout.")
var byClass: [String: Int] = [:]
for s in sessions { byClass[s.cls ?? "other", default: 0] += 1 }
print("  by suggested class: " + byClass.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
if a.listUnlabelled {
    for s in sessions where !candidates.contains(where: { $0.span.overlap(s.detected.span) > 0 }) {
        print("  \(s.day) \(hm(s.s.start))-\(hm(s.s.end))  \(pad("\((s.s.end - s.s.start) / 60)m", 5)) "
              + "avg=\(Int(s.s.avgHR.rounded())) peak=\(s.s.peakHR) \(s.s.isActivityTier ? "activity" : "workout ")\(s.saved ? " SAVE" : "") "
              + "\(s.cls ?? "other") \(s.conf.map { String(format: "%.2f", $0) } ?? "")")
    }
}

print("\nC. FUNNEL TOTALS over \(days) days")
print("  " + funnelTotals.map { "\($0.key)=\($0.value)" }.joined(separator: " "))

if let path = a.csv {
    var out = "day,start,end,durationMin,avgHR,peakHR,tier,suggestedClass,confidence,labelSport,"
        + "hrCoveragePct,avgHRRPct,restHR,strengthScore,walkScore,runScore,cycleScore,labelOverlapMin,"
        + "hrCV,motionVariance,stillFraction,walkFraction,gaitStreakSec,tickCoverage,kcalPerMin,autoSave\n"
    for s in sessions {
        let label = candidates.first { $0.span.overlap(s.detected.span) > 0 }?.sport ?? ""
        out += "\(s.day),\(s.s.start),\(s.s.end),\((s.s.end - s.s.start) / 60),\(Int(s.s.avgHR.rounded())),"
            + "\(s.s.peakHR),\(s.s.isActivityTier ? "activity" : "workout"),\(s.cls ?? "other"),"
            + "\(s.conf.map { String(format: "%.3f", $0) } ?? ""),\(label),"
            + "\(s.s.hrCoveragePct.map { String(format: "%.1f", $0) } ?? ""),\(s.s.avgHRRPct.map { String(format: "%.1f", $0) } ?? ""),"
            + "\(s.rest.map { String(format: "%.0f", $0) } ?? ""),"
            + [CoarseWorkoutClass.strength, .walk, .run, .cycle].map { String(format: "%.3f", s.scores[$0] ?? 0) }.joined(separator: ",")
            + ",\(candidates.map { $0.span.overlap(s.detected.span) }.max().map { $0 / 60 } ?? 0),"
            + (s.features.map { f in
                [f.hrCV, f.motionVariance, f.stillFraction, f.walkFraction, f.gaitStreakSec, f.tickCoverage, f.kcalPerMin ?? 0]
                    .map { String(format: "%.3f", $0) }.joined(separator: ",") } ?? ",,,,,,")
            + ",\(s.saved ? 1 : 0)\n"
    }
    try out.write(toFile: path, atomically: true, encoding: .utf8)
    print("\nwrote \(sessions.count) sessions to \(path)")
}
