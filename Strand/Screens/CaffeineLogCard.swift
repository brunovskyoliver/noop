import SwiftUI
import StrandDesign
import StrandAnalytics

/// Caffeine window (#526) — log a caffeine intake (time + OPTIONAL mg) and see a plain on-device
/// "still active" hint. OPT-IN, manual-first: nothing shows until the user logs an intake, and the
/// estimate is clearly framed as a rough guide from average caffeine clearance, never a measurement or a
/// health claim. Reuses the journal logging patterns (UserDefaults-backed store, pill controls, NoopCard).
///
/// Honesty is enforced in the model (`CaffeineDecay` / `CaffeineLogStore`): an unknown amount stays
/// unknown (we never invent mg), the active hint covers the dose-unknown case in words, and the copy
/// states it's an estimate from what was logged.
struct CaffeineLogCard: View {
    /// The shared UserDefaults-backed store (#949). Shared rather than owned here so the Apple Health
    /// import and this card write through the same instance — see `CaffeineLogStore.shared`.
    @ObservedObject private var store = CaffeineLogStore.shared
    /// Tonight's plan supplies the bedtime (`AppModel.tonightPlan`), shared with the Sleep tab and the
    /// wind-down reminder so the cutoff never works back from a different bedtime.
    @EnvironmentObject private var model: AppModel

    /// Drives a live recompute of the estimate while the card is on screen (the decay is time-based).
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @State private var mgDraft = ""
    /// "How long ago" quick options for logging — hours back from now.
    private let quickHoursAgo: [Int] = [0, 1, 2, 3]

    // PR#566 (mvanhorn) — caffeine cutoff window + late-intake nudge. OPT-IN (default OFF, manual-first):
    // when enabled, NOOP works back from tonight's planned bedtime by each drink's own dose lead and flags
    // any of today's intakes past that cutoff, with a calm inline nudge. The key MIRRORS the Android pref
    // (KEY_CAFFEINE_CUTOFF) so a layout reads the same on both.
    @AppStorage(Self.cutoffEnabledKey) private var cutoffEnabled = false
    static let cutoffEnabledKey = "noop.caffeine.cutoffNudge"

    /// Tonight's planned bedtime (minutes after midnight), nil while the first plan is being built.
    private var bedtimeMinutes: Int? { Self.planBedtimeMinutes(model.tonightPlan) }

