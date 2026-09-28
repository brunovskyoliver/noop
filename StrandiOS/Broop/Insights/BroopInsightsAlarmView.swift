#if os(iOS)
import SwiftUI
import StrandAnalytics
import UIKit

// The Sleep Planner: WHOOP's planner layout (goal capsule, suggested bedtime and wake time, the time-in-bed
// band, the ALARM sheet with its two tiles) over NOOP's alarm surface. Behaviour is the classic
// `SmartAlarmView`'s, unchanged: the strap alarm is armed only through `AppModel.applySmartAlarm()` when the
// alarm's on / time / weekdays / per-day overrides change, and the wind-down reminder through
// `WindDownNudge`. The bedtime comes from `AppModel.tonightPlan` (SleepPlanner), the one plan the caffeine
// cutoff and the reminder also read.
//
// AGENTS.md "two readouts of one fact" (#2353, #1864): there is ONE alarm-time picker (the "Set your wake
// time" sheet). The reminder's input is named "Usual wake time" and says it wakes nobody. Every statement
// about when the alarm fires (countdown, date stamp, "next buzz") resolves through `nextStrapAlarm(from:)`,
// the same pure `AppModel.nextSmartAlarmDate` the strap is armed from, gated on the alarm actually arming.

struct BroopInsightsAlarmView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var repo: Repository

    @State private var windDownOn = WindDownNudge.isEnabled
    @State private var showNotifDeniedAlert = false
    @State private var wakeMinutes = WindDownNudge.wakeMinutes
    @State private var perDayOn = WindDownNudge.hasPerDayOverrides
    @State private var overrides: [Int: Int] = WindDownNudge.perDayWakeOverrides
    @AppStorage("alarm.rejectStreak") private var alarmRejectStreak = 0
    /// Which SleepPlanner tier the planner headline shows: 0 = 100% (Peak), 1 = 85% (Perform), 2 = 70% (Get By).
    /// Display only; the reminder and caffeine cutoff always plan for the full need (`plan.target`).
    @AppStorage("broop.insights.sleepGoalTier") private var goalTier = 0

    @State private var sheet: PlannerSheet?

    enum PlannerSheet: String, Identifiable {
        case goal, wakeTime, alarmMode, weeklyPlan, explainer
        var id: String { rawValue }
    }

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                upper
                lower
                alarmPanel
            }
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            // Overscroll colours: the header slate above, the planner sheet below.
            VStack(spacing: 0) {
                BroopPalette.bgTop.frame(height: 400)
                BroopInsightsPalette.plannerSheet
            }
            .ignoresSafeArea()
        }
        .broopInsightsChrome(String(localized: "Sleep planner"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .weeklyPlan } label: {
                    Image(systemName: "calendar").font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel(Text("Weekly plan"))
            }
        }
        .sheet(item: $sheet) { s in sheetView(s) }
        .alert(String(localized: "Notifications are off"), isPresented: $showNotifDeniedAlert) {
            Button(String(localized: "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(String(localized: "Not now"), role: .cancel) {}
        } message: {
            Text("Turn on notifications for NOOP in Settings to get your wind-down reminder.")
        }
        .task(id: repo.refreshSeq) { await model.refreshTonightPlan() }
        // The arming triggers, exactly the classic card's: any change to the alarm's on / time / weekdays
        // re-arms (or disarms) through the one AppModel path.
        .onChange(of: behavior.smartAlarmEnabled) { _, _ in model.applySmartAlarm(); replan() }
        .onChange(of: behavior.smartAlarmMinutes) { _, _ in model.applySmartAlarm(); replan() }
        .onChange(of: behavior.smartAlarmWeekdays) { _, _ in model.applySmartAlarm(); replan() }
    }

    /// The plan's wake time follows the alarm, so rebuild it after an alarm edit.
    private func replan() { Task { await model.refreshTonightPlan() } }

    // MARK: Upper: headline and goal

    private var tier: SleepPlanner.Tier? {
        guard let plan = model.tonightPlan, !plan.tiers.isEmpty else { return nil }
        return plan.tiers[min(max(goalTier, 0), plan.tiers.count - 1)]
    }

    private var goalName: String { Self.goalName(goalTier) }

    static func goalName(_ tier: Int) -> String {
        switch tier {
        case 1: return String(localized: "Perform")
        case 2: return String(localized: "Get by")
        default: return String(localized: "Peak")
        }
    }

    static func goalPercent(_ tier: Int) -> Int { [100, 85, 70][min(max(tier, 0), 2)] }

    private var upper: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                Button { sheet = .explainer } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle").font(.system(size: 14))
                        BroopCaps(String(localized: "How it's planned"), size: 9.5, color: BroopPalette.textSecondary)
                    }
                    .foregroundStyle(BroopPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(model.tonightPlan == nil)
            }
            BroopBadge(size: 50)
            Text(verbatim: headline)
                .font(BroopType.demi(19))
                .foregroundStyle(BroopPalette.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            if let tier, !tier.reachable {
                Text("All of your need would mean going to bed much earlier than usual. Spread the rest over the next few nights.")
                    .font(BroopType.medium(13))
                    .foregroundStyle(BroopPalette.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            VStack(spacing: 10) {
                BroopCaps(String(localized: "Tomorrow I want to"), size: 11, color: BroopPalette.textSecondary)
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.9)).frame(height: 1)
                    Button { sheet = .goal } label: {
                        BroopCaps(goalName, size: 12)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(Capsule().fill(Color.black))
                            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2.2))
                    }
                    .buttonStyle(BroopPressableStyle())
                    .offset(y: 21)
                }
            }
        }
        .padding(.horizontal, BroopMetrics.page)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .background(BroopPalette.bgTop)
        .zIndex(1)
    }

    private var headline: String {
        guard let plan = model.tonightPlan, let tier else { return String(localized: "Working out tonight's bedtime…") }
        let bed = TonightPlanCard.clock(tier.bedMinute)
        if tier.reachable {
            return String(localized: "Go to bed at \(bed) tonight to get \(Self.goalPercent(goalTier))% of your sleep need, \(BroopFormat.duration(plan.needMin * tier.fraction)) of sleep.")
        }
        return String(localized: "Go to bed at \(bed), the earliest that fits your usual bedtime, for about \(BroopFormat.duration(tier.expectedSleepMin)) of sleep.")
    }

    // MARK: Lower: bedtime, wake time, time in bed

    /// Whether tonight's plan wakes you with the strap alarm (the same gate `tonightWakeMinute` uses).
    private func alarmDrivesWake(now: Date) -> Bool {
        guard let next = nextStrapAlarm(from: now) else { return false }
        return next.timeIntervalSince(now) < 24 * 3600
    }

    private var lower: some View {
        VStack(spacing: 0) {
            if let plan = model.tonightPlan, let tier {
                let fromAlarm = alarmDrivesWake(now: Date())
                HStack(alignment: .top) {
                    bigTime(TonightPlanCard.clock(tier.bedMinute),
                            label: [String(localized: "Suggested time"), String(localized: "to bed")],
                            color: tier.reachable ? BroopPalette.textPrimary : BroopPalette.warning)
                    Spacer()
                    bigTime(TonightPlanCard.clock(plan.wakeMinute),
                            label: fromAlarm ? [String(localized: "Your wake time"), String(localized: "strap alarm")]
                                             : [String(localized: "Usual"), String(localized: "wake time")],
                            color: BroopPalette.textPrimary)
                }
                .padding(.horizontal, 22)
                band(plan: plan, tier: tier, pinned: fromAlarm)
                    .padding(.top, 16)
            } else {
                ProgressView().tint(BroopPalette.textSecondary).padding(.vertical, 60)
            }
        }
        .padding(.top, 64)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity)
        .background(BroopInsightsPalette.plannerLower)
    }

    private func bigTime(_ time: String, label: [String], color: Color) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: time)
                .font(BroopType.number(38))
                .foregroundStyle(color)
                .broopNumeral(38, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(spacing: 2) {
                ForEach(label, id: \.self) { BroopCaps($0, size: 10.5, color: BroopPalette.textSecondary) }
            }
        }
        .frame(minWidth: 130)
    }

    private func band(plan: SleepPlanner.Plan, tier: SleepPlanner.Tier, pinned: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let left = w * 0.18
            let right = w * 0.82
            ZStack(alignment: .topLeading) {
                // Dashed drop lines up to the two values.
                ForEach([left, right], id: \.self) { x in
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 44)) }
                        .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                BroopCaps(String(localized: "Time in bed"), size: 10.5)
                    .frame(width: w).offset(y: 30)
                Rectangle().fill(Color(broopHex: 0x161B1F)).frame(width: w, height: 44).offset(y: 50)
                BroopInsightsHatch(spacing: 7)
                    .stroke(Color.white.opacity(0.42), lineWidth: 2)
                    .frame(width: right - left, height: 30)
                    .clipped()
                    .offset(x: left, y: 57)
                ForEach([left, right], id: \.self) { x in
                    Rectangle().fill(Color.white).frame(width: 2.5, height: 34).offset(x: x - 1.25, y: 55)
                }
                Text(verbatim: BroopFormat.duration(tier.inBedMin))
                    .font(BroopType.number(20))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Capsule().fill(Color.black))
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2))
                    .frame(width: w)
                    .offset(y: 53)
                if pinned {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 30, height: 30)
                        BroopStrapGlyph()
                            .stroke(Color.black, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 14)
                    }
                    .offset(x: right - 15, y: 20)
                    .accessibilityLabel(Text("Strap alarm set"))
                }
                // Dashed bracket with the night's sleep need.
                Path { p in
                    p.move(to: CGPoint(x: left, y: 100))
                    p.addLine(to: CGPoint(x: left, y: 122))
                    p.addLine(to: CGPoint(x: right, y: 122))
                    p.addLine(to: CGPoint(x: right, y: 100))
                }
                .stroke(BroopInsightsPalette.plannerRange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                VStack(spacing: 6) {
                    BroopCaps(String(localized: "Sleep need"), size: 11, color: BroopInsightsPalette.plannerRange)
                        .padding(.horizontal, 8)
                        .background(BroopInsightsPalette.plannerLower)
                    Text(verbatim: String(localized: "\(BroopFormat.duration(plan.needMin)) incl. \(BroopFormat.duration(plan.debtAddMin)) debt"))
                        .font(BroopType.demi(12.5))
                        .foregroundStyle(BroopInsightsPalette.plannerRange)
                }
                .frame(width: w)
                .offset(y: 114)
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time in bed \(BroopFormat.duration(tier.inBedMin)), sleep need \(BroopFormat.duration(plan.needMin))"))
    }

    // MARK: Alarm panel

    private var alarmPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $behavior.smartAlarmEnabled) {
                HStack(spacing: 14) {
                    BroopStrapGlyph()
                        .stroke(BroopPalette.textPrimary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 23.5)
                    Spacer()
                    BroopCaps(String(localized: "Alarm"), size: 13)
                    Spacer()
                }
            }
            .toggleStyle(BroopInsightsToggleStyle())
            .accessibilityLabel(Text("Wake me with a strap buzz"))

            HStack(spacing: 12) {
                tile(String(localized: "Alarm set to"),
                     behavior.smartAlarmEnabled ? String(localized: "Exact time") : String(localized: "Off")) { sheet = .alarmMode }
                tile(String(localized: "Alarm time"), TonightPlanCard.clock(behavior.smartAlarmMinutes),
                     dim: !behavior.smartAlarmEnabled) { sheet = .wakeTime }
            }

            countdown

            if behavior.smartAlarmEnabled {
                if !overrides.isEmpty, let next = nextStrapAlarmLabel {
                    panelText(String(localized: "Some days have a time of their own in your weekly plan. Next buzz \(next)."), color: BroopPalette.textBody)
                }
                repeatDays
                armingNote
            } else {
                panelText(String(localized: "Arms the strap to buzz at your wake time, even if NOOP is closed. Sends the exact alarm command the official app sends, confirmed buzzing on a real WHOOP 4.0 (community wire capture + on-device test, #535). Keep a backup alarm for anything you truly can't miss."))
            }

            if behavior.smartAlarmEnabled && alarmRejectStreak >= 2 {
                BroopInsightsNote(symbol: "exclamationmark.triangle.fill", tint: BroopPalette.warning,
                                  title: String(localized: "Your strap isn't accepting the alarm"),
                                  text: String(localized: "The strap keeps reporting a different time than NOOP sends, so its firmware alarm won't fire at your wake time — usually a strap whose clock or alarm has reset. Reset the strap in the official WHOOP app (or fully charge it and reconnect), and keep your phone's Clock alarm as your wake until it takes."))
            }

            BroopInsightsNote(symbol: "bell.slash", tint: BroopPalette.warning,
                              title: String(localized: "The strap alarm is a silent buzz, not a sound"),
                              text: String(localized: "The wake-alarm above buzzes your wrist from the strap's own firmware. It can't sound a loud alarm. We also schedule a backup notification at your wake time, but a sideloaded app can't sound a guaranteed wake on this device (that needs a critical-alert permission this build doesn't have), so Focus or silent mode can still mute it. Keep your phone's built-in Clock alarm as your real backup. NOOP's phone-based smart wake (light-sleep detection) is available on the Android app."))

            weeklyPlanRow
            reminderSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(BroopInsightsPalette.plannerSheet)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tile(_ label: String, _ value: String, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                BroopCaps(label, size: 10, color: BroopPalette.textSecondary)
                BroopCaps(value, size: 13, color: dim ? BroopPalette.textSecondary : BroopPalette.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BroopInsightsPalette.plannerTile))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(BroopPressableStyle())
    }

    private func panelText(_ text: String, color: Color = BroopPalette.textSecondary) -> some View {
        BroopInsightsBody(text: text, size: 12.5, color: color)
    }

    /// The one countdown on the screen, re-rendered each minute in its own leaf. Shown only when the alarm
    /// will actually arm; the date stamp resolves from the same tick as the countdown.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            if let text = strapAlarmCountdown(from: tick.date) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: text).font(BroopType.demi(17)).foregroundStyle(BroopInsightsPalette.toggleOn)
                    if let stamp = nextStrapAlarmStamp(from: tick.date) {
                        Text(verbatim: stamp).font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var repeatDays: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "Repeat"), size: 10, color: BroopPalette.textSecondary)
            HStack(spacing: 0) {
                ForEach(Self.weekdayOrder, id: \.self) { dow in
                    let on = SmartAlarmView.alarmWeekdayIsSelected(dow, in: behavior.smartAlarmWeekdays)
                    Button {
                        behavior.smartAlarmWeekdays = SmartAlarmView.alarmToggledWeekday(dow, in: behavior.smartAlarmWeekdays)
                    } label: {
                        Text(verbatim: String(Self.weekdayShort(dow).prefix(1)))
                            .font(BroopType.demi(14))
                            .foregroundStyle(on ? Color.black : BroopPalette.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(on ? Color.white : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(verbatim: Self.weekdayName(dow)))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(verbatim: SmartAlarmView.alarmWeekdaySummary(behavior.smartAlarmWeekdays))
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
        }
    }

    /// #864 honesty: a WHOOP 5/MG arms only with Experimental on, and a 5/MG wake is unconfirmed.
    @ViewBuilder private var armingNote: some View {
        if model.whoop5Detected && !PuffinExperiment.isEnabled {
            panelText(String(localized: "Your WHOOP 5/MG won't arm this until Experimental mode is on (Settings, Experimental). Right now your wake time is saved but the strap is NOT armed. Even with Experimental on, a 5/MG strap-driven wake is still unconfirmed on our side, so keep a backup alarm."),
                      color: BroopPalette.warning)
        } else if model.whoop5Detected {
            panelText(String(localized: "Armed on the strap itself with the experimental 5/MG command. A strap-driven wake is still unconfirmed on 5/MG on our side (confirmed only on WHOOP 4.0), so keep a backup alarm for anything you truly can't miss."))
        } else {
            panelText(String(localized: "Armed on the strap itself, so it can buzz at your wake time even if your phone is asleep or NOOP is closed. Sends the exact alarm command the official app sends, confirmed buzzing on a real WHOOP 4.0 (community wire capture + on-device test, #535). Keep a backup alarm for anything you truly can't miss."))
            // #1706: ask the strap what it has stored. Unconditional, as on the classic screen.
            BroopInsightsOutlineButton(title: String(localized: "Check what the strap has stored")) { model.ble.getStrapAlarm() }
            panelText(String(localized: "The answer from the strap appears in your strap log and debug export, with the raw bytes it replied with."),
                      color: BroopPalette.textTertiary)
        }
    }

    private var weeklyPlanRow: some View {
        Button { sheet = .weeklyPlan } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar").font(.system(size: 17)).foregroundStyle(BroopPalette.textPrimary).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Weekly plan"), size: 11.5)
                    Text(verbatim: overrides.isEmpty ? String(localized: "One wake time every day")
                                                     : String(localized: "\(overrides.count) days with a time of their own"))
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopInsightsPalette.plannerTile.opacity(0.7)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Bedtime reminder (wind-down)

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BroopInsightsSectionRule(title: String(localized: "Bedtime reminder")).padding(.top, 10)
            Toggle(isOn: $windDownOn) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remind me to wind down").font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                    Text("A calm evening reminder, timed from your wake time and usual sleep need. It's a suggestion, not an alarm.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(BroopInsightsToggleStyle())
            .accessibilityLabel(Text("Remind me to wind down"))
            .onChange(of: windDownOn) { _, on in
                WindDownNudge.setEnabled(on) { outcome in
                    if outcome == .denied {
                        windDownOn = false
                        showNotifDeniedAlert = true
                    }
                }
            }
            if windDownOn {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Named for what it is: an input to the reminder's arithmetic, not an alarm (#2353).
                        Text("Usual wake time").font(BroopType.demi(15)).foregroundStyle(BroopPalette.textPrimary)
                        Text("This time does not wake you. It only decides when the evening reminder fires.")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    DatePicker("", selection: broopInsightsMinutesBinding($wakeMinutes, onSet: WindDownNudge.setWakeMinutes),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel(Text("Your usual wake time"))
                }
                panelText(String(localized: "The nudge fires \(WindDownNudge.sleepNeedMinutes / 60)h \(WindDownNudge.leadMinutes)m before this. You'll be reminded around \(Self.hhmm(WindDownNudge.nudgeMinuteOfDay()))."),
                          color: BroopPalette.textBody)
                if let next = nextStrapAlarmLabel {
                    panelText(String(localized: "Your strap alarm is what wakes you, next on \(next)."))
                }
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetView(_ s: PlannerSheet) -> some View {
        switch s {
        case .goal:
            BroopInsightsGoalSheet(tier: $goalTier, plan: model.tonightPlan)
                .presentationDetents([.height(460)])
        case .wakeTime:
            BroopInsightsWakeTimeSheet(minutes: behavior.smartAlarmMinutes) { m in
                behavior.smartAlarmMinutes = m
                if !behavior.smartAlarmEnabled { behavior.smartAlarmEnabled = true }
            }
            .presentationDetents([.height(460)])
        case .alarmMode:
            BroopInsightsAlarmModeSheet(enabled: behavior.smartAlarmEnabled) { sheet = .wakeTime }
                .presentationDetents([.height(440)])
        case .weeklyPlan:
            BroopInsightsWeeklyPlanSheet(perDayOn: $perDayOn, overrides: $overrides, wakeMinutes: wakeMinutes,
                                         alarmEnabled: behavior.smartAlarmEnabled,
                                         alarmMinutes: behavior.smartAlarmMinutes,
                                         apply: { model.applySmartAlarm(); replan() })
                .presentationDetents([.large])
        case .explainer:
            if let plan = model.tonightPlan {
                BroopInsightsPlanExplainer(plan: plan).presentationDetents([.large])
            }
        }
    }

    // MARK: The one alarm resolver (verbatim from SmartAlarmView)

    private func nextStrapAlarm(from now: Date = Date()) -> Date? {
        guard behavior.smartAlarmEnabled, model.strapAlarmWillArm else { return nil }
        return AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes,
                                           weekdays: behavior.smartAlarmWeekdays,
                                           overrides: overrides,
                                           from: now)
    }

    private var nextStrapAlarmLabel: String? {
        guard let next = nextStrapAlarm() else { return nil }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEE jj:mm")
        return f.string(from: next)
    }

    private func nextStrapAlarmStamp(from now: Date) -> String? {
        nextStrapAlarm(from: now).map { date in
            let f = DateFormatter()
            f.locale = AppLanguage.activeLocale
            f.setLocalizedDateFormatFromTemplate("EEE d MMM jj:mm")
            return f.string(from: date)
        }
    }

    private func strapAlarmCountdown(from now: Date) -> String? {
        guard let next = nextStrapAlarm(from: now) else { return nil }
        let seconds = next.timeIntervalSince(now)
        guard seconds >= 60 else { return String(localized: "Alarm in less than a minute") }
        let f = DateComponentsFormatter()
        f.calendar = { var c = Calendar.current; c.locale = AppLanguage.activeLocale; return c }()
        f.unitsStyle = .full
        f.allowedUnits = [.day, .hour, .minute]
        f.zeroFormattingBehavior = .dropAll
        f.maximumUnitCount = 3
        guard let span = f.string(from: seconds), !span.isEmpty else { return nil }
        return String(localized: "Alarm in \(span)")
    }

    // MARK: Helpers

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func weekdayName(_ dow: Int) -> String {
        let names = [String(localized: "Sunday"), String(localized: "Monday"), String(localized: "Tuesday"),
                     String(localized: "Wednesday"), String(localized: "Thursday"), String(localized: "Friday"),
                     String(localized: "Saturday")]
        return (1...7).contains(dow) ? names[dow - 1] : String(localized: "Day \(dow)")
    }

    static func weekdayShort(_ dow: Int) -> String {
        switch dow {
        case 1: return String(localized: "Sun")
        case 2: return String(localized: "Mon")
        case 3: return String(localized: "Tue")
        case 4: return String(localized: "Wed")
        case 5: return String(localized: "Thu")
        case 6: return String(localized: "Fri")
        case 7: return String(localized: "Sat")
        default: return "?"
        }
    }
}

