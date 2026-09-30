#if os(iOS)
import SwiftUI
import StrandAnalytics

// The v5 skin-temperature suite on the Broop Health tab: the illness heads-up, the body-clock estimate and the
// opt-in cycle awareness (with its opt-in card). Each renders its engine's result verbatim, worded through
// `SkinTempCopy` / `BodyClockCard` exactly as the classic cards word it; only the drawing is Broop's.

// MARK: - Phase colours

enum BroopFinalACyclePhase {
    static func color(_ phase: CyclePhaseEngine.Phase) -> Color {
        switch phase {
        case .follicular: return BroopFinalAPalette.follicular
        case .periOvulatory: return BroopFinalAPalette.ovulatory
        case .luteal: return BroopFinalAPalette.luteal
        case .unknown, .learning: return BroopPalette.textBody
        }
    }

    /// The top of the phase-tinted gradient (MCI: luteal purple, follicular slate-violet).
    static func wash(_ phase: CyclePhaseEngine.Phase) -> Color {
        switch phase {
        case .follicular: return Color(broopHex: 0x33355A)
        case .periOvulatory: return Color(broopHex: 0x1F3E48)
        case .luteal: return Color(broopHex: 0x3A2A55)
        case .unknown, .learning: return Color(broopHex: 0x2E3337)
        }
    }

    static func confidence(_ c: CyclePhaseEngine.Confidence) -> (String, Color) {
        switch c {
        case .learning: return (String(localized: "Learning"), BroopPalette.textSecondary)
        case .building: return (String(localized: "Building"), BroopPalette.warning)
        case .solid: return (String(localized: "Solid"), BroopPalette.teal)
        }
    }

    /// "~day 18–22", always a range, the classic wording.
    static func dayRange(_ r: CyclePhaseEngine.Result) -> String? {
        guard let lo = r.cycleDayLow, let hi = r.cycleDayHigh else { return nil }
        return lo == hi ? String(localized: "~day \(lo)") : String(localized: "~day \(lo)-\(hi)")
    }
}

private let broopFinalAAwarenessLine = String(localized: "For awareness only. Not a medical device, not contraception, not a substitute for professional care.")

// MARK: - Illness heads-up

/// The illness heads-up: amber when raised or already unwell, calm otherwise. The host mounts it only for a
/// non-quiet level, as the classic card.
struct BroopFinalAHeadsUpCard: View {
    let result: IllnessSignalEngine.Result
    var distance: IllnessDistance.Result? = nil

    private var alarming: Bool { result.level == .raised || result.level == .alreadyUnwell }
    private var tint: Color { alarming ? BroopPalette.warning : BroopPalette.rest }

    private var title: String {
        switch result.level {
        case .raised: return String(localized: "Heads-up")
        case .alreadyUnwell: return String(localized: "Rest up")
        case .suppressed: return String(localized: "Probably not illness")
        case .mild: return String(localized: "A few signals are up")
        case .quiet: return String(localized: "Nothing notable")
        }
    }

    private var glyph: String {
        switch result.level {
        case .raised: return "exclamationmark.triangle.fill"
        case .alreadyUnwell: return "bed.double.fill"
        case .suppressed: return "info.circle.fill"
        case .mild: return "waveform.path"
        case .quiet: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: glyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(alarming ? BroopPalette.bgBottom : BroopPalette.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(alarming ? tint : BroopPalette.row))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    BroopCaps(title, size: 12, color: alarming ? tint : BroopPalette.textPrimary)
                    Text(verbatim: SkinTempCopy.illness(result))
                        .font(BroopType.medium(14))
                        .foregroundStyle(BroopPalette.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !result.firedSignals.isEmpty {
                chips(String(localized: "Signals up"), result.firedSignals, tint: tint)
            }
            if !result.suppressedBy.isEmpty {
                chips(String(localized: "Explained by"), SkinTempCopy.confounders(result), tint: BroopPalette.textBody)
            }
            if result.level == .raised, let d = distance {
                Text(verbatim: String(localized: "Confidence: \(IllnessConfidence.band(d.distance)) (distance \(IllnessConfidence.formatted(d.distance)))"))
                    .font(BroopType.regular(12))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BroopPalette.card)
        .overlay(alignment: .leading) {
            if alarming { Rectangle().fill(tint).frame(width: 4) }
        }
        .clipShape(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chips(_ label: String, _ values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ForEach(values, id: \.self) { BroopFinalAChip(text: $0, tint: tint) } }
                VStack(alignment: .leading, spacing: 6) { ForEach(values, id: \.self) { BroopFinalAChip(text: $0, tint: tint) } }
            }
        }
    }
}

// MARK: - Body clock (Health)

/// The body-clock estimate against the wearer's schedule (not last night: that is the sleep screen's dial).
struct BroopFinalABodyClockEstimateCard: View {
    let estimate: CircadianEngine.PhaseEstimate
    var plan: CircadianEngine.JetLagPlan? = nil

