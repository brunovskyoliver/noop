#if os(iOS)
import SwiftUI
import Combine

// The two "More to log" pages under the Journal, rebuilt in Broop form: Caffeine and the Mood check-in.
// Both keep the classic logic and stores (`CaffeineLogStore`, `CaffeineDecay`, `MoodStore`, `Repository`) and
// the classic copy; only the layout is new.

// MARK: - Caffeine

/// Caffeine: what may still be active, a quick log (optional mg, now or a few hours ago), the opt-in bedtime
/// cutoff with its late-intake nudge, and today's intakes. Same store and decay model as `CaffeineLogCard`.
struct BroopFinalACaffeinePage: View {
    @ObservedObject private var store = CaffeineLogStore.shared
    @EnvironmentObject private var model: AppModel
    @AppStorage(CaffeineLogCard.cutoffEnabledKey) private var cutoffEnabled = false
    @State private var tick = Date()
    @State private var mgDraft = ""
    @FocusState private var mgFocused: Bool
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let quickHoursAgo = [0, 1, 2, 3]

    /// Tonight's planned bedtime in minutes after midnight; 23:00 only until the first plan exists.
    private var bedtimeMinutes: Int { model.tonightPlan?.target.bedMinute ?? 23 * 60 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                lateNudge
                logSection
                cutoffSection
                if !store.intakes.isEmpty { loggedSection }
                BroopFootnote(text: String(localized: "Log a coffee, tea, or energy drink and NOOP shows a rough estimate of how much may still be active. It's a guide based on average caffeine clearance, not a measurement."))
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 12)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .broopNavPage(String(localized: "Caffeine"))
        .onReceive(ticker) { tick = $0 }
        .task { if model.tonightPlan == nil { await model.refreshTonightPlan() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { mgFocused = false }
            }
        }
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        let est = store.estimate()
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "Still active"), size: 10.5, color: BroopPalette.textSecondary)
            if est.hasActive {
                if let mg = est.totalRemainingMg {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "\(Int(mg.rounded()))").font(BroopType.number(56)).foregroundStyle(BroopPalette.textPrimary)
                        Text(verbatim: "mg").font(BroopType.number(24)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(verbatim: activeTitle(est))
                    .font(BroopType.demi(18))
                    .foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: activeDetail(est))
                    .font(BroopType.regular(13.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.intakes.isEmpty
                     ? "No caffeine logged. Log an intake to see an estimate."
                     : "Estimated mostly cleared. Nothing logged is likely still active.")
                    .font(BroopType.demi(18))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var lateNudge: some View {
        if cutoffEnabled, latePastCutoffCount > 0 {
            BroopAccountNotice(symbol: "moon.zzz", text: lateNudgeText)
        }
    }

    // MARK: Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: String(localized: "Log caffeine"))
            BroopFinalAField {
                HStack {
                    TextField("Amount in mg (optional)", text: $mgDraft)
                        .keyboardType(.numberPad)
                        .focused($mgFocused)
                    Text(verbatim: "mg").font(BroopType.demi(14)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(quickHoursAgo, id: \.self) { h in
                    Button {
                        let mg = Double(mgDraft.trimmingCharacters(in: .whitespaces))
                        let at = Calendar.current.date(byAdding: .hour, value: -h, to: tick) ?? tick
                        store.log(at: at, mg: mg)
                        mgDraft = ""
                        mgFocused = false
                    } label: {
                        Text(h == 0 ? "Now" : "\(h)h ago")
                            .font(BroopType.caps(11.5))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(h == 0 ? Color.black : BroopPalette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(h == 0 ? Color.white : BroopPalette.row))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
            }
            Text("Leave the amount blank if you don't know it. NOOP never invents a number.")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cutoff

    private var cutoffSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: String(localized: "Cutoff before bed"))
            BroopAccountGroup {
                BroopAccountToggle(title: String(localized: "Cutoff before bed"),
                                   detail: String(localized: "Warn me when I log caffeine too close to bedtime. A timing guide from your own bedtime, not a measurement."),
                                   isOn: $cutoffEnabled)
                if cutoffEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            BroopCaps(String(localized: "Last regular coffee by"), size: 10, color: BroopPalette.textSecondary)
                            Spacer()
                            Text(verbatim: timeLabel(CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: bedtimeMinutes)))
                                .font(BroopType.number(20)).foregroundStyle(BroopPalette.textPrimary)
                        }
                        (Text("Last regular coffee (95 mg) by about \(timeLabel(CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: bedtimeMinutes))), for bed at \(timeLabel(bedtimeMinutes)) from tonight's sleep plan. A bigger dose needs an earlier cutoff.") + unreachableSuffix)
                            .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let mg = mgAtBedtime, mg >= 1 {
                            Text("About \(Int(mg.rounded())) mg from what you logged will still be active at bedtime.")
                                .font(BroopType.regular(13))
                                .foregroundStyle(mg > CaffeineDecay.bedtimeResidualMg ? BroopPalette.warning : BroopPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: Logged

    private var loggedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: String(localized: "Logged today"))
            BroopAccountGroup {
                ForEach(store.intakes) { intake in
                    HStack(spacing: 12) {
                        Image(systemName: "cup.and.saucer").font(.system(size: 15, weight: .light))
                            .foregroundStyle(BroopPalette.textBody).frame(width: 22)
                        Text(verbatim: AppClock.hourMinute(intake.at))
                            .font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
                        Text(verbatim: intake.mg.map { "\(Int($0.rounded())) mg" } ?? String(localized: "amount not logged"))
                            .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
                        Spacer()
                        if intake.isImported {
                            // Apple Health re-imports its own intakes, so they are removed there.
                            BroopFinalAChip(text: String(localized: "Apple Health"))
                        } else {
                            Button { store.remove(intake.id) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 19))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, BroopFinalAPalette.danger)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove caffeine intake at \(AppClock.hourMinute(intake.at))"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
            }
        }
    }

    // MARK: Logic (as CaffeineLogCard)

    /// The planner's own "not reachable tonight" note when its median-bedtime guard set this bedtime.
    private var unreachableSuffix: Text {
        guard let plan = model.tonightPlan, !plan.target.reachable else { return Text(verbatim: "") }
        return Text(verbatim: " " + TonightPlanCard.unreachableNote)
    }

    private var latePastCutoffCount: Int {
        store.intakes.filter { intake in
            Calendar.current.isDateInToday(intake.at)
                && CaffeineDecay.isPastCutoff(intakeMinutes: minutesSinceMidnight(intake.at),
                                              bedtimeMinutes: bedtimeMinutes, doseMg: intake.mg)
        }.count
    }

    private var mgAtBedtime: Double? {
        let known = store.intakes.filter { $0.mg != nil }
        guard !known.isEmpty else { return nil }
        let cal = Calendar.current
        var bed = cal.date(byAdding: .minute, value: bedtimeMinutes, to: cal.startOfDay(for: tick)) ?? tick
        if bedtimeMinutes < 12 * 60 { bed = cal.date(byAdding: .day, value: 1, to: bed) ?? bed }
        return CaffeineDecay.totalRemainingMg(known.map { (doseMg: $0.mg!, hoursElapsed: bed.timeIntervalSince($0.at) / 3600) })
    }

    private var lateNudgeText: String {
        let n = latePastCutoffCount
        return n == 1
            ? String(localized: "A logged caffeine is past your bedtime cutoff. It may still be on board and keep you up. Just a timing heads-up.")
            : String(localized: "\(n) logged caffeines are past your bedtime cutoff. They may still be on board and keep you up. Just a timing heads-up.")
    }

    private func minutesSinceMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func timeLabel(_ minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        return AppClock.hourMinuteFormatter().string(from: Calendar.current.date(from: c) ?? Date())
    }

    private func activeTitle(_ est: CaffeineActiveEstimate) -> String {
        if let mg = est.totalRemainingMg { return String(localized: "About \(Int(mg.rounded())) mg may still be active") }
        return String(localized: "Caffeine may still be active")
    }

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
}

// MARK: - Mood

/// Mood check-in: five faces for today (one row per local day, edits overwrite), then the gated lines on which
/// body signals move with mood (`MindSection.insightLines`, the classic rule) and the standing footnote.
struct BroopFinalAMoodPage: View {
    @EnvironmentObject private var repo: Repository
    @State private var todayMood: Int?
    @State private var editing = false
    @State private var lines: [MindSection.MoodLine] = []
    @State private var moodDayCount = 0
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                checkIn
                insights
                BroopFootnote(text: String(localized: "Self-tracking, not a clinical assessment. If low mood persists, talk to a professional. You deserve support."))
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 16)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .broopNavPage(String(localized: "Mood"))
        .task(id: repo.refreshSeq) { await load() }
    }

    @ViewBuilder private var checkIn: some View {
        if let mood = todayMood, !editing {
            VStack(alignment: .leading, spacing: 14) {
                BroopCaps(String(localized: "Today's mood"), size: 10.5, color: BroopPalette.textSecondary)
                HStack(spacing: 16) {
                    Text(verbatim: MoodStore.face(for: mood))
                        .font(.system(size: 44))
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(BroopPalette.card))
                        .accessibilityHidden(true)
                    Text(verbatim: MoodStore.label(for: mood))
                        .font(BroopType.demi(24))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Button { withAnimation(.snappy) { editing = true } } label: {
                        HStack(spacing: 6) {
                            BroopCaps(String(localized: "Edit"), size: 11)
                            Image(systemName: "pencil").font(.system(size: 14, weight: .light)).foregroundStyle(BroopPalette.textPrimary)
                        }
                    }
                    .buttonStyle(BroopPressableStyle())
                    .accessibilityLabel(Text("Edit today's mood"))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Today's mood: \(MoodStore.label(for: mood)), \(mood) of 5"))
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("How's your mood today?")
                    .font(BroopType.demi(24))
                    .foregroundStyle(BroopPalette.textPrimary)
                HStack(spacing: 8) {
                    ForEach(Array(MoodStore.scale), id: \.self) { value in face(value) }
                }
            }
            .opacity(loaded ? 1 : 0)
        }
    }

    /// One face. The same neutral treatment for every value: no red for a low mood, just a marked choice.
    private func face(_ value: Int) -> some View {
        let selected = todayMood == value
        return Button { select(value) } label: {
            VStack(spacing: 8) {
                Text(verbatim: MoodStore.face(for: value)).font(.system(size: 30))
                BroopCaps(MoodStore.label(for: value), size: 8.5, color: selected ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.white.opacity(0.85) : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text("\(MoodStore.label(for: value)), mood \(value) of 5"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var insights: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: String(localized: "What tracks your mood"),
                            trailing: moodDayCount > 0 ? String(localized: "\(moodDayCount) check-ins") : nil)
            if lines.isEmpty {
                Text("Check in for a week and NOOP looks for body signals that move with your mood. A line only shows when the link is clear.")
                    .font(BroopType.regular(13.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: line.text)
                            .font(BroopType.demi(15.5))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(BroopPalette.track)
                                Capsule().fill(BroopPalette.rest).frame(width: geo.size.width * CGFloat(line.strength))
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)
                        Text(verbatim: line.caption)
                            .font(BroopType.regular(12.5))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func select(_ value: Int) {
        todayMood = value
        withAnimation(.snappy) { editing = false }
        Task {
            await repo.saveMood(day: Repository.localDayKey(Date()), value: value)
            await load()
        }
    }

    private func load() async {
        let mood = await repo.moodSeries()
        let todayKey = Repository.localDayKey(Date())
        let today = mood.last(where: { $0.day == todayKey }).map { Int($0.value.rounded()) }
        let built = MindSection.insightLines(mood: mood, days: repo.days)
        await MainActor.run {
            todayMood = today
            moodDayCount = mood.count
            lines = built
            loaded = true
        }
    }
}
#endif
