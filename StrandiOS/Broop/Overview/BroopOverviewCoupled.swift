#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// The coupled one-glance day read (classic `CoupledView`) in Broop form: today's Recovery ring with the
/// readiness word, Day Strain on the 0–21 axis with its optimal band, calories and workouts, and last
/// night's sleep performance with slept vs needed. Every value is resolved exactly as `CoupledView`
/// resolves it (same helpers, same carry and calibration rules), so the two never disagree.
struct BroopOverviewCoupledScreen: View {
    @EnvironmentObject private var repo: Repository
    @State private var habitual: Int?
    @State private var showBreakdown = false

    private var day: DailyMetric? { repo.today }
    private var todayKey: String { day?.day ?? Repository.logicalDayKey(Date()) }

    private var calibrationNights: Int? {
        RecoveryScorer.calibrationNights(nightlyHrv: repo.days.map(\.avgHrv), dayKeys: repo.days.map(\.day),
                                         hasRecovery: day?.recovery != nil)
    }

    private var carried: DailyMetric? {
        TodayView.lastScoredRecoveryDay(days: repo.days, selectedDayKey: todayKey, isToday: true,
                                        todayScored: day?.recovery != nil, isCalibrating: calibrationNights != nil)
    }

    private var recovery: Double? { day?.recovery ?? carried?.recovery }
    private var isCarrying: Bool { day?.recovery == nil && carried?.recovery != nil }
    private var strain21: Double? { day?.strain.map { UnitFormatter.effortValue($0, scale: .whoop) } }

    private var sleepPerformance: Double? {
        guard let d = day else { return nil }
        return repo.importedSleep[d.day]?.performancePct ?? AnalyticsEngine.Rest.composite(daily: d)
    }

    private var readiness: ReadinessEngine.Level {
        let anchor = (isCarrying ? carried?.day : day?.day) ?? Repository.logicalDayKey(Date())
        return ReadinessEngine.evaluate(days: repo.days, today: anchor).level
    }

    /// Imported need for the day, else the ≥ 7.5 h personal mean (the Coupled rule).
    private var sleepNeed: Double {
        if let need = day.flatMap({ repo.importedSleep[$0.day]?.needMin }), need > 0 { return need }
        let banked = repo.days.compactMap(\.totalSleepMin).filter { $0 > 0 }
        return max(450, banked.isEmpty ? 450 : banked.reduce(0, +) / Double(banked.count))
    }

    private var bedWake: String? {
        let start = Int(Calendar.current.startOfDay(for: Repository.logicalDay(Date())).timeIntervalSince1970)
        guard let span = SleepView.mainNightSpan(repo.sleeps.filter { $0.endTs > start }, habitualMidsleepSec: habitual)
        else { return nil }
        return "\(Night.clockString(span.start)) – \(Night.clockString(span.end))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { showBreakdown = true } label: { recoveryHero }
                    .buttonStyle(BroopPressableStyle())
                    .padding(.top, 20)

                strainCard.padding(.top, 26)
                NavigationLink(value: BroopScreen.sleep) { sleepCard }
                    .buttonStyle(BroopPressableStyle())
                    .padding(.top, 12)

                Text("A classic one-glance read of NOOP's own scores. Same data, different lens.")
                    .font(BroopType.medium(12.5))
                    .foregroundStyle(BroopPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopOverviewNavBar(title: String(localized: "Today"))
        }
        .background(BroopBackground())
        .broopBarChrome()
        .task(id: repo.refreshSeq) { habitual = await repo.habitualMidsleepSec() }
        .sheet(isPresented: $showBreakdown) {
            BroopOverviewCoupledBreakdown(row: day?.recovery != nil ? day : carried,
                                          sleepPerf: sleepPerformance,
                                          calibrationNights: calibrationNights,
                                          onClose: { showBreakdown = false })
        }
    }