    private var confidence: (String, Color) {
        switch estimate.confidence {
        case .unreadable: return (String(localized: "Calibrating"), BroopPalette.textSecondary)
        case .wide: return (String(localized: "Building"), BroopPalette.warning)
        case .solid: return (String(localized: "Solid"), BroopPalette.teal)
        }
    }

    var body: some View {
        BroopHealthCard {
            VStack(alignment: .leading, spacing: 12) {
                BroopFinalACardTitle(title: String(localized: "Body clock"),
                                     subtitle: String(localized: "Light + sleep timing only"),
                                     chip: confidence.0, chipTint: confidence.1)
                Text(verbatim: SkinTempCopy.bodyClockHeadline(estimate))
                    .font(BroopType.demi(20))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: SkinTempCopy.bodyClockNote(estimate))
                    .font(BroopType.medium(14))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Image(systemName: "moon.stars").font(.system(size: 13)).foregroundStyle(BroopPalette.rest)
                    BroopCaps(String(localized: "Body-clock low"), size: 9.5, color: BroopPalette.textSecondary)
                    Spacer()
                    Text(verbatim: BroopFinalABodyClockCard.clock(estimate.tempMinHour))
                        .font(BroopType.number(17))
                        .foregroundStyle(BroopPalette.textPrimary)
                }
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Estimated body-clock low around \(BroopFinalABodyClockCard.clock(estimate.tempMinHour))"))
                NavigationLink(value: BroopScreen.jetLag) {
                    BroopNavTile(symbol: "airplane", title: String(localized: "Jet-lag planner"))
                }
                .buttonStyle(BroopPressableStyle())
                if let plan, plan.direction != .none, let first = plan.days.first {
                    BroopHairline()
                    VStack(alignment: .leading, spacing: 6) {
                        BroopCaps(String(localized: "Plan · \(plan.estimatedDays)-day shift"), size: 10, color: BroopPalette.textSecondary)
                        Text("Day 1: bright light \(BroopFinalABodyClockCard.clock(first.brightLightStartHour))-\(BroopFinalABodyClockCard.clock(first.brightLightEndHour)), lights-out around \(BroopFinalABodyClockCard.clock(first.targetSleepHour)).")
                            .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: SkinTempCopy.planNote(plan))
                            .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Cycle awareness

/// The cycle-awareness card: a phase-tinted wash, "~day 18–22" with the phase name in its colour, the
/// sparkline of the nightly curve, the status and the likely period window, then LOG PERIOD START, the
/// tracker link and the off switch. Opt-in only; the host gates it.
struct BroopFinalACycleCard: View {
    let result: CyclePhaseEngine.Result
    var curve: [Double] = []
    var onLogPeriod: (() -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil
    var onTurnOff: (() -> Void)? = nil

    var body: some View {
        let hue = BroopFinalACyclePhase.color(result.phase)
        VStack(alignment: .leading, spacing: 14) {
            let conf = BroopFinalACyclePhase.confidence(result.confidence)
            BroopFinalACardTitle(title: String(localized: "Cycle awareness"),
                                 subtitle: String(localized: "From your nightly temperature"),
                                 chip: conf.0, chipTint: conf.1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let day = BroopFinalACyclePhase.dayRange(result) {
                    Text(verbatim: day).font(BroopType.demi(22)).foregroundStyle(BroopPalette.textPrimary)
                }
                Text(verbatim: SkinTempCopy.phaseTitle(result.phase))
                    .font(BroopType.demi(22))
                    .foregroundStyle(hue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if curve.count > 1 {
                BroopFinalASparkline(values: curve, color: hue).frame(height: 34).accessibilityHidden(true)
            }
            Text(verbatim: SkinTempCopy.cycleStatus(result))
                .font(BroopType.medium(14))
                .foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            if let w = result.nextPeriodWindow {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(BroopFinalAPalette.menstrual)
                    Text("A period is likely between \(BroopFinalAFormat.shortDay(w.earliestDay)) and \(BroopFinalAFormat.shortDay(w.latestDay)) (a window, not a fixed date).")
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if onLogPeriod != nil || onOpenDetail != nil {
                VStack(spacing: 8) {
                    if let onLogPeriod {
                        Button(action: onLogPeriod) {
                            HStack(spacing: 14) {
                                Image(systemName: "drop")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BroopFinalAPalette.menstrual)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])).foregroundStyle(BroopPalette.textSecondary))
                                BroopCaps(String(localized: "Log period start"), size: 11.5)
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.row))
                        }
                        .buttonStyle(BroopPressableStyle())
                        .accessibilityHint(Text("Optional. Stored only on this device."))
                    }
                    if let onOpenDetail {
                        Button(action: onOpenDetail) {
                            HStack {
                                BroopCaps(String(localized: "Cycle tracker"), size: 11.5)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(BroopPalette.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.row))
                        }
                        .buttonStyle(BroopPressableStyle())
                    }
                }
            }
            BroopHairline()
            Text(verbatim: broopFinalAAwarenessLine)
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            BroopFinalAPrivacyLine()
            if let onTurnOff {
                Button(action: onTurnOff) {
                    BroopCaps(String(localized: "Turn off cycle awareness"), size: 10.5, color: BroopPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityHint(Text("Stops reading a cycle phase from your nightly temperature. You can turn it back on here any time."))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [BroopFinalACyclePhase.wash(result.phase), BroopPalette.card],
                                     startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
        )
        .accessibilityElement(children: .contain)
    }
}

/// Shown when cycle awareness applies and is off: what it is, the privacy promise, and the switch.
struct BroopFinalACycleOptInCard: View {
    let onEnable: () -> Void

    var body: some View {
        BroopHealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(BroopFinalAPalette.luteal)
                    BroopCaps(String(localized: "Cycle awareness"), size: 12)
                }
                Text("NOOP can read a coarse menstrual-cycle phase from your nightly skin temperature, entirely on your device. It is awareness only: not contraception, not a fertility predictor, not a medical service.")
                    .font(BroopType.medium(14))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                BroopFinalAPrivacyLine()
                BroopHealthButton(title: String(localized: "Turn on cycle awareness"), kind: .secondary, action: onEnable)
            }
        }
    }
}

/// A light line through the values, scaled to their own range.
struct BroopFinalASparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, 1e-9)
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                 y: size.height - size.height * CGFloat((v - lo) / span))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Cycle tracker sheet

