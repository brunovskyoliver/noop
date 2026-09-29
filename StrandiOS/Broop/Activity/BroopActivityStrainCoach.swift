#if os(iOS)
import SwiftUI
import StrandAnalytics
import WhoopStore

/// Live Strain Coach for a running workout: the day's Effort so far including this workout, today's target
/// band (`StrainTargetContext.band`, the resolver Home and the notifier read), a zone label and how long at
/// the current heart rate it takes to reach the band.
///
/// Day Effort = the day's heart rate scored up to the workout's start (with the same window, HRmax and resting
/// HR as Home's live day ring) plus this workout's TRIMP. Edwards TRIMP is a sum over samples, so adding the
/// two TRIMPs and mapping back through the scorer does not count anything twice. The stored day row floors
/// that TOTAL, not the pre-workout part: a pass that runs mid-workout writes the workout's own heart rate into
/// the row, and flooring the pre-workout part with it would add the workout a second time.
/// Minutes use the inverted scorer (`StrainTarget.minutesToReach`) and only apply to the Edwards method.
///
/// A leaf view: it owns its `AppModel` observation so the heart-rate publishes stay here.
struct BroopActivityStrainCoach: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var context = StrainTargetContext.shared
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    /// The day's Effort before this workout started, keyed by the workout's start.
    @State private var before: (start: Date, effort: Double)?

    var body: some View {
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        let maxValue = scale == .whoop ? 21.0 : 100.0
        let workout = model.activeWorkout
        let band = context.band(charge: repo.today?.recovery, isToday: true)
        let dayEffort: Double? = workout.flatMap { w in
            guard let b = before, b.start == w.start else { return nil }
            let live = StrainScorer.trimpToStrain(StrainScorer.strainToTrimp(b.effort) + StrainScorer.strainToTrimp(w.liveStrain))
            return StrainScorer.effectiveEffort(live: live, stored: repo.today?.strain)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopCaps(String(localized: "Strain Coach"), size: 11.5)
                Spacer()
                if let band, let dayEffort {
                    BroopCaps(zoneLabel(band.zone(effort: dayEffort)), size: 10.5, color: zoneColor(band.zone(effort: dayEffort)))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: dayEffort.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–")
                    .font(BroopType.number(30)).foregroundStyle(BroopPalette.textPrimary)
                    .contentTransition(.numericText())
                Text("day Effort").font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                Spacer()
                if let band {
                    Text(verbatim: String(localized: "Target \(UnitFormatter.effortDisplay(band.lower, scale: scale))–\(UnitFormatter.effortDisplay(band.upper, scale: scale))"))
                        .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textBody)
                }
            }
            gauge(band: band, effort: dayEffort)
            Text(verbatim: message(band: band, dayEffort: dayEffort, scale: scale, maxValue: maxValue))
                .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        .task(id: "\(workout?.start.timeIntervalSince1970 ?? 0)|\(repo.refreshSeq)") { await loadBefore(workout?.start) }
    }

    /// Track 0…100 with the band shaded and a marker at the day's Effort (fractions are scale-free).
    private func gauge(band: StrainTarget.Band?, effort: Double?) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track).frame(height: 8)
                if let band {
                    Capsule().fill(BroopPalette.effort.opacity(0.45))
                        .frame(width: max(4, w * (band.upper - band.lower) / StrainScorer.maxStrain), height: 8)
                        .offset(x: w * band.lower / StrainScorer.maxStrain)
                }
                if let effort {
                    Capsule().fill(BroopPalette.textPrimary)
                        .frame(width: 3, height: 18)
                        .offset(x: min(w - 3, max(0, w * effort / StrainScorer.maxStrain - 1.5)))
                        .animation(.easeOut(duration: 0.4), value: effort)
                }
            }
            .frame(height: 18)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func message(band: StrainTarget.Band?, dayEffort: Double?, scale: EffortScale, maxValue: Double) -> String {
        guard let band else { return String(localized: "Your target appears once today's Charge is calculated.") }
        guard let dayEffort else { return String(localized: "Working out today's Effort so far…") }
        switch band.zone(effort: dayEffort) {
        case .optimal: return String(localized: "Target reached.")
        case .overreaching: return String(localized: "Above target: consider easing off.")
        case .restoring:
            guard PuffinExperiment.effortMethod == .edwards else {
                return String(localized: "Below today's target.")
            }
            let rest = model.workoutRestingHR, maxHR = model.effortMaxHR
            let rate = model.bpm.map { StrainTarget.edwardsTrimpPerMinute(bpm: Double($0), restingHR: rest, maxHR: maxHR) } ?? 0
            if rate > 0, let m = StrainTarget.minutesToReach(targetEffort: band.lower, currentEffort: dayEffort, trimpPerMinute: rate) {
                return String(localized: "~\(Int(m.rounded(.up))) min at this pace to reach your target.")
            }
            // Below zone 1 nothing accrues; say what zone 2 would take instead of promising nothing.
            if let m = StrainTarget.minutesToReach(targetEffort: band.lower, currentEffort: dayEffort, trimpPerMinute: 2) {
                return String(localized: "This pace is below zone 1. ~\(Int(m.rounded(.up))) min in zone 2 would reach your target.")
            }
            return String(localized: "Below today's target.")
        }
    }

    private func zoneLabel(_ z: StrainTarget.Zone) -> String {
        switch z {
        case .restoring: return String(localized: "Restoring")
        case .optimal: return String(localized: "Optimal")
        case .overreaching: return String(localized: "Overreaching")
        }
    }

    private func zoneColor(_ z: StrainTarget.Zone) -> Color {
        switch z {
        case .restoring: return BroopPalette.textSecondary
        case .optimal: return BroopPalette.effort
        case .overreaching: return BroopPalette.warning
        }
    }

    /// Score the day's heart rate from the day's start (the day-cycle rule Home uses) to the workout start.
    private func loadBefore(_ start: Date?) async {
        guard let start else { before = nil; return }
        let cal = Calendar.current
        let logical = Repository.logicalDay(start)
        let key = Repository.localDayKey(logical)
        let calendarFrom = Int(cal.startOfDay(for: logical).timeIntervalSince1970)
        let mode = DayCycleMode.persisted(UserDefaults.standard.string(forKey: DayCycleMode.storageKey)
                                          ?? DayCycleMode.sleepOnset.rawValue)
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: "my-whoop") : []
        let from = markers.last(where: { $0.day == key }).map { Int($0.value) } ?? calendarFrom
        let to = Int(start.timeIntervalSince1970) - 1
        let hr = to > from ? await repo.hrSamples(from: from, to: to, limit: 200_000) : []
        guard !Task.isCancelled else { return }
        let maxHR = model.effortMaxHR, rest = model.workoutRestingHR
        let method = PuffinExperiment.effortMethod, sex = model.profile.sex
        let live = await CancellableAnalysis.run {
            StrainScorer.strain(hr, maxHR: maxHR, restingHR: rest, method: method, sex: sex)
        }
        guard !Task.isCancelled else { return }
        // Raw heart rate only. The stored-row floor is applied to the day total in `body`, since the row
        // can already contain this workout.
        before = (start, live ?? 0)
    }
}
#endif