/// A minutes-since-midnight value bridged to a DatePicker's Date.
func broopInsightsMinutesBinding(_ minutes: Binding<Int>, onSet: @escaping (Int) -> Void = { _ in }) -> Binding<Date> {
    Binding(
        get: {
            var c = DateComponents(); c.hour = minutes.wrappedValue / 60; c.minute = minutes.wrappedValue % 60
            return Calendar.current.date(from: c) ?? Date()
        },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
            minutes.wrappedValue = m
            onSet(m)
        }
    )
}

// MARK: - Sheets

/// The planner's bottom-sheet look: slate panel, back-arrow title row.
private struct PlannerSheetChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left").font(.system(size: 20, weight: .regular))
                        .foregroundStyle(BroopPalette.textPrimary).frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel(Text("Back"))
                Spacer()
                Text(verbatim: title).font(BroopType.medium(19)).foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [BroopInsightsPalette.plannerSheet, Color(broopHex: 0x151A1E)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }
}

/// "Select your Sleep Goal." Peak / Perform / Get By, each with the bedtime that goal needs tonight.
struct BroopInsightsGoalSheet: View {
    @Binding var tier: Int
    let plan: SleepPlanner.Plan?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlannerSheetChrome(title: String(localized: "Select your sleep goal.")) {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(0..<3, id: \.self) { i in
                    Button { tier = i } label: {
                        HStack(spacing: 18) {
                            ZStack {
                                if tier == i {
                                    Circle().fill(Color.white)
                                    Circle().fill(Color.black).frame(width: 9, height: 9)
                                } else {
                                    Circle().strokeBorder(Color.white, lineWidth: 2.4)
                                }
                            }
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                BroopCaps("\(BroopInsightsAlarmView.goalPercent(i))% · \(BroopInsightsAlarmView.goalName(i))", size: 13,
                                          color: tier == i ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                                if let plan, i < plan.tiers.count {
                                    Text(verbatim: String(localized: "Bed by \(TonightPlanCard.clock(plan.tiers[i].bedMinute))"))
                                        .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tier == i ? .isSelected : [])
                }
                BroopInsightsBody(text: String(localized: "This only changes the bedtime the planner suggests. Your wind-down reminder and caffeine cutoff always plan for all of your sleep need."),
                                  size: 12, color: BroopPalette.textTertiary)
                BroopInsightsOutlineButton(title: String(localized: "Done"), color: BroopInsightsPalette.toggleOn) { dismiss() }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
        }
    }
}

/// "Set your wake time." The ONE picker for the strap alarm's time. Saving arms the alarm.
struct BroopInsightsWakeTimeSheet: View {
    @State var minutes: Int
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(minutes: Int, onSave: @escaping (Int) -> Void) {
        _minutes = State(initialValue: minutes)
        self.onSave = onSave
    }

    var body: some View {
        PlannerSheetChrome(title: String(localized: "Set your wake time.")) {
            VStack(spacing: 20) {
                DatePicker("", selection: broopInsightsMinutesBinding($minutes), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityLabel(Text("Strap alarm wake time"))
                BroopInsightsOutlineButton(title: String(localized: "Save & set alarm")) {
                    onSave(minutes)
                    dismiss()
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
}

/// "Choose your alarm mode." NOOP's strap alarm has one mode, Exact Time; the sheet says so plainly
/// instead of offering Sleep Goal or In the Green modes the strap is never told about.
struct BroopInsightsAlarmModeSheet: View {
    let enabled: Bool
    let onExactTime: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlannerSheetChrome(title: String(localized: "Choose your alarm mode")) {
            VStack(spacing: 16) {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onExactTime() }
                } label: {
                    VStack(spacing: 6) {
                        BroopCaps(String(localized: "Exact time"), size: 14)
                        Text("Wake up at a specific time.").font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(RoundedRectangle(cornerRadius: 6).fill(BroopInsightsPalette.plannerTile))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(enabled ? Color.white : Color.white.opacity(0.15), lineWidth: enabled ? 1.5 : 1))
                }
                .buttonStyle(BroopPressableStyle())
                BroopInsightsBody(text: String(localized: "The strap's firmware alarm buzzes at one exact time. Sleep-goal and in-the-green wake windows aren't available: NOOP arms only what it has confirmed the strap does."),
                                  size: 13, color: BroopPalette.textSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
        }
    }
}

/// Weekly plan: a wake time of its own for specific days. These move the strap alarm AND the reminder
/// on those days (#1864), and say so.
struct BroopInsightsWeeklyPlanSheet: View {
    @Binding var perDayOn: Bool
    @Binding var overrides: [Int: Int]
    let wakeMinutes: Int
    let alarmEnabled: Bool
    let alarmMinutes: Int
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle(isOn: $perDayOn) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Different wake time per day").font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                            Text("Set a wake time for specific days (a lie-in at the weekend, say). These times move your strap alarm AND the evening reminder on those days.")
                                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(BroopInsightsToggleStyle())
                    .accessibilityLabel(Text("Different wake time per day"))
                    .onChange(of: perDayOn) { _, on in
                        // Off clears every override and re-arms, so the alarm reverts to its single time.
                        if !on {
                            for weekday in 1...7 { WindDownNudge.setWakeOverride(weekday: weekday, minutes: nil) }
                            overrides = [:]
                            apply()
                        }
                    }
                    if perDayOn {
                        VStack(spacing: 0) {
                            ForEach(BroopInsightsAlarmView.weekdayOrder, id: \.self) { dow in
                                row(dow)
                                if dow != 1 { BroopHairline() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
                        BroopInsightsBody(text: untouchedExplainer, size: 12.5, color: BroopPalette.textSecondary)
                    }
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .broopInsightsChrome(String(localized: "Weekly plan"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("Done").font(BroopType.demi(16)) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var untouchedExplainer: String {
        guard alarmEnabled else { return String(localized: "Days you leave alone use the usual wake time above.") }
        return String(localized: "Days you leave alone keep your strap alarm at \(BroopInsightsAlarmView.hhmm(alarmMinutes)), and time the reminder from \(BroopInsightsAlarmView.hhmm(wakeMinutes)).")
    }

    private func row(_ dow: Int) -> some View {
        let has = overrides[dow] != nil
        let effective = overrides[dow] ?? wakeMinutes
        let name = BroopInsightsAlarmView.weekdayName(dow)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(BroopType.demi(15)).foregroundStyle(has ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                if !has {
                    Text("no time of its own").font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textTertiary)
                }
            }
            Spacer()
            if has {
                Button {
                    WindDownNudge.setWakeOverride(weekday: dow, minutes: nil)
                    overrides[dow] = nil
                    apply()
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BroopPalette.textSecondary).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear \(name) override, use the default wake time"))
            }
            DatePicker("", selection: Binding(
                get: {
                    var c = DateComponents(); c.hour = effective / 60; c.minute = effective % 60
                    return Calendar.current.date(from: c) ?? Date()
                },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                    WindDownNudge.setWakeOverride(weekday: dow, minutes: m)
                    overrides[dow] = m
                    apply()
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel(Text("\(name) wake time"))
        }
        .padding(.vertical, 10)
    }
}

/// "Your sleep recommendation": how tonight's bedtime is built, straight from the plan.
struct BroopInsightsPlanExplainer: View {
    let plan: SleepPlanner.Plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BroopInsightsBody(text: String(localized: "Your bedtime starts with your sleep need, adjusted for recent sleep debt and naps, then works back from your wake time allowing for how long you usually take to fall asleep and how efficiently you sleep."),
                                      size: 14, color: BroopPalette.textBody)
                    VStack(spacing: 0) {
                        line(String(localized: "Sleep need"), BroopFormat.duration(plan.needMin), bold: true)
                        dashed
                        line(String(localized: "Baseline"), BroopFormat.duration(plan.baseNeedMin), indent: true)
                        line(String(localized: "Sleep debt"), "+" + BroopFormat.duration(plan.debtAddMin), indent: true)
                        line(String(localized: "Recent naps"), "−" + BroopFormat.duration(plan.napSubMin), indent: true)
                        dashed
                        line(String(localized: "Sleep efficiency"), "\(Int((plan.efficiency * 100).rounded()))%")
                        line(String(localized: "Time to fall asleep"), "\(Int(plan.latencyMin)) min")
                        Rectangle().fill(Color.white.opacity(0.5)).frame(height: 2).padding(.vertical, 6)
                        line(String(localized: "Recommended time in bed"), BroopFormat.duration(plan.target.inBedMin), bold: true)
                        line(String(localized: "Wake"), TonightPlanCard.clock(plan.wakeMinute))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
                    BroopInsightsSectionRule(title: String(localized: "Bedtime by goal"))
                    VStack(spacing: 0) {
                        ForEach(Array(plan.tiers.enumerated()), id: \.offset) { i, t in
                            line("\(BroopInsightsAlarmView.goalPercent(i))% · \(BroopInsightsAlarmView.goalName(i))", TonightPlanCard.clock(t.bedMinute))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
                    BroopInsightsBody(text: String(localized: "Assumes \(Int((plan.efficiency * 100).rounded()))% sleep efficiency and \(Int(plan.latencyMin)) min to fall asleep. The wake time is your strap alarm, or your usual wake time in Alarms."),
                                      size: 12, color: BroopPalette.textTertiary)
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .broopInsightsChrome(String(localized: "Your sleep recommendation"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)) }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dashed: some View {
        Line().stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1).padding(.vertical, 6)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }

    private func line(_ label: String, _ value: String, bold: Bool = false, indent: Bool = false) -> some View {
        HStack {
            BroopCaps(label, size: bold ? 11.5 : 10.5, color: bold ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                .padding(.leading, indent ? 14 : 0)
            Spacer()
            Text(verbatim: value).font(BroopType.number(bold ? 19 : 15)).foregroundStyle(bold ? BroopPalette.textPrimary : BroopPalette.textBody)
        }
        .padding(.vertical, 6)
    }
}
#endif
