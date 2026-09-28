#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Broop Stress Monitor (`.stress`), rebuilt from the classic `StressView`: the 0–3 gauge, the day's
/// stress line, the plain-English read, the Total Day split, breathwork, the day's markers, the advanced
/// HRV lenses, the history trend and the methodology. Every number comes from the classic engines —
/// `StressModel` (daily proxy), `DaytimeStress.analyze` (intraday), `StressIndex` and `HRVFreqDomain` —
/// fed the same reads the classic screen makes; the day stepper only moves which day they read.
struct BroopHealthStressView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.stressPersonalBaselineKey) private var personalBaseline = false

    @State private var stored: [(day: String, value: Double)] = []
    @State private var model: StressModel?
    @State private var loaded = false
    @State private var dayOffset = 0
    @State private var daytime: DaytimeStress.Result?
    @State private var usesPersonalBaseline = false
    @State private var stressIndex: StressIndex.Components?
    @State private var freq: HRVFreqDomain.Bands?
    @State private var range: ExploreRange = .month
    @State private var selection: BroopHealthPoint?
    @State private var scrub: DaytimeStress.HourPoint?
    @State private var showSettings = false
    @State private var showInfo = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                BroopHealthDateNav(label: dayLabel,
                                   canGoBack: dayOffset < maxOffset, canGoForward: dayOffset > 0,
                                   onBack: { dayOffset += 1 }, onForward: { dayOffset -= 1 })
                    .frame(width: 230)
                    .frame(maxWidth: .infinity)
                if let model {
                    gauge(model).padding(.top, 18)
                    dayChart.padding(.top, 26)
                    Text(verbatim: insight(model))
                        .font(BroopType.medium(17))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)
                    totalDayCard.padding(.top, 24)
                    breatheCard.padding(.top, 12)
                    markers(model).padding(.top, BroopMetrics.section)
                    if hasAdvanced { advancedCard.padding(.top, 12) }
                    trendSection(model).padding(.top, BroopMetrics.section)
                } else if !loaded {
                    BroopHealthEmpty(symbol: "gauge.with.dots.needle.50percent", title: String(localized: "Stress Monitor"),
                                     message: String(localized: "Reading your heart-rate variability and resting heart rate…"))
                } else {
                    BroopHealthEmpty(symbol: "gauge.with.dots.needle.50percent", title: String(localized: "No stress history yet"),
                                     message: String(localized: "Stress appears once there are a few nights of resting heart rate and HRV, or after you import your WHOOP export in Data Sources."))
                    breatheCard.padding(.top, 12)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Stress Monitor")) {
                BroopHealthHeaderIcon(symbol: "gearshape", label: String(localized: "Stress settings")) { showSettings = true }
            }
        }
        .broopHealthScreen()
        .task(id: repo.refreshSeq) { await loadModel() }
        .task(id: "\(dayOffset)|\(repo.refreshSeq)|\(personalBaseline)") { await loadDay() }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showInfo) { methodologySheet }
    }

    // MARK: Days

    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    private var selectedKey: String { Repository.localDayKey(selectedDate) }
    private var maxOffset: Int {
        guard let first = repo.days.first?.day, let d = BroopHealthFormat.date(first) else { return 0 }
        let today = BroopHealthFormat.date(Repository.localDayKey(Date())) ?? Date()
        return max(0, Int(today.timeIntervalSince(d) / 86_400))
    }
    private var dayLabel: String {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default: return BroopHealthFormat.weekday(selectedKey)
        }
    }

    /// The daily 0–3 proxy for the selected day: today reads the classic hero value (which carries the
    /// newest scored night), other days the same day's point on the classic trend.
    private func dayScore(_ model: StressModel) -> Double? {
        if dayOffset == 0 { return model.score }
        return model.fullTrend.last { BroopHealthFormat.day($0.date) == selectedKey }?.value
    }

    // MARK: Loading

    private func loadModel() async {
        stored = await repo.series(key: "stress", source: "my-whoop")
        let days = repo.days, s = stored
        model = await CancellableAnalysis.run { StressModel(days: days, stored: s) }
        loaded = true
    }

    /// The classic `loadDaytime`, for the selected local day ([midnight, now] today; the whole day before).
    private func loadDay() async {
        daytime = nil; stressIndex = nil; freq = nil; scrub = nil
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end = dayOffset == 0 ? Date() : (cal.date(byAdding: .day, value: 1, to: start) ?? Date()).addingTimeInterval(-1)
        let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970)
        let tz = TimeZone.current.secondsFromGMT(for: start)
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { daytime = .empty; return }
        let rr = await repo.rrIntervals(from: from, to: to, limit: 200_000)
        let gravity = await repo.gravitySamplesUnion(from: from, to: to, limit: 200_000)
        let mode = PuffinExperiment.stressPersonalBaselineEnabled ? await scoringMode(before: start) : .dayRelative
        if case .baselineRelative = mode { usesPersonalBaseline = true } else { usesPersonalBaseline = false }
        let result = await runUnescalated(priority: .userInitiated) {
            DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity, tzOffsetSeconds: tz, mode: mode, includeTimeline: true)
        }
        guard !Task.isCancelled else { return }
        daytime = result
        let advanced = await runUnescalated { (index: StressIndex.components(rr: rr), freq: HRVFreqDomain.freqDomain(rr: rr)) }
        guard !Task.isCancelled else { return }
        stressIndex = advanced.index
        freq = advanced.freq
    }

    /// The classic personal daytime baseline: the 30 local days before the scored one, reduced per day.
    private func scoringMode(before dayStart: Date) async -> DaytimeStress.ScoringMode {
        let cal = Calendar.current
        var aggregates: [(hr: Double?, rmssd: Double?)] = []
        for back in stride(from: 30, through: 1, by: -1) {
            guard let s = cal.date(byAdding: .day, value: -back, to: dayStart),
                  let e = cal.date(byAdding: .day, value: 1, to: s) else { continue }
            let from = Int(s.timeIntervalSince1970), to = Int(e.timeIntervalSince1970) - 1
            let dayHR = await repo.hrSamples(from: from, to: to, limit: 200_000)
            guard !dayHR.isEmpty else { continue }
            let dayRR = await repo.rrIntervals(from: from, to: to, limit: 200_000)
            aggregates.append(DaytimeStress.dayDaytimeAggregate(hr: dayHR, rr: dayRR,
                                                                tzOffsetSeconds: TimeZone.current.secondsFromGMT(for: s)))
        }
        return DaytimeStress.scoringModeFromAggregates(aggregates)
    }

    // MARK: Gauge

    @ViewBuilder
    private func gauge(_ model: StressModel) -> some View {
        let scrubLevel = scrub?.level
        let value = scrubLevel ?? dayScore(model)
        let band = value.map { StressBand(score: $0) }
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    BroopHealthStressArc(value: value)
                        .frame(width: 262, height: 262)
                    VStack(spacing: 8) {
                        Text(verbatim: value.map(StressTrace.formatLevel) ?? "--")
                            .font(BroopType.number(60))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .broopNumeral(60)
                            .contentTransition(.numericText())
                        BroopCaps(band?.title ?? String(localized: "No data"), size: 15,
                                  color: band.map(BroopHealthStressBand.color) ?? BroopPalette.textSecondary)
                        Text(verbatim: gaugeCaption)
                            .font(BroopType.medium(13.5))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    .offset(y: 8)
                }
                HStack {
                    Text(verbatim: "0.0")
                    Spacer()
                    Text(verbatim: "3.0")
                }
                .font(BroopType.number(15))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 214)
                .offset(y: -34)
            }
            .frame(maxWidth: .infinity)
            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 12)
            .accessibilityLabel(Text("How this is computed"))
        }
        .padding(.bottom, -30)
    }

    private var gaugeCaption: String {
        if let scrub {
            return Date(timeIntervalSince1970: TimeInterval(scrub.startTs)).formatted(date: .omitted, time: .shortened)
        }
        return dayOffset == 0 ? (model?.usingStored == true ? String(localized: "Recorded today") : String(localized: "Daily score"))
            : String(localized: "Daily score")
    }

    // MARK: Day chart

    @ViewBuilder private var dayChart: some View {
        if let day = daytime, day.timeline.contains(where: { $0.level != nil }) {
            VStack(alignment: .leading, spacing: 8) {
                BroopHealthStressDayChart(hours: day.timeline, scrub: $scrub)
                    .frame(height: 190)
                if day.activityMaskedHours > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run").font(.system(size: 11))
                        Text("Shaded: active hours, read as exertion rather than stress")
                    }
                    .font(BroopType.regular(12))
                    .foregroundStyle(BroopPalette.textSecondary)
                }
            }
        } else if daytime != nil {
            BroopHealthCard(fill: BroopHealthPalette.innerPanel) {
                Text("Not enough heart-rate data from this day to draw the stress line.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            }
        } else {
            ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).frame(height: 190)
        }
    }

    private func insight(_ model: StressModel) -> String {
        if dayOffset == 0 { return model.explanation }
        guard let day = daytime, !day.scored.isEmpty else {
            return dayScore(model) == nil ? String(localized: "No stress reading for this day.")
                : String(localized: "Only the daily score is available for this day.")
        }
        let totals = StressTotals(hours: day.hours)
        let top: StressBand = [StressBand.low, .medium, .high].max { totals.hours($0) < totals.hours($1) } ?? .low
        let bandName: String = {
            switch top {
            case .low: return String(localized: "low")
            case .medium: return String(localized: "medium")
            case .high: return String(localized: "high")
            }
        }()
        return String(localized: "Most of your scored waking hours were in the \(bandName) stress zone, with \(day.highStressMinutes) min in the high zone.")
    }

    // MARK: Total Day

    @ViewBuilder private var totalDayCard: some View {
        if let day = daytime, !day.scored.isEmpty {
            let totals = StressTotals(hours: day.hours)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(BroopPalette.textSecondary)
                    BroopCaps(String(localized: "Total Day"), size: 12.5)
                    Spacer()
                    if let mean = day.dayMean {
                        BroopCaps(String(localized: "Avg \(StressTrace.formatLevel(mean))"), size: 10.5, color: BroopPalette.textSecondary)
                    }
                }
                BroopCaps(String(localized: "\(BroopHealthFormat.weekday(selectedKey)) stress · \(totals.total)h scored"),
                          size: 11, color: BroopPalette.textPrimary)
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach([StressBand.low, .medium, .high], id: \.self) { b in
                            if totals.hours(b) > 0 {
                                Rectangle().fill(BroopHealthStressBand.color(b))
                                    .frame(width: max(2, (geo.size.width - 6) * CGFloat(totals.fraction(b))))
                            }
                        }
                    }
                }
                .frame(height: 16)
                HStack(alignment: .top, spacing: 0) {
                    ForEach([StressBand.low, .medium, .high], id: \.self) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: BroopFormat.duration(Double(totals.hours(b) * 60)))
                                .font(BroopType.number(24)).foregroundStyle(BroopPalette.textPrimary)
                            HStack(spacing: 6) {
                                Rectangle().fill(BroopHealthStressBand.color(b)).frame(width: 10, height: 10)
                                BroopCaps(b.title, size: 11, color: BroopPalette.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(verbatim: usesPersonalBaseline
                     ? String(localized: "Each waking hour's 0-3 proxy, scored against your personal daytime baseline (how your own days usually run).")
                     : String(localized: "Each waking hour's 0-3 proxy, scored against your own calm hours that day."))
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopHealthPalette.innerPanel))
        }
    }

    // MARK: Breathwork

    @ViewBuilder private var breatheCard: some View {
        if let day = daytime, day.sustainedHigh, dayOffset == 0 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lungs").foregroundStyle(BroopHealthPalette.stressHigh)
                    BroopCaps(String(localized: "Sustained high stress"), size: 12)
                    Spacer()
                    BroopHealthStatusPill(tone: .warn, text: String(localized: "\(day.sustainedRun)h elevated"))
                }
                Text("Your last \(day.sustainedRun) hours have stayed in the high band. A few minutes of paced breathing can help downshift your nervous system.")
                    .font(BroopType.medium(15)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: BroopScreen.breathe) {
                    Text(verbatim: String(localized: "Start a Breathe session").uppercased())
                        .font(BroopType.caps(12.5)).tracking(1.3).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(BroopPressableStyle())
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        } else {
            NavigationLink(value: BroopScreen.breathe) {
                BroopHealthRow(symbol: "wind", title: String(localized: "Guided breathing"),
                               detail: String(localized: "Increase relaxation or alertness"))
            }
            .buttonStyle(BroopPressableStyle())
        }
    }

    // MARK: Markers

    private func markers(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopCaps(String(localized: "Markers"), size: 12.5)
                Spacer()
                BroopCaps(String(localized: "vs. 30-day baseline"), size: 10, color: BroopPalette.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                markerTile(title: String(localized: "Resting HR"), symbol: "arrow.down.heart",
                           value: model.rhrToday.map { "\($0)" }, unit: "bpm", delta: model.rhrDelta, higherIsStress: true)
                markerTile(title: String(localized: "HRV"), symbol: "waveform.path.ecg",
                           value: model.hrvToday.map { "\(Int($0.rounded()))" }, unit: "ms", delta: model.hrvDelta, higherIsStress: false)
                simpleTile(title: String(localized: "Calm time"), symbol: "leaf", value: model.calmTimeValue, caption: model.calmTimeCaption)
                simpleTile(title: String(localized: "Stress"), symbol: "gauge.with.dots.needle.50percent",
                           value: StressTrace.formatLevel(model.score),
                           caption: String(localized: "of 3 · \(model.band.title)"))
            }
        }
    }

    private func markerTile(title: String, symbol: String, value: String?, unit: String,
                            delta: Double?, higherIsStress: Bool) -> some View {
        var pill: (BroopHealthStatusPill.Tone, String)?
        if let delta {
            if abs(delta) >= 0.5 {
                let up = delta > 0
                pill = (up == higherIsStress ? .warn : .good,
                        String(localized: "\(up ? "+" : "−")\(Int(abs(delta).rounded())) vs base"))
            } else {
                pill = (.none, String(localized: "at baseline"))
            }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(BroopPalette.textSecondary)
                BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value ?? "--").font(BroopType.number(30)).foregroundStyle(BroopPalette.textPrimary)
                if value != nil { Text(verbatim: unit).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textPrimary) }
            }
            if let pill { BroopHealthStatusPill(tone: pill.0, text: pill.1) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopHealthPalette.vitalCard))
    }

    private func simpleTile(title: String, symbol: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(BroopPalette.textSecondary)
                BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
            }
            Text(verbatim: value).font(BroopType.number(30)).foregroundStyle(BroopPalette.textPrimary)
            Text(verbatim: caption).font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopHealthPalette.vitalCard))
    }

    // MARK: Advanced HRV

    private var hasAdvanced: Bool {
        if stressIndex != nil { return true }
        if let f = freq, f.lfhf != nil || f.hf > 0 { return true }
        return false
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BroopCaps(String(localized: "Advanced HRV"), size: 12.5)
                Spacer()
                BroopCaps(String(localized: "This day's R-R"), size: 10, color: BroopPalette.textSecondary)
            }
            if let si = stressIndex {
                advancedRow(String(localized: "Baevsky Stress Index"), "\(Int(si.si.rounded()))",
                            String(localized: "Autonomic rigidity from your heart-rate rhythm. Higher means a more rigid, stressed rhythm."))
            }
            if let f = freq {
                if let ratio = f.lfhf {
                    advancedRow(String(localized: "Autonomic balance (LF/HF)"), StressTrace.formatRatio(ratio),
                                String(localized: "Sympathetic vs parasympathetic tone from frequency-domain HRV. Higher leans sympathetic (stress-ward)."))
                } else if f.hf > 0 {
                    advancedRow(String(localized: "HF power"), "\(Int(f.hf.rounded()))",
                                String(localized: "Parasympathetic (rest) band of your HRV."))
                }
            }
            Text("Extra lenses computed from this day's R-R intervals. They are informational and do not change the stress score.")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func advancedRow(_ title: String, _ value: String, _ caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
                Text(verbatim: caption).font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(verbatim: value).font(BroopType.number(26)).foregroundStyle(BroopPalette.textPrimary)
        }
    }

    // MARK: Trend

    private func windowed(_ model: StressModel) -> [BroopHealthPoint] {
        let all = model.fullTrend
        var slice = all
        if let days = range.days, let last = all.last?.date {
            let cutoff = last.addingTimeInterval(-Double(days - 1) * 86_400)
            let s = all.filter { $0.date >= cutoff }
            slice = s.count >= 2 ? s : all
        }
        return slice.map { BroopHealthPoint(day: BroopHealthFormat.day($0.date), date: $0.date, value: $0.value) }
    }

    private func trendSection(_ model: StressModel) -> some View {
        let pts = windowed(model)
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        return VStack(alignment: .leading, spacing: 14) {
            BroopHealthHeading(text: String(localized: "Trend View"))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(selection.map { BroopHealthFormat.weekday($0.day) } ?? String(localized: "Average"),
                              size: 11, color: BroopPalette.textSecondary)
                    Text(verbatim: (selection?.value ?? avg).map(StressTrace.formatLevel) ?? "--")
                        .font(BroopType.number(34)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(34)
                }
                Spacer()
            }
            BroopHealthRangePicker(selection: $range)
            if pts.count >= 2 {
                BroopHealthTrendChart(points: pts, style: .bars, yDomain: 0...3, average: avg,
                                      color: { BroopHealthPalette.stress($0) },
                                      valueLabel: { StressTrace.formatLevel($0) },
                                      axisLabel: { String(format: "%.1f", $0) },
                                      selection: $selection, height: 220)
            } else {
                BroopHealthEmpty(title: String(localized: "No data"),
                                 message: String(localized: "Not enough recent days to chart a trend yet. Import a history or keep wearing your strap."))
            }
            BroopHealthFootnote(text: String(localized: "Daily 0-3 proxy · \(pts.count) days"))
        }
    }

    // MARK: Sheets

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $personalBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            BroopCaps(String(localized: "Personal daytime baseline"), size: 12)
                            Text("Score each hour against how your own days usually run once enough worn history exists, instead of against that day's calm hours. Experimental; the same switch lives in Settings → Experimental.")
                                .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(BroopHealthPalette.mint)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .navigationTitle(Text("Stress settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showSettings = false } }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private var methodologySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model?.usingStored == true
                         ? "Today's value is your recorded daily stress score (0-3)."
                         : "Stress is derived from two autonomic signals.")
                        .font(BroopType.demi(18)).foregroundStyle(BroopPalette.textPrimary)
                    Text("We compare today's resting heart rate and HRV to your own 30-day baseline. A higher-than-usual resting HR and a lower-than-usual HRV both push the score up, classic signs the body is activated. The combined shift is mapped onto a 0-3 scale: 0 is calm, 1.5 sits at your baseline, 3 is highly activated.")
                        .font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The line through the day is the same proxy at a finer grain: each waking hour, re-read every half hour, from that hour's heart rate and R-R. Hours spent moving are read as exertion and left out.")
                        .font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 0) {
                        legend("0-1", String(localized: "LOW"), BroopHealthPalette.stressLow)
                        legend("1-2", String(localized: "MEDIUM"), BroopHealthPalette.stressMedium)
                        legend("2-3", String(localized: "HIGH"), BroopHealthPalette.stressHigh)
                    }
                    .padding(.top, 6)
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .navigationTitle(Text("How this is computed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showInfo = false } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func legend(_ range: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                BroopCaps(label, size: 11)
                Text(verbatim: range).font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gauge arc

/// The 240° stress arc: a wide dim band under a thin bright gradient stroke (blue → green → amber),
/// with a short white needle at value / 3 of the sweep.
private struct BroopHealthStressArc: View {
    let value: Double?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 10
            let start = Angle.degrees(150), sweep = 240.0
            let gradient = Gradient(stops: [
                .init(color: BroopHealthPalette.stressLow, location: 0),
                .init(color: BroopHealthPalette.stressMedium, location: 0.5),
                .init(color: BroopHealthPalette.stressHigh, location: 1),
            ])
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: start, endAngle: .degrees(150 + sweep), clockwise: false)
            // Conic shading mapped onto the sweep.
            let shading = GraphicsContext.Shading.conicGradient(
                Gradient(stops: gradient.stops.map { .init(color: $0.color, location: $0.location * sweep / 360) }),
                center: c, angle: start)
            // A wide dim band, then a thin bright outer edge.
            ctx.drawLayer { layer in
                layer.opacity = 0.22
                layer.stroke(arc, with: shading, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
            }
            var edge = Path()
            edge.addArc(center: c, radius: r + 6.5, startAngle: start, endAngle: .degrees(150 + sweep), clockwise: false)
            ctx.stroke(edge, with: .conicGradient(
                Gradient(stops: gradient.stops.map { .init(color: $0.color, location: $0.location * sweep / 360) }),
                center: c, angle: start), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            if let value {
                let t = min(max(value / 3, 0), 1)
                let a = (150 + sweep * t) * .pi / 180
                let outer = CGPoint(x: c.x + CGFloat(cos(a)) * (r + 7), y: c.y + CGFloat(sin(a)) * (r + 7))
                let inner = CGPoint(x: c.x + CGFloat(cos(a)) * (r - 28), y: c.y + CGFloat(sin(a)) * (r - 28))
                var needle = Path()
                needle.move(to: outer)
                needle.addLine(to: inner)
                ctx.stroke(needle, with: .linearGradient(Gradient(colors: [.white, .white.opacity(0)]),
                                                         startPoint: outer, endPoint: inner),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Day chart

/// The day's stress line on a 0–3 grid: coloured by level, broken where an hour has no reading,
/// active hours shaded with a runner above, a dashed now-line, and press-and-drag scrubbing that
/// drives the gauge.
private struct BroopHealthStressDayChart: View {
    let hours: [DaytimeStress.HourPoint]
    @Binding var scrub: DaytimeStress.HourPoint?

    var body: some View {
        GeometryReader { geo in
            let labelW: CGFloat = 30
            let plotW = geo.size.width - labelW
            let plotH = geo.size.height - 26
            let n = max(hours.count - 1, 1)
            let x: (Int) -> CGFloat = { labelW + plotW * CGFloat($0) / CGFloat(n) }
            let y: (Double) -> CGFloat = { plotH - plotH * CGFloat(min(max($0 / 3, 0), 1)) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Grid + labels.
                    for lvl in [0.0, 1, 2, 3] {
                        var g = Path()
                        g.move(to: CGPoint(x: labelW, y: y(lvl)))
                        g.addLine(to: CGPoint(x: geo.size.width, y: y(lvl)))
                        ctx.stroke(g, with: .color(BroopHealthPalette.grid), lineWidth: 1)
                        ctx.draw(Text(verbatim: String(format: "%.1f", lvl)).font(BroopType.number(12))
                                    .foregroundColor(BroopPalette.textSecondary),
                                 at: CGPoint(x: 12, y: y(lvl)), anchor: .center)
                    }
                    // Activity shading.
                    for (i, h) in hours.enumerated() where h.maskedForActivity {
                        let w = plotW / CGFloat(max(hours.count, 1))
                        ctx.fill(Path(CGRect(x: x(i) - w / 2, y: y(3), width: w, height: plotH - y(3))),
                                 with: .color(.white.opacity(0.05)))
                    }
                    // Runs.
                    let ramp = Gradient(colors: [BroopHealthPalette.stressHigh, BroopHealthPalette.stressMedium, BroopHealthPalette.stressLow])
                    var run = Path(); var open = false
                    func flush() {
                        if open {
                            ctx.stroke(run, with: .linearGradient(ramp, startPoint: CGPoint(x: 0, y: y(3)), endPoint: CGPoint(x: 0, y: y(0))),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                        run = Path(); open = false
                    }
                    for (i, h) in hours.enumerated() {
                        guard let lvl = h.level else { flush(); continue }
                        let p = CGPoint(x: x(i), y: y(lvl))
                        if open { run.addLine(to: p) } else {
                            run.move(to: p); run.addLine(to: CGPoint(x: p.x + 0.5, y: p.y)); open = true
                        }
                    }
                    flush()
                    // Now line.
                    var now = Path()
                    now.move(to: CGPoint(x: geo.size.width - 1, y: 0))
                    now.addLine(to: CGPoint(x: geo.size.width - 1, y: plotH))
                    ctx.stroke(now, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if let scrub, let i = hours.firstIndex(of: scrub), let lvl = scrub.level {
                        var s = Path()
                        s.move(to: CGPoint(x: x(i), y: 0)); s.addLine(to: CGPoint(x: x(i), y: plotH))
                        ctx.stroke(s, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ctx.fill(Path(ellipseIn: CGRect(x: x(i) - 5, y: y(lvl) - 5, width: 10, height: 10)),
                                 with: .color(BroopHealthPalette.stress(lvl)))
                    }
                }
                // Activity icons.
                ForEach(Array(activityStarts.enumerated()), id: \.offset) { _, i in
                    Image(systemName: "figure.run")
                        .font(.system(size: 12))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .position(x: x(i), y: -10)
                }
                // Time ticks.
                HStack {
                    ForEach(tickIndices, id: \.self) { i in
                        Text(verbatim: timeLabel(hours[i]))
                            .font(i == hours.count - 1 ? BroopType.demi(12.5) : BroopType.medium(12.5))
                            .foregroundStyle(i == hours.count - 1 ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                        if i != tickIndices.last { Spacer() }
                    }
                }
                .padding(.leading, labelW - 12)
                .offset(y: plotH + 8)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let t = (g.location.x - labelW) / plotW
                    let i = min(max(Int((t * CGFloat(n)).rounded()), 0), hours.count - 1)
                    let h = hours[i]
                    scrub = h.level == nil ? nil : h
                }
                .onEnded { _ in scrub = nil })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stress through the day"))
    }

    private var activityStarts: [Int] {
        hours.indices.filter { hours[$0].maskedForActivity && ($0 == 0 || !hours[$0 - 1].maskedForActivity) }
    }

    private var tickIndices: [Int] {
        guard hours.count > 1 else { return hours.indices.map { $0 } }
        let last = hours.count - 1
        return [0, last / 3, 2 * last / 3, last]
    }

    private func timeLabel(_ h: DaytimeStress.HourPoint) -> String {
        Date(timeIntervalSince1970: TimeInterval(h.startTs)).formatted(date: .omitted, time: .shortened)
    }
}
#endif
