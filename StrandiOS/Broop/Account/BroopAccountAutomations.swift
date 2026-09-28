#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Automations

/// The strap's inputs and haptic coaching, grouped the WHOOP way. Every switch binds the key or store the
/// classic Automations screen binds and fires the same side effects (authorisation requests, re-evaluation).
struct BroopAccountAutomationsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var router: NavRouter

    @AppStorage(AppModel.cycleAwarenessKey) private var cycleAwareness = false
    @AppStorage(AppModel.cycleAwarenessHiddenKey) private var cycleHidden = false
    @AppStorage(RhythmConsent.enabledKey) private var rhythmEnabled = false
    @StateObject private var inactivity = InactivityPrefs()
    @AppStorage(StandReminderNotifier.K.enabled) private var standOn = false
    @AppStorage(StandReminderNotifier.K.goalMinutes) private var standGoal = 5
    @AppStorage(StandReminderNotifier.K.remindAtMinute) private var standAt = 50
    @AppStorage(StandReminderNotifier.K.learnWindow) private var standLearn = true
    @AppStorage(StandReminderNotifier.K.manualStartHour) private var standFrom = 9
    @AppStorage(StandReminderNotifier.K.manualEndHour) private var standTo = 18
    @AppStorage(StandReminderNotifier.K.maxPerDay) private var standMax = 8
    @AppStorage(StandReminderNotifier.K.learnMuting) private var standMute = true
    @AppStorage(StandReminderNotifier.K.buzz) private var standBuzz = true
    @State private var standLearned = StandReminder.State()
    @AppStorage("notif.masterEnabled") private var wristAlertsMaster = false
    @AppStorage(HapticPrefs.breathing) private var breathingHaptic = true
    @AppStorage(HapticPrefs.intervals) private var intervalsHaptic = true
    @AppStorage(HapticPrefs.liveSession) private var liveSessionHaptic = true
    @AppStorage(HapticPrefs.workout) private var workoutHaptic = true

    var body: some View {
        BroopAccountPage(spacing: 30) {
            BroopAccountHeading(title: String(localized: "Automations"),
                                detail: String(localized: "Make the strap do things: tap to act, walk away to lock, train by feel."))
            section(String(localized: "Wrist alerts")) {
                BroopAccountToggle(title: String(localized: "Enable wrist alerts"),
                                   detail: String(localized: "The master switch for every wrist buzz (inactivity, stress, alerts). Off keeps the strap quiet no matter what else is on."),
                                   isOn: $wristAlertsMaster)
            }
            doubleTap
            section(String(localized: "Haptics"), footer: String(localized: "Choose which in-session cues buzz your wrist during a breathing session, timer, or workout.")) {
                BroopAccountToggle(title: String(localized: "Breathing pacer"),
                                   detail: String(localized: "Buzz each inhale and exhale during a breathing or resonance session."), isOn: $breathingHaptic)
                BroopAccountToggle(title: String(localized: "Interval timer"),
                                   detail: String(localized: "Buzz on each interval change."), isOn: $intervalsHaptic)
                BroopAccountToggle(title: String(localized: "Live Session cues"),
                                   detail: String(localized: "Coaching buzzes during a live workout session."), isOn: $liveSessionHaptic)
                BroopAccountToggle(title: String(localized: "Workout start & end"),
                                   detail: String(localized: "A buzz confirms a workout starting and saving."), isOn: $workoutHaptic)
            }
            section(String(localized: "Wear & presence"),
                    footer: String(localized: "React when the strap comes off or goes on. Run a Shortcut to set a Focus, pause media, mark yourself away.")) {
                shortcutRow(String(localized: "Run a Shortcut when taken off"),
                            String(localized: "Presence automation: set a Focus, pause media, set away…"), $behavior.wristOffShortcut)
                shortcutRow(String(localized: "Run a Shortcut when put back on"),
                            String(localized: "Reverse the above when you return."), $behavior.wristOnShortcut)
            }
            section(String(localized: "Haptic coaching"), footer: String(localized: "Train by feel. The strap buzzes so you don't have to watch a screen.")) {
                BroopAccountToggle(title: String(localized: "HR-zone coaching"),
                                   detail: String(localized: "Buzz when you hit your top zone (ease off) and again when you recover. Uses your max HR from Settings."),
                                   isOn: $behavior.zoneCoaching)
                BroopAccountToggle(title: String(localized: "Stress check-ins (haptic)"),
                                   detail: String(localized: "When a fresh, non-exercise HRV dip is detected while you're still, NOOP offers a one-minute guided breath: a single confirming buzz and a dismissible card. Never an alarm, never a diagnosis."),
                                   isOn: $behavior.stressCheckIn)
                if behavior.stressCheckIn {
                    BroopAccountToggle(title: String(localized: "Auto-nudge"),
                                       detail: String(localized: "Let the check-in fire on its own. Off keeps it manual: you start a breath from Breathe yourself."),
                                       isOn: $behavior.stressAutoNudge)
                    BroopAccountToggle(title: String(localized: "Respect quiet hours"),
                                       detail: String(localized: "Suppress auto-nudges overnight (10pm-7am)."), isOn: $behavior.stressQuietHours)
                    BroopAccountToggle(title: String(localized: "Use my resonance pace"),
                                       detail: String(localized: "Breathe at the pace your last \u{201C}find my pace\u{201D} sweep locked in, if you have one. Otherwise a calm 5.5 breaths/min."),
                                       isOn: $behavior.stressUseResonancePace)
                }
            }
            inactivitySection
            standSection
            section(String(localized: "Illness early-warning"),
                    footer: String(localized: "Watches your resting HR, HRV, skin temperature and respiration against your own 28-day baseline. On-device and approximate: informational only, not a diagnosis.")) {
                BroopAccountToggle(title: String(localized: "Watch for early-illness signs"),
                                   detail: String(localized: "Needs at least 14 days of history. When two or more signals drift together you get a banner on the dashboard and a notification, at most once a day."),
                                   isOn: $behavior.illnessWatch)
            }
            healthInsights
            section(String(localized: "Battery alerts")) {
                BroopAccountToggle(title: String(localized: "Notify on low and full battery"),
                                   detail: String(localized: "A reminder to recharge before bed when the strap drops to 15%, and a heads-up when it reaches 100%, each at most once per charge cycle."),
                                   isOn: $behavior.batteryAlerts)
                if behavior.batteryAlerts {
                    BroopAccountToggle(title: String(localized: "Predictive runtime warning"),
                                       detail: String(localized: "An early \"recharge tonight\" heads-up when the strap has about a day of estimated runtime left, at most once per discharge cycle. Turn off to keep only the 15% warning."),
                                       isOn: $behavior.batteryPredictiveAlerts)
                }
            }
            section(String(localized: "Strain target"),
                    footer: String(localized: "A once-a-day nudge when your Effort reaches the low end of today's optimal strain range, worked out from your recovery.")) {
                BroopAccountToggle(title: String(localized: "Notify when optimal strain is reached"),
                                   detail: String(localized: "Posts after your strap syncs and NOOP scores the day — not the exact second you cross it. At most once per day."),
                                   isOn: $behavior.strainTargetNudge)
            }
        }
        .broopAccountChrome(String(localized: "Automations"))
        .onAppear { standLearned = StandReminderNotifier.loadState() }
        .onChange(of: standOn) { _, on in StandReminderNotifier.setEnabled(on) }
        .onChange(of: behavior.illnessWatch) { _, on in
            model.reevaluateIllness()
            if on { IllnessNotifier.requestAuthorization() }
        }
        .onChange(of: cycleAwareness) { _, on in
            model.cycleAwarenessEnabled = on
            Task { await model.refreshV5Signals() }
        }
        .onChange(of: behavior.batteryAlerts) { _, on in if on { BatteryNotifier.requestAuthorization() } }
        .onChange(of: behavior.strainTargetNudge) { _, on in
            if on {
                StrainTargetNotifier.requestAuthorization()
                model.evaluateStrainTarget()
            }
        }
    }

    // MARK: Sections

    private func section<Rows: View>(_ title: String, footer: String? = nil, @ViewBuilder _ rows: () -> Rows) -> some View {
        BroopAccountSection(title: title, footer: footer) {
            BroopAccountGroup { rows() }
        }
    }

    private var doubleTap: some View {
        BroopAccountSection(title: String(localized: "Double-tap"),
                            footer: String(localized: "Double-tap the strap to trigger an action on \(Platform.deviceNounPhrase). (The strap exposes a single double-tap gesture.)")) {
            VStack(alignment: .leading, spacing: 12) {
                BroopAccountGroup {
                    BroopAccountPicker(title: String(localized: "When I double-tap"), selection: $behavior.doubleTapAction,
                                       options: MacActionKind.allCases.filter { $0 != .lockScreen }.map { ($0, $0.label) })
                    if behavior.doubleTapAction == .runShortcut {
                        BroopAccountRow(title: String(localized: "Shortcut name")) {
                            shortcutField(String(localized: "Shortcut name"), $behavior.doubleTapShortcut)
                        }
                    }
                    BroopAccountRow(title: String(localized: "Strap")) { BroopAccountBondChip() }
                }
                BroopAccountButton(title: String(localized: "Test action"), kind: .secondary,
                                   enabled: behavior.doubleTapAction != .none) {
                    model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
                }
                if !model.moments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            BroopCaps(String(localized: "Recent moments"), size: 10.5, color: BroopAccountStyle.caption)
                            Spacer()
                            Button {
                                model.moments.removeAll()
                                UserDefaults.standard.removeObject(forKey: "moments")
                            } label: { BroopCaps(String(localized: "Clear"), size: 10.5) }
                        }
                        ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, d in
                            Text(verbatim: Self.momentFormatter.string(from: d))
                                .font(BroopType.number(14)).foregroundStyle(BroopPalette.textBody)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
                }
            }
        }
    }

    private static let momentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        let uses24h = !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.activeLocale) ?? "H").contains("a")
        f.dateFormat = "EEE d MMM · " + (uses24h ? "HH:mm" : "h:mm a")
        return f
    }()

    private var notifMasterOn: Bool { wristAlertsMaster }

    private var inactivitySection: some View {
        section(String(localized: "Inactivity reminder"),
                footer: String(localized: "A gentle wrist buzz when you've been sitting too long, a nudge to get up and move. Inferred from the strap's motion on each history sync, so it lags real time by a sync or two.")) {
            BroopAccountToggle(title: String(localized: "Enable inactivity reminder"),
                               detail: String(localized: "Buzzes after you've been sitting past your threshold."), isOn: $inactivity.enabled)
            if inactivity.enabled {
                if !notifMasterOn {
                    warning(String(localized: "Notifications are off, so this can't buzz yet. Turn on the master switch in Notifications to let it through."))
                }
                stepper(String(localized: "Sitting for"), String(localized: "Minutes seated before the first nudge."),
                        $inactivity.thresholdMinutes, String(localized: "min"), 15...120, 15)
                stepper(String(localized: "Re-nudge every"), String(localized: "If you're still seated, buzz again this often."),
                        $inactivity.reNudgeMinutes, String(localized: "min"), 15...120, 15)
                stepper(String(localized: "Buzz strength"), String(localized: "How strong the buzz is."),
                        $inactivity.buzzLoops, "×", 1...4, 1)
                BroopAccountToggle(title: String(localized: "Only during active hours"),
                                   detail: String(localized: "Only nudge during your active hours."), isOn: $inactivity.activeHoursEnabled)
                if inactivity.activeHoursEnabled {
                    BroopAccountRow(title: String(localized: "Active hours")) {
                        HStack(spacing: 6) {
                            DatePicker("", selection: minutesBinding(\.activeStartMinutes), displayedComponents: .hourAndMinute)
                                .labelsHidden().accessibilityLabel(Text("Active hours start"))
                            Text("to").font(BroopType.medium(13)).foregroundStyle(BroopAccountStyle.caption)
                            DatePicker("", selection: minutesBinding(\.activeEndMinutes), displayedComponents: .hourAndMinute)
                                .labelsHidden().accessibilityLabel(Text("Active hours end"))
                        }
                    }
                }
            }
        }
    }

    private var standSection: some View {
        section(String(localized: "Stand reminder"),
                footer: String(localized: "Aim for a few minutes up and moving every hour. If the hour is still short at the reminder time, NOOP nudges you with time left to earn it. It learns which hours you're usually up, and goes quiet in hours you keep ignoring.")) {
            BroopAccountToggle(title: String(localized: "Remind me to stand"),
                               detail: String(localized: "Counted from the strap's motion on each sync; a minute counts when you're walking or moving on your feet."),
                               isOn: $standOn)
            if standOn {
                if !notifMasterOn {
                    warning(String(localized: "Wrist alerts are off, so this can't notify you yet. Turn on Wrist alerts at the top of this screen."))
                }
                stepper(String(localized: "Hourly goal"), String(localized: "Minutes up and moving that earn the hour."),
                        $standGoal, String(localized: "min"), 1...15, 1)
                stepper(String(localized: "Remind at"), String(localized: "Minute past the hour to check the goal."),
                        $standAt, String(localized: "past"), 30...55, 5)
                BroopAccountToggle(title: String(localized: "Learn my day"), detail: standWindowSummary, isOn: $standLearn)
                if !standLearn {
                    stepper(String(localized: "First reminder hour"), String(localized: "Reminders start in this hour."),
                            $standFrom, ":00", 0...22, 1)
                    stepper(String(localized: "Stop at"), String(localized: "No reminders from this hour on."),
                            $standTo, ":00", (standFrom + 1)...24, 1)
                }
                stepper(String(localized: "At most"), String(localized: "Reminders per day."), $standMax, String(localized: "a day"), 1...16, 1)
                BroopAccountToggle(title: String(localized: "Mute hours I keep ignoring"), detail: standMutedSummary, isOn: $standMute)
                if standMute && !standMutedSlots.isEmpty {
                    BroopAccountButtonRow(title: String(localized: "Unmute all"), showsChevron: false) {
                        StandReminderNotifier.resetMuting()
                        standLearned = StandReminderNotifier.loadState()
                    }
                }
                BroopAccountToggle(title: String(localized: "Buzz the strap too"),
                                   detail: String(localized: "A wrist buzz with the notification, while the strap is connected and worn."),
                                   isOn: $standBuzz)
            }
        }
    }

    private var standMutedSlots: [(weekend: Bool, hour: Int)] {
        StandReminder.mutedSlots(outcomes: standLearned.outcomes, nowSec: Int(Date().timeIntervalSince1970))
    }

    private var standWindowSummary: String {
        let days = Set(standLearned.history.filter(\.observed).map(\.day)).count
        guard let wd = StandReminder.learnedWindow(standLearned.history, weekend: false),
              let we = StandReminder.learnedWindow(standLearned.history, weekend: true) else {
            let w = StandReminder.defaultWindow
            return String(localized: "Still learning (\(days) of \(StandReminder.minLearnDays) days seen). Until then: \(Self.standRange(w, at: standAt)).")
        }
        return String(localized: "Learned from \(days) days. Weekdays \(Self.standRange(wd, at: standAt)), weekends \(Self.standRange(we, at: standAt)).")
    }

    private var standMutedSummary: String {
        let slots = standMutedSlots
        guard !slots.isEmpty else {
            return String(localized: "After three ignored reminders in the same hour, that hour goes quiet for a week.")
        }
        let list = slots.map { String(format: "%02d:%02d", $0.hour, standAt) + ($0.weekend ? " " + String(localized: "weekends") : "") }
        return String(localized: "Muted for now: \(list.joined(separator: ", ")).")
    }

    private static func standRange(_ w: StandReminder.Window, at minute: Int) -> String {
        String(format: "%02d:%02d–%02d:%02d", w.startHour, minute, max(w.startHour, w.endHour - 1), minute)
    }

    private var healthInsights: some View {
        section(String(localized: "Health insights"),
                footer: String(localized: "Optional, on-device reads from your nightly signals. Each is off by default: for awareness only, never a diagnosis.")) {
            if model.profile.cycleAwarenessApplies {
                BroopAccountToggle(title: String(localized: "Show cycle awareness"),
                                   detail: String(localized: "Shows the cycle-awareness card on Today and in Health. Turn off to hide it entirely — a private choice, never based on your age. You can turn it back on here any time."),
                                   isOn: Binding(get: { !cycleHidden }, set: { show in
                                       cycleHidden = !show
                                       if !show {
                                           cycleAwareness = false
                                           model.cycleAwarenessEnabled = false
                                           Task { await model.refreshV5Signals() }
                                       }
                                   }))
                if !cycleHidden {
                    BroopAccountToggle(title: String(localized: "Cycle awareness"),
                                       detail: String(localized: "Reads a coarse menstrual-cycle phase from your nightly skin temperature, entirely on \(Platform.deviceNounPhrase). Awareness only: not contraception, not a fertility predictor, not a medical service. The card appears in Health."),
                                       isOn: $cycleAwareness)
                }
            }
            BroopAccountToggle(title: String(localized: "Rhythm visualization (experimental)"),
                               detail: String(localized: "An experimental picture of your beat-to-beat heart timing. Not an ECG and not a diagnosis. You'll read and accept an experimental note before it shows anything."),
                               isOn: $rhythmEnabled)
            if rhythmEnabled {
                BroopAccountButtonRow(title: String(localized: "Open Rhythm")) { router.openRhythm() }
            }
        }
    }

    // MARK: Helpers

    private func stepper(_ title: String, _ help: String, _ value: Binding<Int>, _ suffix: String,
                         _ range: ClosedRange<Int>, _ step: Int) -> some View {
        BroopAccountRow(title: title, detail: help) {
            BroopAccountStepper(intValue: value, in: range, step: step, text: "\(value.wrappedValue)", unit: suffix, accessibility: title)
        }
    }

    private func warning(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BroopType.medium(13))
            .foregroundStyle(BroopPalette.warning)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func shortcutRow(_ title: String, _ help: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
            Text(verbatim: help).font(BroopType.regular(13)).foregroundStyle(BroopAccountStyle.caption)
            shortcutField(String(localized: "Shortcut name"), text)
        }
        .padding(16)
    }

    private func shortcutField(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(BroopType.medium(15))
            .foregroundStyle(BroopPalette.textPrimary)
            .padding(.horizontal, 12)
            .frame(minWidth: 150, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopAccountStyle.field))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BroopAccountStyle.fieldBorder, lineWidth: 1))
            .autocorrectionDisabled()
    }

    private func minutesBinding(_ key: ReferenceWritableKeyPath<InactivityPrefs, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = inactivity[keyPath: key]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                inactivity[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

/// Strap bond state, isolated so a strap tick re-renders only this chip.
private struct BroopAccountBondChip: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        BroopAccountChip(text: live.bonded ? String(localized: "Strap bonded") : String(localized: "Strap not connected"),
                         tint: live.bonded ? BroopAccountStyle.connected : BroopPalette.warning)
    }
}
#endif