    /// The cutoff's bedtime: the plan's, or none while it loads. There is no stand-in bedtime, so the card
    /// shows a loading line instead of a cutoff worked back from a time nobody planned. Shared with the
    /// Broop caffeine page.
    static func planBedtimeMinutes(_ plan: SleepPlanner.Plan?) -> Int? { plan?.target.bedMinute }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Caffeine", overline: "Log")
            NoopCard(tint: StrandPalette.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Log a coffee, tea, or energy drink and NOOP shows a rough estimate of how much may still be active. It's a guide based on average caffeine clearance, not a measurement.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    activeHint

                    // PR#566 — the late-intake nudge sits right under the active hint when the cutoff is on
                    // and a logged intake is past it, so the timing warning is the first thing read.
                    lateIntakeNudge

                    Divider().overlay(StrandPalette.hairline)

                    // Optional amount — leave blank if you don't know it. We never invent a number.
                    HStack {
                        TextField("Amount in mg (optional)", text: $mgDraft)
                            .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                        Text("mg")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }

                    // Log "now" or a quick number of hours ago — mirrors the journal's day-pill row.
                    HStack {
                        Text("Had it")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                        Spacer()
                        ForEach(quickHoursAgo, id: \.self) { h in
                            logPill(h == 0 ? "Now" : "\(h)h ago", hoursAgo: h)
                        }
                    }

                    Divider().overlay(StrandPalette.hairline)
                    cutoffSection

                    if !store.intakes.isEmpty {
                        Divider().overlay(StrandPalette.hairline)
                        loggedList
                    }
                }
            }
        }
        .onReceive(ticker) { tick = $0 }
        .task { if model.tonightPlan == nil { await model.refreshTonightPlan() } }
    }

    // MARK: - Cutoff window (PR#566) — bedtime + late-intake nudge

    /// The bedtime + cutoff controls: a toggle, and (when on) a bedtime picker plus the derived "stop after"
    /// time. OFF by default — nothing here surfaces or nags until the user opts in. The cutoff time itself is
    /// computed from the dose-decay lead (`CaffeineDecay.cutoffMinutesSinceMidnight`), so it's never a magic
    /// number and matches the "still active" math.
    @ViewBuilder private var cutoffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cutoff before bed")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Warn me when I log caffeine too close to bedtime. A timing guide from your own bedtime, not a measurement.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $cutoffEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(StrandPalette.accent)
                    .accessibilityLabel("Warn me about caffeine close to bedtime")
            }
            if cutoffEnabled, let bedtimeMinutes {
                (Text("Last regular coffee (95 mg) by about \(cutoffTimeLabel(bedtimeMinutes)), for bed at \(timeLabel(bedtimeMinutes)) from tonight's sleep plan. A bigger dose needs an earlier cutoff.") + unreachableSuffix)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let mg = mgAtBedtime, mg >= 1 {
                    Text("About \(Int(mg.rounded())) mg from what you logged will still be active at bedtime.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(mg > CaffeineDecay.bedtimeResidualMg ? StrandPalette.statusWarning
                                                                              : StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if cutoffEnabled {
                Text("Working out tonight's bedtime…")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    /// The late-intake nudge — shown only when the cutoff is ON and at least one logged intake (today) falls
    /// past the cutoff for the user's bedtime. Honest: it warns about TIMING ("may keep you up"), never a
    /// health claim, and it disappears the moment no logged intake is past cutoff.
    @ViewBuilder private var lateIntakeNudge: some View {
        if cutoffEnabled, latePastCutoffCount > 0 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .accessibilityHidden(true)
                Text(lateNudgeText)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(StrandPalette.statusWarning.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// The planner's own "not reachable tonight" note when its median-bedtime guard set this bedtime.
    private var unreachableSuffix: Text {
        guard let plan = model.tonightPlan, !plan.target.reachable else { return Text(verbatim: "") }
        return Text(verbatim: " " + TonightPlanCard.unreachableNote)
    }

    /// Count of TODAY's logged intakes past their own cutoff for tonight's bedtime (the store keeps 48 h;
    /// yesterday's evening coffee is not about tonight). Uses the shared decay model's `isPastCutoff`, with
    /// each intake's own dose, so the UI and the cutoff math can't drift. Zero until the plan exists.
    private var latePastCutoffCount: Int {
        guard let bedtimeMinutes else { return 0 }
        return store.intakes.filter { intake in
            Calendar.current.isDateInToday(intake.at)
                && CaffeineDecay.isPastCutoff(intakeMinutes: minutesSinceMidnight(intake.at),
                                              bedtimeMinutes: bedtimeMinutes, doseMg: intake.mg)
        }.count
    }

    /// Estimated mg still active at tonight's bedtime from intakes with a known dose; nil when none has one.
    private var mgAtBedtime: Double? {
        let known = store.intakes.filter { $0.mg != nil }
        guard !known.isEmpty, let bedtimeMinutes else { return nil }
        let cal = Calendar.current
        var bed = cal.date(byAdding: .minute, value: bedtimeMinutes, to: cal.startOfDay(for: tick)) ?? tick
        if bedtimeMinutes < 12 * 60 { bed = cal.date(byAdding: .day, value: 1, to: bed) ?? bed }   // after midnight
        return CaffeineDecay.totalRemainingMg(known.map { (doseMg: $0.mg!, hoursElapsed: bed.timeIntervalSince($0.at) / 3600) })
    }

    private var lateNudgeText: String {
        let n = latePastCutoffCount
        // Whole-phrase variants per count so translators see complete sentences (never a stitched lead).
        return n == 1
            ? String(localized: "A logged caffeine is past your bedtime cutoff. It may still be on board and keep you up. Just a timing heads-up.")
            : String(localized: "\(n) logged caffeines are past your bedtime cutoff. They may still be on board and keep you up. Just a timing heads-up.")
    }

    /// The cutoff time-of-day label, derived from bedtime minus the dose-decay lead (shared model).
    private func cutoffTimeLabel(_ bedtimeMinutes: Int) -> String {
        timeLabel(CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: bedtimeMinutes))
    }

    /// Local minutes-since-midnight for a logged intake's wall-clock time.
    private func minutesSinceMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func timeLabel(_ minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return Self.cutoffTimeFormatter.string(from: date)
    }

    /// #1821: routed through AppClock so the Clock format setting reaches this label. Was a `static
    /// let`, which would have frozen the reader's choice at first use until the app relaunched.
    private static var cutoffTimeFormatter: DateFormatter { AppClock.hourMinuteFormatter() }

    // MARK: - Active hint

    /// The "caffeine still active" readout. Computed from the logged intakes via the decay model. Shows
    /// an mg estimate only when at least one active intake had a known amount; otherwise it's worded
    /// without a number (honest: we don't fabricate a dose). Renders a calm "all clear" line when nothing
    /// is active so the card always reads as live, never blank.
    @ViewBuilder private var activeHint: some View {
        let est = store.estimate()
        if est.hasActive {
            VStack(alignment: .leading, spacing: 4) {
                Text(activeTitle(est))
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(activeDetail(est))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(store.intakes.isEmpty
                 ? "No caffeine logged. Log an intake to see an estimate."
                 : "Estimated mostly cleared. Nothing logged is likely still active.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func activeTitle(_ est: CaffeineActiveEstimate) -> String {
        if let mg = est.totalRemainingMg {
            return String(localized: "About \(Int(mg.rounded())) mg may still be active")
        }
        return String(localized: "Caffeine may still be active")
    }

    /// Whole-phrase variants per combination (recent-intake line and/or multi-intake line) so
    /// translators always see a complete sentence rather than joined fragments.
    private func activeDetail(_ est: CaffeineActiveEstimate) -> String {
        let recent = est.hoursSinceMostRecentActive.map(hoursLabel)
        let count = est.activeIntakeCount
        switch (recent, count > 1) {
        case (let r?, true):
            return String(localized: "most recent intake about \(r) ago · \(count) intakes still in the estimate. Rough guide only, based on what you logged.")
        case (let r?, false):
            return String(localized: "most recent intake about \(r) ago. Rough guide only, based on what you logged.")
        case (nil, true):
            return String(localized: "\(count) intakes still in the estimate. Rough guide only, based on what you logged.")
        case (nil, false):
            return String(localized: "Rough guide only, based on what you logged.")
        }
    }

    private func hoursLabel(_ hrs: Double) -> String {
        if hrs < 1 { return String(localized: "under an hour") }
        let rounded = Int(hrs.rounded())
        return rounded == 1 ? String(localized: "1 hour") : String(localized: "\(rounded) hours")
    }

    // MARK: - Logged list

    @ViewBuilder private var loggedList: some View {
        Text("Logged today")
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        ForEach(store.intakes) { intake in
            HStack {
                Text(intakeLabel(intake))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                // No remove control on an imported intake (#949): the next sync re-reads the same window
                // from Apple Health and would bring it straight back, so offering the button would be
                // offering something NOOP cannot honour. Remove it where it was logged.
                if intake.isImported {
                    Text("Apple Health")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Button {
                        store.remove(intake.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.statusCritical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove caffeine intake at \(Self.timeFormatter.string(from: intake.at))")
                }
            }
        }
    }

    private func intakeLabel(_ intake: CaffeineIntake) -> String {
        let time = Self.timeFormatter.string(from: intake.at)
        if let mg = intake.mg {
            return String(localized: "\(time) · \(Int(mg.rounded())) mg")
        }
        return String(localized: "\(time) · amount not logged")
    }

    // MARK: - Controls

    private func logPill(_ label: LocalizedStringKey, hoursAgo: Int) -> some View {
        pillButton(label, selected: false) {
            let mg = Double(mgDraft.trimmingCharacters(in: .whitespaces))   // nil if blank/invalid
            let at = Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: tick) ?? tick
            store.log(at: at, mg: mg)
            mgDraft = ""
        }
    }

    private func pillButton(_ label: LocalizedStringKey, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(StrandFont.footnote)
                .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? StrandPalette.accent : StrandPalette.surfaceInset, in: Capsule())
                .overlay(Capsule().stroke(selected ? StrandPalette.accent : StrandPalette.hairline,
                                          lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// #1821: routed through AppClock so the Clock format setting reaches this label. Was a `static
    /// let`, which would have frozen the reader's choice at first use until the app relaunched.
    private static var timeFormatter: DateFormatter { AppClock.hourMinuteFormatter() }
}
