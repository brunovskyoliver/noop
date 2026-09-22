import Foundation
import StrandAnalytics
import UserNotifications

// MARK: - Detected-workout notification
//
// A single opt-in, default-OFF FYI: after an analysis pass persists `sport="detected"` bouts
// (IntelligenceEngine re-derives them every run), post one local notification for the newest
// detected bout whose end is at least `WorkoutDetectedPolicy.notifySettleSec` old. The row is
// already saved — the notification is informational, with Edit / "Not a workout" actions so the
// user can relabel or durably dismiss it. WHOOP auto-saves detected "Activity" rows the same way;
// the wording below is NOOP's own.
//
// Battery contract: this adds NO work of its own — no timer, no BLE, no sensor reads. The check
// rides the existing `analyzeRecent` cadence (offload-driven and the 15-min tick): when the
// preference is OFF it costs one UserDefaults read per call; when ON it adds one bounded
// workouts read over a 36-hour window.
//
// Dedup is by SPAN OVERLAP, not exact tokens: the engine's re-detect can drift a bout's startTs
// by minutes between passes, so the persisted "startTs:endTs" set is consulted the same way the
// dismissed-detected list is (WorkoutSource.isDismissed). Once a span is settled, every overlapping
// re-derive stays silent — and every eligible token from the pass is marked, so the same pass can
// never re-notify an older sibling later.

/// Pure policy + copy for the detected-workout notification — no UserNotifications types, so the
/// decision logic is pinned by unit tests independently of the notification plumbing. Kotlin twin:
/// `com.noop.notif.WorkoutDetectedPolicy` (same constants, same semantics).
enum WorkoutDetectedPolicy {

    /// One detected-bout candidate, built from a persisted `sport="detected"` row.
    struct Candidate: Equatable, Sendable {
        var startTs: Int
        var endTs: Int
        var avgHr: Int?
        var maxHr: Int?
        /// The classifier's advisory token ("walk"/"run"/"strength"/"cycle"/"ski"), copied from the
        /// row's `suggestedClass`. nil when the classifier had nothing to say — the copy then makes
        /// no activity claim at all.
        var suggestedClass: String? = nil
    }

    /// The pass decision: the single bout to notify about (newest eligible), plus EVERY eligible
    /// span token to mark settled — not just the notified one, so a pass with several fresh bouts
    /// can never trickle out extra notifications on later passes.
    struct Decision: Equatable, Sendable {
        var notify: Candidate?
        var settledTokens: [String]
    }

    /// A bout must have been over this long before we talk about it: the detector extends a live
    /// bout across a sync boundary, so notifying on first sight could fire mid-workout. 600 s also
    /// lands the notification ~10-25 min post-exercise on the normal offload cadence.
    static let notifySettleSec = 600
    /// Candidates are only considered inside this lookback — an ancient re-detect never notifies.
    static let candidateWindowSec = 36 * 3600
    /// Persisted-token hygiene: spans older than this are pruned and the set is capped, so the
    /// UserDefaults list can't grow without bound across process restarts.
    static let maxTokenAgeSec = 30 * 86_400
    static let maxTokens = 200

    /// The "startTs:endTs" token persisted for a settled span — same shape as the
    /// dismissed-detected tokens (`WorkoutSource.dismissedToken`), so the two span lists can share
    /// `WorkoutSource.parseDismissedSpans`.
    static func token(startTs: Int, endTs: Int) -> String { "\(startTs):\(endTs)" }

    /// Half-open overlap test — identical to `WorkoutSource.isDismissed`'s span check.
    static func overlaps(_ aStart: Int, _ aEnd: Int, _ bStart: Int, _ bEnd: Int) -> Bool {
        aStart < bEnd && bStart < aEnd
    }

    /// Pick the newest notify-eligible bout and every eligible token to settle.
    ///
    /// A candidate is eligible when ALL hold:
    ///  - it ended at least `notifySettleSec` ago (can't fire mid-workout);
    ///  - it does not overlap a dismissed span (the user already said "not a workout" — matching
    ///    the read-time filter that hides it from the Workouts list);
    ///  - it does not overlap a real (manual / imported / live) session span — mirrors the
    ///    engine's own persist-time overlap suppression and covers a real row imported after the
    ///    detected twin was persisted;
    ///  - it does not overlap an already-settled span (drift-tolerant re-notification guard).
    ///
    /// [realSpans] and [dismissedSpans] are (start,end) pairs; [settledSpans] comes from parsing
    /// the persisted token set. Deterministic: newest by endTs, then startTs.
    static func decide(
        nowSec: Int,
        candidates: [Candidate],
        realSpans: [(start: Int, end: Int)],
        dismissedSpans: [(start: Int, end: Int)],
        settledSpans: [(start: Int, end: Int)]
    ) -> Decision {
        let eligible = candidates.filter { c in
            c.endTs <= nowSec - notifySettleSec
                && !dismissedSpans.contains { overlaps(c.startTs, c.endTs, $0.start, $0.end) }
                && !realSpans.contains { overlaps(c.startTs, c.endTs, $0.start, $0.end) }
                && !settledSpans.contains { overlaps(c.startTs, c.endTs, $0.start, $0.end) }
        }
        let notify = eligible.max { a, b in
            a.endTs != b.endTs ? a.endTs < b.endTs : a.startTs < b.startTs
        }
        return Decision(notify: notify,
                        settledTokens: eligible.map { token(startTs: $0.startTs, endTs: $0.endTs) }
                            .sorted())
    }

