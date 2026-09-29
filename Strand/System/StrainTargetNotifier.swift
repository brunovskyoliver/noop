import Foundation
import UserNotifications
import StrandAnalytics

// MARK: - Target-strain notification (#593)
//
// A single opt-in, default-OFF celebratory nudge: once per day, when the day's Effort (strain) reaches the
// LOW end of today's recovery-derived OPTIMAL strain band (the #43 coupled read), post an "optimal strain
// reached" notification. iOS-only fork: the band comes from `StrainTarget` and Android is not updated. The pure policy
// is pinned by StrainTargetPolicyTests.
//
// CLEAN-ROOM: this reimplements the BEHAVIOUR only. The copy is NOOP's own — NOT WHOOP's decompiled
// strings — and the target is NOOP's own recovery→strain band (#43), not a value read off another app.
//
// The gate runs on the internal 0-100 Effort axis against the band from `AppModel.strainTarget` (the one
// resolver Home and the live coach read too); only the copy converts to the user's Effort scale. An
// optional second nudge fires when the day passes the band's top. It is NOT "the instant" you cross the target — day strain is a per-analytics-pass
// rollup, so it fires on the first pass at/after the crossing. Once-per-day dedupe via a persisted day
// string, the same crossing-dedupe idiom as BatteryNotifier / the Android ScheduledReportPolicy.
enum StrainTargetNotifier {
    private static let lastDayKey = "behavior.strainTargetLastDay"
    private static let lastUpperDayKey = "behavior.strainTargetUpperLastDay"

    /// Pure, testable policy + copy — no notification/UserDefaults runtime, so the decision logic is
    /// pinned by StrainTargetPolicyTests.
    enum StrainTargetPolicy {
        /// Fire at most once per day: only when enabled, BOTH the day strain and the target are known,
        /// the day strain has reached the target, and we haven't already posted for `today`. `dayStrain`
        /// and `target` must be on the SAME axis. A nil `target` means Charge is unknown ⇒ never fires.
        static func shouldNotify(enabled: Bool,
                                 dayStrain: Double?,
                                 target: Double?,
                                 lastNotifiedDay: String?,
                                 today: String) -> Bool {
            guard enabled, let dayStrain, let target else { return false }
            return dayStrain >= target && lastNotifiedDay != today
        }

        /// Title + body for the low-end nudge. `target` is already formatted on the user's Effort scale.
        /// NOOP's OWN wording — the feature is reimplemented behaviour, not copied copy.
        static func copy(target: String) -> (title: String, body: String) {
            (String(localized: "Optimal strain reached"),
             String(localized: "You've hit today's optimal strain target of \(target). Nice work — your recovery earned it."))
        }

        /// Title + body for the top-of-band nudge (`upper` formatted on the user's Effort scale).
        static func upperCopy(upper: String) -> (title: String, body: String) {
            (String(localized: "Above today's target"),
             String(localized: "Your Effort has passed the top of today's target range (\(upper)). Consider easing off so you can recover."))
        }
    }

    /// Ask up front (called when the user enables a nudge) so the system dialog appears at a
    /// predictable moment, not on the first crossing. BatteryNotifier idiom.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Run both policies against today's stored Effort (0–100) and the resolved band
    /// (`AppModel.strainTarget`). Comparisons happen on the 0–100 axis; the copy shows the bound on the
    /// user's Effort scale. Each persisted day marker advances only after an authorized post.
    static func onDayUpdate(day: String, effort: Double?, band: StrainTarget.Band?,
                            lowerEnabled: Bool, upperEnabled: Bool) {
        let d = UserDefaults.standard
        let scale = UnitPrefs.resolveEffortScale(d.string(forKey: UnitPrefs.effortScaleKey) ?? "")
        if StrainTargetPolicy.shouldNotify(enabled: lowerEnabled, dayStrain: effort, target: band?.lower,
                                           lastNotifiedDay: d.string(forKey: lastDayKey), today: day),
           let band {
            post(StrainTargetPolicy.copy(target: UnitFormatter.effortDisplay(band.lower, scale: scale)),
                 id: "strain-target", day: day, marker: lastDayKey)
        }
        if StrainTargetPolicy.shouldNotify(enabled: upperEnabled, dayStrain: effort, target: band.map { $0.upper + 0.01 },
                                           lastNotifiedDay: d.string(forKey: lastUpperDayKey), today: day),
           let band {
            post(StrainTargetPolicy.upperCopy(upper: UnitFormatter.effortDisplay(band.upper, scale: scale)),
                 id: "strain-target-upper", day: day, marker: lastUpperDayKey)
        }
    }

    private static func post(_ copy: (title: String, body: String), id: String, day: String, marker: String) {
        let center = UNUserNotificationCenter.current()
        // Authorization is requested once via requestAuthorization() when the toggle is enabled; here we
        // only check status (no second system prompt) — the BatteryNotifier idiom.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            UserDefaults.standard.set(day, forKey: marker)
        }
    }
}