/// The cycle tracker, laid out like WHOOP's Menstrual Cycle Insights (cycle-calendar-luteal): a phase-tinted
/// top, "~day 18–22" and the phase in its colour, a month calendar marking the logged period starts, the
/// likely window (dashed) and today, then LOG PERIOD DATA with a date and a white plus, the logged history with
/// delete and delete-all, and the awareness and privacy lines. Same repository calls as `CycleTrackerView`.
///
/// NOOP has no per-day phase history, so the calendar does not paint phase bands; it marks only what is known.
struct BroopFinalACycleTracker: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let result: CyclePhaseEngine.Result
    var curve: [Double] = []

    @State private var starts: [String] = []
    @State private var selectedDate = Date()
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var confirmDeleteAll = false

    private var selectedDay: String { Repository.localDayKey(selectedDate) }
    private var alreadyLogged: Bool { starts.contains(selectedDay) }
    private var hue: Color { BroopFinalACyclePhase.color(result.phase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    calendar
                    logRow
                    history
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: broopFinalAAwarenessLine)
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        BroopFinalAPrivacyLine()
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(
                ZStack {
                    BroopPalette.bgBottom
                    LinearGradient(colors: [BroopFinalACyclePhase.wash(result.phase), BroopPalette.bgBottom],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
                }
                .ignoresSafeArea()
            )
            .broopFinalASheetBar(String(localized: "Cycle tracker"), onClose: { dismiss() })
            .task(id: repo.cycleTrackingSeq) { starts = await repo.periodStarts() }
            .confirmationDialog("Delete all logged period starts?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all period history", role: .destructive) {
                    Task {
                        await repo.deleteAllPeriodStarts()
                        await model.refreshV5Signals()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the on-device period-start history. Sensor history is not changed.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let day = BroopFinalACyclePhase.dayRange(result) {
                    Text(verbatim: day).font(BroopType.demi(24)).foregroundStyle(BroopPalette.textPrimary)
                }
                Text(verbatim: SkinTempCopy.phaseTitle(result.phase)).font(BroopType.demi(24)).foregroundStyle(hue)
            }
            if let w = result.nextPeriodWindow {
                Text("Likely period window: \(BroopFinalAFormat.shortDay(w.earliestDay))-\(BroopFinalAFormat.shortDay(w.latestDay)). This is a range, not a fixed date.")
                    .font(BroopType.medium(13.5)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: SkinTempCopy.cycleStatus(result))
                .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if curve.count > 1 {
                BroopFinalASparkline(values: curve, color: hue).frame(height: 30).padding(.top, 4).accessibilityHidden(true)
            }
        }
    }

    // MARK: Calendar

    private var calendar: some View {
        let cal = Calendar.current
        let days = monthDays(cal)
        let window = windowKeys(cal)
        let today = Repository.localDayKey(Date())
        return VStack(spacing: 14) {
            HStack(spacing: 18) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Previous month"))
                BroopCaps(month.formatted(.dateTime.month(.wide).year().locale(AppLanguage.activeLocale)), size: 12)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(cal.isDate(month, equalTo: Date(), toGranularity: .month))
                    .accessibilityLabel(Text("Next month"))
                Spacer()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(BroopPalette.textPrimary)
            .buttonStyle(.plain)

            let symbols = weekdaySymbols(cal)
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                    BroopCaps(s, size: 9.5, color: BroopPalette.textSecondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = Repository.localDayKey(date)
                        dayCell(date: date, logged: starts.contains(key), likely: window.contains(key),
                                isToday: key == today, future: date > Date())
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            HStack(spacing: 16) {
                legend(fill: BroopFinalAPalette.menstrual, dashed: false, String(localized: "Period start"))
                legend(fill: nil, dashed: true, String(localized: "Likely window"))
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card.opacity(0.85)))
    }

    private func dayCell(date: Date, logged: Bool, likely: Bool, isToday: Bool, future: Bool) -> some View {
        let n = Calendar.current.component(.day, from: date)
        return ZStack {
            if logged {
                Circle().fill(BroopFinalAPalette.menstrual)
            } else if likely {
                Circle().strokeBorder(BroopFinalAPalette.menstrual, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            if isToday {
                Circle().strokeBorder(Color.white, lineWidth: 1.5).padding(-3)
            }
            Text(verbatim: "\(n)")
                .font(BroopType.number(14))
                .foregroundStyle(future && !logged ? BroopPalette.textTertiary : BroopPalette.textPrimary)
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
        .onTapGesture { if !future { selectedDate = date } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: date.formatted(date: .abbreviated, time: .omitted)
                                 + (logged ? ", " + String(localized: "Period start") : "")
                                 + (likely ? ", " + String(localized: "Likely window") : "")))
    }

    private func legend(fill: Color?, dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                if let fill { Circle().fill(fill) }
                if dashed { Circle().strokeBorder(BroopFinalAPalette.menstrual, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])) }
            }
            .frame(width: 10, height: 10)
            Text(verbatim: text).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
        }
    }

    private func monthDays(_ cal: Calendar) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month)
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            out.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return out
    }

    private func weekdaySymbols(_ cal: Calendar) -> [String] {
        var f = cal
        f.locale = AppLanguage.activeLocale
        let s = f.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    private func windowKeys(_ cal: Calendar) -> Set<String> {
        guard let w = result.nextPeriodWindow,
              let a = BroopFinalAFormat.date(fromKey: w.earliestDay),
              let b = BroopFinalAFormat.date(fromKey: w.latestDay), a <= b else { return [] }
        var out: Set<String> = []
        var d = a
        while d <= b, out.count < 20 {
            out.insert(Repository.localDayKey(d))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    private func shiftMonth(_ by: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: by, to: month) { withAnimation(.snappy) { month = m } }
    }

    // MARK: Log

    private var logRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "drop")
                    .font(.system(size: 14))
                    .foregroundStyle(BroopFinalAPalette.menstrual)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])).foregroundStyle(BroopPalette.textSecondary))
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Log period data"), size: 11.5)
                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .accessibilityLabel(Text("Period started on"))
                }
                Spacer()
                Button {
                    Task {
                        await repo.logPeriodStart(day: selectedDay)
                        await model.refreshV5Signals()
                    }
                } label: {
                    Image(systemName: alreadyLogged ? "checkmark" : "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(BroopPressableStyle())
                .disabled(alreadyLogged)
                .opacity(alreadyLogged ? 0.5 : 1)
                .accessibilityLabel(Text(alreadyLogged ? "Already logged" : "Log period start"))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
            Text("This optional date anchors cycle day 1 and is checked against your nightly temperature pattern.")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalARule(title: String(localized: "Logged starts"))
            if starts.isEmpty {
                Text("No period starts logged yet.")
                    .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(starts.reversed().enumerated()), id: \.element) { i, day in
                        if i > 0 { BroopHairline().padding(.leading, 16) }
                        HStack(spacing: 12) {
                            Circle().fill(BroopFinalAPalette.menstrual).frame(width: 8, height: 8)
                            Text(verbatim: BroopFinalAFormat.longDay(day))
                                .font(BroopType.demi(15)).foregroundStyle(BroopPalette.textPrimary)
                            Spacer()
                            Button {
                                Task {
                                    await repo.deletePeriodStart(day: day)
                                    await model.refreshV5Signals()
                                }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(BroopFinalAPalette.danger)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(BroopPressableStyle())
                            .accessibilityLabel(Text("Delete \(BroopFinalAFormat.shortDay(day))"))
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                }
                .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                BroopFinalAPill(title: String(localized: "Delete all"), kind: .destructive) { confirmDeleteAll = true }
                    .padding(.top, 4)
            }
        }
    }
}
#endif