    /// Prune the persisted settled-token set: drop malformed entries, spans older than
    /// `maxTokenAgeSec`, and overflow beyond `maxTokens` keeping the newest starts. Returns a
    /// sorted (by startTs) list so the persisted value is deterministic and testable.
    static func prunedTokens(_ tokens: [String], nowSec: Int) -> [String] {
        let spans = tokens.compactMap { t -> (start: Int, end: Int, raw: String)? in
            let p = t.split(separator: ":")
            guard p.count == 2, let a = Int(p[0]), let b = Int(p[1]), b > a else { return nil }
            return (a, b, t)
        }
        let fresh = spans.filter { $0.end > nowSec - maxTokenAgeSec }
        let kept = fresh.sorted { $0.start > $1.start }.prefix(maxTokens)
        return kept.map(\.raw).sorted()
    }

    /// "47 min" / "1 h 23 min" — byte-mirrors Android `ScheduledReportPolicy.durationLabel` so the
    /// notification body reads identically on both platforms.
    static func durationLabel(minutes: Int) -> String {
        if minutes <= 0 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The measured-facts fragment ("47 min · avg 104 bpm · peaked 140 bpm"). Locale-neutral unit
    /// notation — the Apple notifier interpolates it into the localized sentence frame; Android
    /// posts it through [copy]'s full English body. avg/peak are omitted when absent, never
    /// invented, and no sport is claimed — attribution discipline: only what the detector measured.
    static func metricsText(_ c: Candidate) -> String {
        var parts = [durationLabel(minutes: (c.endTs - c.startTs) / 60)]
        if let avg = c.avgHr { parts.append("avg \(avg) bpm") }
        if let peak = c.maxHr { parts.append("peaked \(peak) bpm") }
        return parts.joined(separator: " · ")
    }

    /// English display name for a classifier token, for the Android verbatim body. nil for
    /// "other"/unknown tokens — they make no claim. The Apple path re-localizes the same token
    /// through `WorkoutSource.suggestedClassName` instead of using this string.
    static func classLabel(_ token: String?) -> String? {
        switch token {
        case "walk":     "Walking"
        case "run":      "Running"
        case "strength": "Strength Training"
        case "cycle":    "Cycling"
        case "ski":      "Skiing"
        default:         nil
        }
    }

    /// Title + full English body (the Android notifier posts these verbatim; the Apple notifier
    /// rebuilds the same text through the localized frame in `onAnalysisPass`). The frame tells
    /// the user the row is already saved, so the tap reads as review, not approval. When the bout
    /// carried a classifier suggestion the body names it — hedged ("looks like") because it is an
    /// advisory guess, not a measured fact.
    static func copy(_ c: Candidate) -> (title: String, body: String) {
        let tail = "Saved to Workouts — tap to review."
        guard let label = classLabel(c.suggestedClass) else {
            return ("Activity detected", metricsText(c) + ". " + tail)
        }
        return ("Activity detected",
                metricsText(c) + " — looks like \(label). " + tail)
    }
}

/// The notification plumbing: authorization, the Edit / "Not a workout" category, posting, and the
/// post-pass eligibility check `IntelligenceEngine.analyzeRecent` calls.
enum WorkoutDetectedNotifier {

    /// `UNNotificationCategory` / action identifiers. The category is registered at launch by the
    /// app roots (StrandApp / StrandiOSApp); actions are routed by `NotificationPresenter`.
    static let categoryId = "workout.detected"
    static let actionEditId = "workout.detected.edit"
    static let actionDismissId = "workout.detected.dismiss"

    /// userInfo keys — local epoch-second identifiers only, no health payload leaves the app.
    static let infoStartTs = "startTs"
    static let infoEndTs = "endTs"

    /// UserDefaults keys. `enabledDefaultsKey` is the Settings toggle ("workoutDetectedNotify",
    /// default OFF); `notifiedDefaultsKey` holds the settled span tokens.
    static let enabledDefaultsKey = "workoutDetectedNotify"
    static let notifiedDefaultsKey = "workouts.detectedNotified"

