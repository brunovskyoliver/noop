#if os(iOS) && DEBUG
import SwiftUI
import StrandAnalytics

/// Screenshot entry points; all readouts load through the same production resolvers as their screens.
struct BroopWiringDemoHost: View {
    enum Kind { case jetLag, hrv, sleepHeart, bedtime }
    let kind: Kind
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @StateObject private var store = BroopStore()
    @State private var bedtimeValues = ""

    var body: some View {
        Group {
            switch kind {
            case .jetLag: BroopHealthJetLagView()
            case .hrv:
                ScrollView { BroopHealthHRVStatusCard().padding(BroopMetrics.page) }
                    .background(BroopBackground())
            case .sleepHeart:
                ScrollView {
                    BroopOverviewSleepHeartRateCards(day: repo.days.last?.day ?? Repository.dayString(Date()))
                        .padding(BroopMetrics.page)
                }
                .background(BroopBackground())
            case .bedtime:
                ScrollView {
                    VStack(alignment: .leading, spacing: BroopMetrics.page) {
                        BroopOverviewPlannerCard()
                        CaffeineLogCard()
                        if let night = store.snapshot?.night {
                            BroopFinalABodyClockSection(actualBedHour: SleepView.localClockHour(night.session.effectiveStartTs),
                                                       actualWakeHour: SleepView.localClockHour(night.session.endTs))
                        }
                        Text(verbatim: bedtimeValues).font(BroopType.regular(BroopMetrics.page))
                    }
                    .padding(BroopMetrics.page)
                }
                .background(BroopBackground())
            }
        }
        .environmentObject(store)
        .task(id: repo.refreshSeq) {
            guard !repo.days.isEmpty else { return }
            await model.refreshTonightPlan()
            await store.reload(repo: repo, profile: model.profile)
            if kind == .bedtime { UserDefaults.standard.set(true, forKey: CaffeineLogCard.cutoffEnabledKey) }
            if kind == .sleepHeart { UserDefaults.standard.set(true, forKey: "broop.sleep.preSleepHeartRate") }
            if kind == .jetLag, let sleep = model.tonightPlan,
               UserDefaults.standard.string(forKey: "broop.jetLag.activeTrip.v1") == nil {
                let trip = JetLagTrip(travelDate: Calendar.current.date(byAdding: .day, value: 7, to: Date())!,
                                      originTimeZone: TimeZone.current.identifier, destinationOffsetMinutes: 300,
                                      bedMinute: sleep.target.bedMinute, wakeMinute: sleep.wakeMinute)
                if let data = try? JSONEncoder().encode(trip), let value = String(data: data, encoding: .utf8) {
                    UserDefaults.standard.set(value, forKey: "broop.jetLag.activeTrip.v1")
                }
            }
            if kind == .bedtime, let plan = model.tonightPlan {
                let clock = BroopFinalABodyClockCard.clock
                let bed = clock(Double(plan.target.bedMinute) / 60)
                let wake = clock(Double(plan.wakeMinute) / 60)
                let nudge = clock(Double(WindDownNudge.nudgeMinuteOfDay()) / 60)
                let cut = clock(Double(CaffeineDecay.cutoffMinutesSinceMidnight(bedtimeMinutes: plan.target.bedMinute)) / 60)
                var values = "Shared plan: \(bed)–\(wake)\nWind-down reminder: \(nudge)\nCaffeine cutoff: \(cut)\n"
                if let phase = model.circadianPhase, phase.confidence != .unreadable,
                   let window = CircadianEngine.idealSleepWindow(tempMinHour: phase.tempMinHour,
                                                                 durationHours: (store.snapshot?.night.map { Double($0.session.endTs - $0.session.effectiveStartTs) / 3600 } ?? 0)) {
                    values += "Body-clock reference: \(clock(window.bedHour))–\(clock(window.wakeHour))"
                }
                bedtimeValues = values
                print("WIRING_DEMO_BEDTIMES \(values)")
            }
        }
    }
}
#endif
