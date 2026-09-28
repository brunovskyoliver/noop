#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

// Intelligence: NOOP's own on-device Charge / Effort / Rest, shown the way WHOOP's performance reports read.
// A forecast dial for tomorrow's Charge, the model explained as weighted bars, and a By Day list whose rows
// open to "what shaped it". Every value comes from `IntelligenceEngine.results` and `RecoveryForecaster`,
// exactly as the classic screen reads them.

struct BroopInsightsIntelligenceView: View {
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var range: Range = .month
    @State private var expanded: Set<String> = []

    enum Range: Int, CaseIterable, Hashable {
        case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
        var days: Int? { self == .all ? nil : rawValue }
        var label: String {
            switch self {
            case .week: return String(localized: "W")
            case .month: return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half: return String(localized: "6M")
            case .year: return String(localized: "1Y")
            case .all: return String(localized: "ALL")
            }
        }
    }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let f = forecast { forecastCard(f).padding(.top, 8) }
                modelCard.padding(.top, BroopMetrics.section)
                statusOrList.padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .broopInsightsChrome(String(localized: "Intelligence"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await intelligence.analyzeRecent() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                }
                .disabled(intelligence.computing)
                .accessibilityLabel(Text("Recompute"))
            }
        }
        .task { if intelligence.results.isEmpty { await intelligence.analyzeRecent() } }
    }

    // MARK: Forecast

    /// Same inputs as the classic screen: results are newest-first, the forecaster wants oldest-first.
    private var forecast: RecoveryForecast? {
        let charge = intelligence.results.compactMap { $0.recovery }.reversed()
        let effort = intelligence.results.compactMap { $0.strain }.reversed()
        let sleeps = intelligence.results.compactMap { $0.sleepMin }
        let planned = sleeps.isEmpty ? RecoveryForecaster.defaultNeedHours : (sleeps.reduce(0, +) / Double(sleeps.count)) / 60
        return RecoveryForecaster.forecast(recentCharge: Array(charge), recentEffort: Array(effort),
                                           todayEffort: intelligence.results.first?.strain,
                                           plannedSleepHours: planned)
    }

    private func forecastCard(_ f: RecoveryForecast) -> some View {
        VStack(spacing: 18) {
            HStack {
                BroopCaps(String(localized: "Tomorrow's Charge"), size: 12)
                Spacer()
                BroopInsightsChip(text: String(localized: "Estimate"), color: BroopPalette.textBody)
            }
            BroopDial(score: .charge, value: f.charge, diameter: 150, lineWidth: 8)
            Text("± \(Int(f.band.rounded())) · \(StrandPalette.recoveryState(f.charge))")
                .font(BroopType.demi(13))
                .foregroundStyle(BroopPalette.textSecondary)
            BroopInsightsBody(text: String(localized: "You'll likely wake around \(Int(f.charge.rounded())) ± \(Int(f.band.rounded())) Charge if you sleep about \(Self.hours(f.plannedSleepHours)) tonight."),
                              size: 15, color: BroopPalette.textPrimary)
            BroopInsightsBody(text: String(localized: "Estimate from today's effort, your typical sleep and your \(f.nights)-night recovery baseline, not a measurement. Your real Charge is scored from tomorrow's HRV when you wake."),
                              size: 12.5, color: BroopPalette.textSecondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    private static func hours(_ h: Double) -> String {
        let half = (h * 2).rounded() / 2
        let whole = Int(half)
        let m = Int((half - Double(whole)) * 60)
        return m == 0 ? "\(whole)h" : "\(whole)h \(m)m"
    }

    // MARK: Model

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopInsightsSectionRule(title: String(localized: "How this works"))
            BroopInsightsBody(text: String(localized: "Charge weighs your HRV against your personal baseline (~55%), resting heart rate (~20%), rest quality (~15%), respiration (~5%) and skin-temperature deviation (~5%). Effort is a 0-\(UnitFormatter.effortScaleMax(effortScale)) cardiovascular load from time in heart-rate zones. Rest is staged from movement and heart rate. Everything is computed here from the strap's raw data. It works for any day Broop collected raw streams."),
                              size: 13.5, color: BroopPalette.textSecondary)
            BroopInsightsCard {
                VStack(alignment: .leading, spacing: 14) {
                    BroopCaps(String(localized: "Charge model"), size: 10.5, color: BroopPalette.textSecondary)
                    weight(String(localized: "Heart-rate variability"), 0.55)
                    weight(String(localized: "Resting heart rate"), 0.20)
                    weight(String(localized: "Rest quality"), 0.15)
                    weight(String(localized: "Respiration"), 0.05)
                    weight(String(localized: "Skin-temperature deviation"), 0.05)
                }
            }
        }
    }

    private func weight(_ label: String, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: label).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                Text(verbatim: "~\(Int(share * 100))%").font(BroopType.number(14)).foregroundStyle(BroopPalette.textBody)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(BroopPalette.bandHigh).frame(width: g.size.width * share / 0.55)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(Int(share * 100))% of Charge"))
    }

    // MARK: By day

    @ViewBuilder private var statusOrList: some View {
        if intelligence.computing {
            BroopInsightsCard {
                HStack(spacing: 12) {
                    ProgressView().tint(BroopPalette.textSecondary)
                    Text("Crunching your raw streams…").font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        } else if let note = intelligence.note {
            BroopInsightsNote(symbol: "moon.zzz", title: nil, text: note)
        } else if intelligence.results.isEmpty {
            VStack(spacing: 12) {
                BroopInsightsSyncNote()
                BroopInsightsNote(symbol: "brain.head.profile", title: String(localized: "Building from your strap"),
                                  text: String(localized: "This builds from the strap as it syncs. Effort and rest appear after you have worn it and slept a night. Charge needs about four nights of sleep to learn your baseline (you'll see \"Calibrating\" until then), and keeps sharpening over your first couple of weeks. On a WHOOP 5 or MG the strap banks little history, so the night count can climb slowly or sit at 0 of 4 until you have worn it across a few nights. That's its sync limit, not a fault. Import your WHOOP export to skip the wait."))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                BroopInsightsSectionRule(title: String(localized: "By day"), trailing: filtered.count == 1 ? String(localized: "1 day") : String(localized: "\(filtered.count) days"))
                BroopUnderlineTabs(options: Range.allCases, selection: $range) { $0.label }
                    .padding(.bottom, 4)
                if filtered.isEmpty {
                    BroopInsightsNote(symbol: "calendar", title: nil,
                                      text: String(localized: "No scored days in this window. Widen the range or import more history."))
                } else {
                    ForEach(filtered) { dayRow($0) }
                }
            }
        }
    }

    private var filtered: [IntelligenceEngine.Computed] {
        guard let n = range.days else { return intelligence.results }
        let date = Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date()
        let cutoff = Repository.localDayKey(date)
        return intelligence.results.filter { $0.day >= cutoff }
    }

    private func dayRow(_ d: IntelligenceEngine.Computed) -> some View {
        let open = expanded.contains(d.day)
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy) { if open { expanded.remove(d.day) } else { expanded.insert(d.day) } }
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        BroopCaps(Self.dayTitle(d.day), size: 11.5)
                        Spacer()
                        if d.recovery != nil {
                            BroopInsightsChip(text: ChargeBreakdownFormat.tierTag(d.confidence), color: Self.confidenceColor(d.confidence))
                        }
                        BroopInsightsChip(text: d.source.badge, color: BroopPalette.textBody)
                        if !d.drivers.isEmpty {
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
                        }
                    }
                    HStack(spacing: 0) {
                        stat(String(localized: "Charge"), d.recovery.map { "\(Int($0.rounded()))%" } ?? "—",
                             d.recovery.map(BroopPalette.band) ?? BroopPalette.textSecondary)
                        stat(String(localized: "Effort"), d.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "—",
                             d.strain == nil ? BroopPalette.textSecondary : BroopPalette.effort)
                        stat(String(localized: "Rest"), d.sleepMin.map { BroopFormat.duration($0) } ?? "—", BroopPalette.rest)
                        stat(String(localized: "HRV"), d.hrv.map { "\(Int($0.rounded()))" } ?? "—", BroopPalette.textPrimary)
                        stat(String(localized: "RHR"), d.rhr.map { "\($0)" } ?? "—", BroopPalette.textPrimary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(d.drivers.isEmpty)
            if open, !d.drivers.isEmpty { drivers(d) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BroopCaps(label, size: 8.5, color: BroopPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(BroopType.number(18)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func drivers(_ d: IntelligenceEngine.Computed) -> some View {
        let maxMag = Double(max(1, d.drivers.map { abs($0.deltaPoints) }.max() ?? 1))
        return VStack(alignment: .leading, spacing: 14) {
            BroopHairline()
            BroopCaps(String(localized: "What shaped it"), size: 10, color: BroopPalette.textSecondary)
            ForEach(Array(d.drivers.enumerated()), id: \.offset) { _, driver in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(driver.label)).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                        Spacer()
                        Text(verbatim: ChargeBreakdownFormat.chipLabel(deltaPoints: driver.deltaPoints))
                            .font(BroopType.number(14))
                            .foregroundStyle(driver.deltaPoints >= 0 ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts)
                    }
                    Text(verbatim: driver.baselineText.isEmpty ? driver.valueText : "\(driver.valueText) · \(driver.baselineText)")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                    BroopInsightsImpactBar(fraction: Double(driver.deltaPoints) / maxMag,
                                           color: driver.deltaPoints >= 0 ? BroopInsightsPalette.helps : BroopInsightsPalette.hurts,
                                           height: 9)
                    Text(LocalizedStringKey(driver.verdict)).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: ChargeBreakdownFormat.driverAccessibilityLabel(driver)))
            }
            if let rel = d.skinTempRel {
                HStack {
                    BroopCaps(String(localized: "Skin temperature"), size: 10, color: BroopPalette.textSecondary)
                    Spacer()
                    Text(verbatim: "\(ChargeBreakdownFormat.skinTempDeviationLabel(rel)) · \(ChargeBreakdownFormat.skinTempTierWord(rel.tier))")
                        .font(BroopType.demi(12.5)).foregroundStyle(BroopPalette.textBody)
                }
            }
        }
    }

    private static func confidenceColor(_ c: ScoreConfidence) -> Color {
        switch c {
        case .solid: return BroopInsightsPalette.helps
        case .building: return BroopPalette.textBody
        case .calibrating: return BroopInsightsPalette.hurts
        }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayTitle(_ key: String) -> String {
        guard let d = keyFormatter.date(from: key) else { return key }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// The "Syncing strap history" line, isolated so the 1 Hz live state never re-renders the page.
struct BroopInsightsSyncNote: View {
    @EnvironmentObject private var live: LiveState
    var body: some View {
        if live.backfilling {
            HStack(spacing: 10) {
                ProgressView().tint(BroopPalette.textSecondary)
                Text(live.syncChunksThisSession > 0
                     ? String(localized: "Syncing strap history… \(live.syncChunksThisSession) chunks pulled")
                     : String(localized: "Syncing strap history…"))
                    .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                Spacer()
            }
        }
    }
}
#endif