    private var recoveryHero: some View {
        VStack(spacing: 12) {
            BroopOverviewHeroRing(fraction: recovery.map { $0 / 100 },
                                  color: recovery.map(BroopPalette.band) ?? BroopPalette.textSecondary,
                                  valueText: recovery.map { BroopFormat.whole($0) }, unit: "%",
                                  label: [String(localized: "Recovery")], diameter: 220, lineWidth: 11)
                .opacity(isCarrying ? 0.85 : 1)
            if let word = TodayView.readinessWord(readiness) {
                BroopCaps(word, size: 11, color: tint)
                    .padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule().fill(tint.opacity(0.14)))
            }
            if isCarrying, let prior = carried {
                Text(verbatim: TodayView.carriedCaption(priorDayKey: prior.day, todayKey: todayKey))
                    .font(BroopType.medium(12.5)).foregroundStyle(BroopPalette.textSecondary)
            } else if recovery == nil, let banked = calibrationNights {
                Text(verbatim: ChargeBreakdownFormat.calibrationProgress(banked: banked, seed: Baselines.minNightsSeed))
                    .font(BroopType.medium(12.5)).foregroundStyle(BroopPalette.textSecondary)
            }
            HStack(spacing: 6) {
                BroopCaps(String(localized: "What shaped it"), size: 10, color: BroopPalette.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tint: Color {
        switch readiness {
        case .primed: return BroopOverviewPalette.optimal
        case .balanced: return BroopPalette.teal
        case .strained: return BroopPalette.warning
        case .rundown: return BroopPalette.bandLow
        case .insufficient: return BroopPalette.textSecondary
        }
    }

    private var strainCard: some View {
        let band = CoupledView.optimalStrainRange(recovery: recovery)
        return BroopOverviewCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BroopCaps(String(localized: "Day Strain"), size: 11.5)
                    Spacer()
                    if let s = strain21 {
                        BroopCaps(s < 6 ? String(localized: "Light") : (s < 10 ? String(localized: "Moderate")
                                  : (s < 14 ? String(localized: "Strenuous") : String(localized: "High"))),
                                  size: 10.5, color: BroopPalette.effort)
                    }
                }
                HStack(spacing: 18) {
                    BroopOverviewDial(fraction: strain21.map { $0 / 21 }, color: BroopPalette.effort,
                                      valueText: strain21.map(BroopFormat.one),
                                      band: band.map { (Double($0.lowerBound) / 21)...(Double($0.upperBound) / 21) },
                                      tick: band.map { Double($0.lowerBound + $0.upperBound) / 42 },
                                      diameter: 104, lineWidth: 7)
                    VStack(alignment: .leading, spacing: 12) {
                        stat(String(localized: "Optimal"), CoupledView.optimalStrainRangeText(recovery: recovery),
                             recovery.map(BroopPalette.band) ?? BroopPalette.textSecondary)
                        stat(String(localized: "Calories"), day?.activeKcalEst.map { "\(Int($0.rounded())) kcal" } ?? "—",
                             BroopPalette.textPrimary)
                        stat(String(localized: "Workouts"), "\(day?.exerciseCount ?? 0)", BroopPalette.textPrimary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var sleepCard: some View {
        BroopOverviewCard {
            HStack(spacing: 18) {
                BroopOverviewDial(fraction: sleepPerformance.map { $0 / 100 }, color: BroopPalette.rest,
                                  valueText: sleepPerformance.map { BroopFormat.whole($0) }, unit: "%",
                                  diameter: 76, lineWidth: 5.3)
                VStack(alignment: .leading, spacing: 5) {
                    BroopCaps(String(localized: "Sleep Performance"), size: 11)
                    if let asleep = day?.totalSleepMin, asleep > 0 {
                        Text(verbatim: String(localized: "\(BroopFormat.duration(asleep)) slept of \(BroopFormat.duration(sleepNeed)) needed"))
                            .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                    } else {
                        Text("No sleep tracked last night").font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    if let bedWake {
                        Text(verbatim: bedWake).font(BroopType.demi(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(19)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// "What shaped your Charge" for the coupled read: the shared breakdown components over the displayed
/// row, the calibrating countdown while the baseline seeds, and the method link.
private struct BroopOverviewCoupledBreakdown: View {
    @EnvironmentObject private var repo: Repository
    let row: DailyMetric?
    let sleepPerf: Double?
    let calibrationNights: Int?
    let onClose: () -> Void
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let row, let b = ChargeBreakdownWiring.breakdown(days: repo.days, row: row, sleepPerfPercent: sleepPerf,
                                                                          hrvBaselineEpoch: Baselines.hrvBaselineEpoch()),
                       !b.drivers.isEmpty {
                        BroopOverviewCard {
                            BroopFinalAChargeBreakdown(drivers: b.drivers, confidence: b.confidence,
                                                   skinTempRel: RecoveryScorer.skinTempRelative(deviationC: row.skinTempDevC))
                        }
                    } else if let banked = calibrationNights {
                        BroopOverviewCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: ChargeBreakdownFormat.calibrationCountdown(nightsRemaining: max(1, Baselines.minNightsSeed - banked)))
                                    .font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                                Text(verbatim: ChargeBreakdownFormat.calibrationUnlockCopy(scoreName: String(localized: "Charge")))
                                    .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                                Text(verbatim: ChargeBreakdownFormat.calibrationProgress(banked: banked, seed: Baselines.minNightsSeed))
                                    .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                            }
                        }
                    } else {
                        BroopOverviewCard {
                            Text("No Charge breakdown yet. Wear the strap overnight to score a night first.")
                                .font(BroopType.medium(15)).foregroundStyle(BroopPalette.textBody)
                        }
                    }
                    Button { showGuide = true } label: {
                        BroopNavTile(symbol: "function", title: String(localized: "How Charge is calculated"))
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .broopSheetBar(String(localized: "What shaped your Charge"), onDone: onClose)
            .sheet(isPresented: $showGuide) {
                BroopOverviewScoreGuide(initialSection: .charge, onClose: { showGuide = false })
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