    /// Distinct request identifier per bout so a re-post for the same span replaces rather than
    /// stacks; a different span posts alongside (the newest-wins policy means at most one is
    /// outstanding in practice).
    static func requestId(startTs: Int) -> String { "workout.detected.\(startTs)" }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledDefaultsKey) }

    /// The category with its two actions. Edit opens the detected row for relabel; "Not a workout"
    /// durably dismisses it (same path as the Workouts row menu). Neither unlocks data — the span
    /// tokens ride in userInfo and the handlers re-resolve the row.
    static var category: UNNotificationCategory {
        let edit = UNNotificationAction(
            identifier: actionEditId,
            title: String(localized: "Edit"),
            options: [.foreground])
        let dismiss = UNNotificationAction(
            identifier: actionDismissId,
            title: String(localized: "Not a workout"),
            options: [.destructive])
        return UNNotificationCategory(identifier: categoryId, actions: [edit, dismiss],
                                      intentIdentifiers: [])
    }

    /// The same authorization request every notifier makes — called when the user flips the
    /// Settings toggle ON, never at launch or on a schedule.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Post-pass eligibility check. Called from `IntelligenceEngine.analyzeRecent` on every
    /// invocation — real passes and fingerprint-skipped ones alike — because a bout's 600 s settle
    /// window can elapse during quiet ticks with no new data. One notification per call at most;
    /// safe to call from any pass because the settled-token set dedupes across process death.
    ///
    /// Reads `Repository.workoutRows(from:to:)` — the SAME dismissed-filtered, cross-source-deduped
    /// read the Workouts list uses — so a bout is notified exactly as the user will see it, and a
    /// dismissed or later-imported-overlapping row can never fire. That read is bounded (36 h
    /// window ⇒ a handful of rows); when the preference is OFF the whole thing is one bool read.
    static func onAnalysisPass(repository: Repository) async {
        guard enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let now = Int(Date().timeIntervalSince1970)
        let rows = await repository.workoutRows(from: now - WorkoutDetectedPolicy.candidateWindowSec,
                                                to: now)
        let candidates = rows.filter { WorkoutSource.classify($0.source) == .detected }
            .map { WorkoutDetectedPolicy.Candidate(startTs: $0.startTs, endTs: $0.endTs,
                                                   avgHr: $0.avgHr, maxHr: $0.maxHr,
                                                   suggestedClass: $0.suggestedClass) }
        guard !candidates.isEmpty else { return }
        let realSpans = rows.filter { WorkoutSource.classify($0.source) != .detected }
            .map { (start: $0.startTs, end: $0.endTs) }
        let dismissed = WorkoutSource.parseDismissedSpans(
            UserDefaults.standard.stringArray(forKey: WorkoutSource.dismissedDefaultsKey) ?? [])
        let settled = WorkoutSource.parseDismissedSpans(
            UserDefaults.standard.stringArray(forKey: notifiedDefaultsKey) ?? [])

        let decision = WorkoutDetectedPolicy.decide(
            nowSec: now, candidates: candidates, realSpans: realSpans,
            dismissedSpans: dismissed, settledSpans: settled)
        guard let bout = decision.notify else { return }

        do {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Activity detected")
            // The metrics fragment ("47 min · avg 104 bpm") is locale-neutral unit notation the
            // policy builds once for both platforms; only the sentence frame around it localizes,
            // so the extractable key stays a single interpolation (dynamic strings can't be keys).
            // When the classifier suggested a class, the localized name joins the frame — hedged
            // ("looks like") because it is an advisory guess, never a measured fact.
            let metrics = WorkoutDetectedPolicy.metricsText(bout)
            if let name = WorkoutSource.suggestedClassName(bout.suggestedClass) {
                content.body = String(localized:
                    "\(metrics) — looks like \(name). Saved to Workouts — tap to review.")
            } else {
                content.body = String(localized:
                    "\(metrics). Saved to Workouts — tap to review.")
            }
            content.categoryIdentifier = categoryId
            content.sound = .default
            content.userInfo = [infoStartTs: bout.startTs, infoEndTs: bout.endTs]
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: requestId(startTs: bout.startTs),
                                      content: content, trigger: nil))
            // Mark settled only after a successful post (StrainTarget idiom): a suppressed or
            // denied delivery still gets its chance once notifications are usable again.
            var tokens = UserDefaults.standard.stringArray(forKey: notifiedDefaultsKey) ?? []
            for t in decision.settledTokens where !tokens.contains(t) { tokens.append(t) }
            UserDefaults.standard.set(
                WorkoutDetectedPolicy.prunedTokens(tokens, nowSec: now),
                forKey: notifiedDefaultsKey)
            if TestCentre.active(.workouts), let workoutsLog = await repository.workoutsLog {
                workoutsLog(WorkoutsTrace.detectedNotifyLine(
                    durMin: (bout.endTs - bout.startTs) / 60,
                    settledCount: decision.settledTokens.count))
            }
        } catch {
            // A failed post must not consume the tokens — the bout stays eligible so it can fire
            // on the next pass instead of being lost silently.
        }
    }
}
