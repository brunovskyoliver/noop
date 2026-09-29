#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Health

/// The Broop Health tab, laid out like WHOOP's: the live heart-rate hero, then Healthspan, Health
/// Monitor and Stress Monitor cards, then the other body screens NOOP has data for (HRV status, fitness,
/// cycle, body, trends, records). Every card opens its Broop screen.
///
/// The vitals come from `BroopHealthVitalSet` (the same resolver and inputs as Home and the classic
/// Health screen) and the stress figure from `StressModel` over the same inputs `BroopStore` uses, so the
/// Home tiles and these cards can never disagree.
struct BroopHealthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(PuffinExperiment.spo2CandidateDisplayKey) private var spo2CandidateOn = false
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleEnabled = false

    @State private var vitals = BroopHealthVitalSet()
    @State private var vitalsLoaded = false
    @State private var healthspan = BroopHealthspanData()
    @State private var weight: (value: Double, day: String)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                BroopPageHeader(text: String(localized: "Health"))
                BroopHealthLiveHeartRate()
                    .padding(.horizontal, -BroopMetrics.page)
                    .padding(.top, 8)
                VStack(spacing: 14) {
                    NavigationLink(value: BroopScreen.healthspan) { healthspanCard }
                    NavigationLink(value: BroopScreen.health) { monitorCard }
                    NavigationLink(value: BroopScreen.stress) { stressCard }
                    NavigationLink(value: BroopScreen.mind) { BroopMindCard() }
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 18)

                BroopHealthHeading(text: String(localized: "Heart & Fitness")).padding(.top, BroopMetrics.section)
                VStack(spacing: 12) {
                    BroopHealthHRVStatusCard(showsLink: true)
                    NavigationLink(value: BroopScreen.healthspan) { fitnessCard }
                        .buttonStyle(BroopPressableStyle())
                }
                .padding(.top, 12)

                if cycleEnabled {
                    // AppModel republishes about once a second; only this leaf observes it.
                    BroopHealthCycleEntry().padding(.top, 12)
                }

                BroopHealthHeading(text: String(localized: "Body")).padding(.top, BroopMetrics.section)
                VStack(spacing: 10) {
                    NavigationLink(value: BroopScreen.metric(key: "weight", source: "apple-health")) {
                        BroopHealthDashboardRow(symbol: "scalemass", title: String(localized: "Weight"),
                                                value: weight.map { UnitFormatter.massFromKilograms($0.value, system: unitSystem) },
                                                baseline: weight.map { BroopHealthFormat.shortDay($0.day) },
                                                direction: 0, good: nil)
                    }
                    NavigationLink(value: BroopScreen.labBook) {
                        BroopHealthRow(symbol: "books.vertical", title: String(localized: "Lab Book"),
                                       detail: String(localized: "Bloods, blood pressure and body numbers"))
                    }
                    NavigationLink(value: BroopScreen.hydration) {
                        BroopHealthRow(symbol: "drop", title: String(localized: "Hydration"))
                    }
                    NavigationLink(value: BroopScreen.rhythm) {
                        BroopHealthRow(symbol: "waveform.path", title: String(localized: "Rhythm"),
                                       detail: String(localized: "Beat-to-beat regularity, experimental"))
                    }
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 12)

                BroopHealthHeading(text: String(localized: "Trends")).padding(.top, BroopMetrics.section)
                VStack(spacing: 10) {
                    NavigationLink(value: BroopScreen.trends) {
                        BroopHealthRow(symbol: "chart.xyaxis.line", title: String(localized: "My Dashboard"),
                                       detail: String(localized: "Every metric over weeks and months"))
                    }
                    NavigationLink(value: BroopScreen.metricExplorer) {
                        BroopHealthRow(symbol: "waveform.path.ecg", title: String(localized: "Metric Explorer"))
                    }
                    NavigationLink(value: BroopScreen.compare) {
                        BroopHealthRow(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "Compare"))
                    }
                    NavigationLink(value: BroopScreen.fusedRecord) {
                        BroopHealthRow(symbol: "square.stack.3d.up", title: String(localized: "Your Data, Fused"))
                    }
                }
                .buttonStyle(BroopPressableStyle())
                .padding(.top, 12)

                BroopHairline().padding(.top, BroopMetrics.section)
                BroopHealthFootnote(text: String(localized: "Health Monitor and Stress Monitor are not medical devices and cannot diagnose or manage medical conditions. They do not provide medical advice. Always consult your doctor for health concerns and never delay or modify medical care based on these features."))
                    .padding(.top, 16)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
        .task(id: "\(repo.refreshSeq)|\(spo2CandidateOn)") { await load() }
    }

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
    }

    private func load() async {
        vitals = await BroopHealthVitalSet.load(repo: repo)
        vitalsLoaded = true

        healthspan = await BroopHealthspanData.load(repo: repo, profile: profile)
        weight = (await repo.exploreSeries(key: "weight", source: "apple-health")).last.map { ($0.value, $0.day) }
    }

    // MARK: Healthspan

    private var healthspanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopHealthCardTitle(title: String(localized: "Healthspan"))
            if let age = healthspan.bodyAge {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: BroopFormat.one(age))
                            .font(BroopType.number(40)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(40)
                        BroopCaps(String(localized: "Broop Age"), size: 10.5, color: BroopPalette.textSecondary)
                    }
                    Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        if let delta = healthspan.bodyAgeDelta(age: profile.age) {
                            Text(verbatim: BroopHealthspanData.yearsLine(delta))
                                .font(BroopType.demi(16))
                                .foregroundStyle(delta >= 0 ? BroopHealthPalette.mint : BroopHealthPalette.amber)
                        }
                        Text(verbatim: healthspan.pace.map { "\(BroopFormat.one($0))x " + String(localized: "pace of aging") }
                             ?? String(localized: "Updated every Sunday"))
                            .font(BroopType.medium(13.5))
                            .foregroundStyle(BroopPalette.textBody)
                    }
                    Spacer(minLength: 0)
                }
                BroopHealthPaceRuler(pace: healthspan.pace).frame(height: 16)
            } else {
                Text(healthspan.loaded
                     ? String(localized: "Keep wearing your strap. Log 21 recoveries in a month (\(healthspan.snap.recoveriesLast31) so far) to unlock your Broop Age and Pace of Aging.")
                     : String(localized: "Reading your Healthspan…"))
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    // MARK: Health Monitor

    private var monitorCard: some View {
        let core = vitals.core
        let withData = vitals.withData
        let outliers = vitals.outliers
        return VStack(alignment: .leading, spacing: 18) {
            BroopHealthCardTitle(title: String(localized: "Health Monitor"))
            HStack(spacing: 0) {
                ForEach(Array(core.enumerated()), id: \.element.id) { i, r in
                    VStack(spacing: 10) {
                        Image(systemName: r.broopSymbol)
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .frame(height: 24)
                        BroopCaps(r.broopShort, size: 11)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        BroopHealthStatusSquare(tone: r.broopTone, size: 22)
                    }
                    .frame(maxWidth: .infinity)
                    if i < core.count - 1 {
                        Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 74)
                    }
                }
            }
            HStack(spacing: 12) {
                BroopHealthStatusSquare(tone: withData.isEmpty ? .none : (outliers.isEmpty ? .good : .warn),
                                        size: 18, solid: !withData.isEmpty)
                Text(verbatim: summaryLine(withData: withData.count, outliers: outliers.count))
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopHealthPalette.innerPanel))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func summaryLine(withData: Int, outliers: Int) -> String {
        if !vitalsLoaded { return String(localized: "Reading your vitals…") }
        if withData == 0 { return String(localized: "Wear your strap overnight to see your vitals") }
        let inRange = withData - outliers
        return String(localized: "\(inRange)/\(withData) metrics within range")
    }

    // MARK: Stress Monitor

    private var stressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopHealthCardTitle(title: String(localized: "Stress Monitor"))
            BroopHealthStressCardBody()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    // MARK: Fitness

    private var fitnessCard: some View {
        HStack(spacing: 0) {
            fitnessColumn(title: String(localized: "VO₂ Max"),
                          value: healthspan.vo2max.map { String(format: "%.0f", $0) }, unit: "mL/kg/min")
            Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 54)
            fitnessColumn(title: String(localized: "Fitness Age"),
                          value: healthspan.fitnessAge.map { "\(fitnessAgeBoundSymbol($0))\(Int($0.rounded()))" },
                          unit: String(localized: "yrs"))
            Image(systemName: "chevron.right")
                .font(.system(size: 15))
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .padding(.vertical, 18)
        .padding(.leading, 4)
        .padding(.trailing, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func fitnessColumn(title: String, value: String?, unit: String) -> some View {
        VStack(spacing: 6) {
            BroopCaps(title, size: 10.5, color: BroopPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value ?? "--").font(BroopType.number(30)).foregroundStyle(BroopPalette.textPrimary)
                if value != nil {
                    Text(verbatim: unit).font(BroopType.regular(11.5)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The cycle-awareness row and its tracker sheet. The only part of the Health tab that reads `AppModel`,
/// so its once-a-second republish re-renders this row, not the tab.
private struct BroopHealthCycleEntry: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @State private var showTracker = false

    var body: some View {
        if let cycle = model.cyclePhase {
            Button { showTracker = true } label: { cycleCard(cycle) }
                .buttonStyle(BroopPressableStyle())
                .sheet(isPresented: $showTracker) {
                    if let cycle = model.cyclePhase {
                        BroopFinalACycleTracker(result: cycle, curve: model.cycleCurve)
                            .environmentObject(repo)
                            .environmentObject(model)
                    }
                }
        }
    }

    private func cycleCard(_ cycle: CyclePhaseEngine.Result) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color(broopHex: 0xB45CF0))
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(String(localized: "Cycle awareness"), size: 12)
                Text(String(localized: "From your nightly skin temperature"))
                    .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(BroopPalette.textPrimary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }
}

/// Band colours for the stress scale, shared by the Health tab and the Stress screen.
enum BroopHealthStressBand {
    static func color(_ band: StressBand) -> Color {
        switch band {
        case .low: return BroopHealthPalette.stressLow
        case .medium: return BroopHealthPalette.stressMedium
        case .high: return BroopHealthPalette.stressHigh
        }
    }
}

/// Tiny bar strip (last N values), each bar coloured by its value.
struct BroopHealthMiniBars: View {
    let values: [Double]
    let domain: ClosedRange<Double>
    let color: (Double) -> Color

    var body: some View {
        GeometryReader { geo in
            let n = max(values.count, 1)
            let gap: CGFloat = 3
            let w = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let t = (min(max(v, domain.lowerBound), domain.upperBound) - domain.lowerBound)
                        / (domain.upperBound - domain.lowerBound)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(v))
                        .frame(width: w, height: max(3, geo.size.height * CGFloat(t)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
#endif
