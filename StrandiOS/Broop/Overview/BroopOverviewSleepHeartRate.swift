#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics

struct BroopOverviewSleepHeartRateCards: View {
    let day: String
    @EnvironmentObject private var repo: Repository
    @AppStorage("broop.sleep.preSleepHeartRate") private var enabled = false
    @State private var nights: [SleepHeartRateNight] = []
    @State private var showMethod = false
    @State private var trendDays = 14

    var body: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            if let latest = nights.first(where: { $0.day == day }) {
                if let feedback = latest.preSleep, let observation = feedback.observation, let comparison = feedback.comparison {
                    BroopCard {
                        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                            BroopSectionTitle(String(localized: "Pre-sleep heart rate"))
                            Text(String(localized: "\(Int(observation.meanBpm.rounded())) bpm before sleep"))
                                .font(BroopType.number(BroopType.sectionSize)).foregroundStyle(BroopPalette.textPrimary)
                            Text(String(localized: "\(String(format: "%+.1f", comparison.deltaBpm)) bpm versus your prior nights. One night cannot explain why."))
                                .font(BroopType.regular(BroopMetrics.page)).foregroundStyle(BroopPalette.textBody)
                            if !feedback.uncertainty.isEmpty {
                                BroopFootnote(text: String(localized: "Your personal comparison is still building."))
                            }
                            trend(preSleep: true)
                        }
                    }
                }
                if let contrast = latest.contrast {
                    BroopCard {
                        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                            BroopSectionTitle(String(localized: "Sleep heart-rate dip"))
                            Text(String(localized: "\(String(format: "%.1f", contrast.sleepReductionPercent))% sleep reduction"))
                                .font(BroopType.number(BroopType.sectionSize)).foregroundStyle(BroopPalette.textPrimary)
                            Text(contrast.sleepReductionPercent >= 0
                                 ? String(localized: "Your mean heart rate was lower during the primary sleep window than during the preceding waking interval.")
                                 : String(localized: "Your mean heart rate was higher during the primary sleep window than during the preceding waking interval."))
                                .font(BroopType.regular(BroopMetrics.page)).foregroundStyle(BroopPalette.textBody)
                            Text(String(localized: "Wake \(Int(contrast.wakeMeanBpm.rounded())) bpm · sleep \(Int(contrast.sleepMeanBpm.rounded())) bpm"))
                                .font(BroopType.medium(BroopMetrics.tileRadius)).foregroundStyle(BroopPalette.textSecondary)
                            Text(String(localized: "Observed epochs: wake \(Int((contrast.wakeCoverage * 100).rounded()))% · sleep \(Int((contrast.sleepCoverage * 100).rounded()))%"))
                                .font(BroopType.regular(BroopMetrics.tileRadius)).foregroundStyle(BroopPalette.textSecondary)
                            trend(preSleep: false)
                        }
                    }
                }
                if latest.contrast != nil || latest.preSleep?.comparison != nil {
                    Picker(String(localized: "Trend window"), selection: $trendDays) {
                        Text(String(localized: "14 days")).tag(14)
                        Text(String(localized: "30 days")).tag(30)
                    }
                    .pickerStyle(.segmented)
                    Button(String(localized: "How sleep heart-rate readings work")) { showMethod = true }
                        .frame(minHeight: BroopMetrics.navHeight)
                }
            }
        }
        .task(id: "\(repo.refreshSeq)|\(day)|\(enabled)") {
            nights = []
            let result = await repo.sleepHeartRateHistory(through: day, preSleepEnabled: enabled)
            guard !Task.isCancelled else { return }
            nights = result
        }
        .sheet(isPresented: $showMethod) {
            NavigationStack {
                ScrollView {
                    BroopFootnote(text: String(localized: "Pre-sleep HR is the mean of valid samples in the 30 minutes before primary sleep, compared with prior observed nights. It needs at least 10 samples and a usable personal baseline. Turn it on in Settings → Sleep. Sleep dip compares full five-minute HR epochs in primary sleep with the preceding waking interval, excluding recorded naps. Each side needs 30 observed epochs. Missing epochs stay missing; percentages describe epoch availability, not continuous sensor coverage. The sleep window includes in-bed wake. These are descriptive trends, not another resting HR, a diagnosis or a causal explanation. Missing or stale data produces no card."))
                        .padding(BroopMetrics.page)
                }
                .broopScreenChrome(String(localized: "Sleep heart rate"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { showMethod = false } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func trend(preSleep: Bool) -> some View {
        let end = VitalityEngine.epochDay(day) ?? 0
        return Chart {
            ForEach(nights) { night in
                if let ordinal = VitalityEngine.epochDay(night.day), ordinal > end - trendDays {
                    let value = preSleep ? night.preSleep?.observation?.meanBpm : night.contrast?.sleepReductionPercent
                    if let value {
                        PointMark(x: .value(String(localized: "Day"), night.day),
                                  y: .value(preSleep ? String(localized: "bpm") : String(localized: "%"), value))
                            .foregroundStyle(BroopPalette.rest)
                    }
                }
            }
        }
        .frame(height: BroopMetrics.tabBarClearance)
        .chartXAxis(.hidden)
        .accessibilityLabel(preSleep ? String(localized: "Pre-sleep heart-rate trend") : String(localized: "Sleep heart-rate dip trend"))
    }
}

struct BroopAccountSleepPage: View {
    @AppStorage("broop.sleep.preSleepHeartRate") private var enabled = false
    var body: some View {
        BroopAccountPage {
            BroopAccountSection(title: String(localized: "Sleep")) {
                BroopAccountGroup {
                    BroopAccountToggle(title: String(localized: "Pre-sleep heart rate"),
                                       detail: String(localized: "Compare the 30 minutes before sleep with your prior nights. Descriptive only; no score or advice changes."),
                                       isOn: $enabled)
                }
            }
        }
        .broopAccountChrome(String(localized: "Sleep"))
    }
}
#endif
