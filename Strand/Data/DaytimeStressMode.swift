import Foundation
import StrandAnalytics

/// The lens for the macOS Stress screen. With the personal lens on it reads the stored 14-day calm floors,
/// the same values and the same median `StressMonitor` uses, so the two cannot disagree about the floor.
/// Those are a few indexed rows, so the 30-day raw HR fold and its in-memory cache are gone.
enum DaytimeStressMode {
    @MainActor
    static func selected(repo: Repository, startOfToday: Date,
                         calendar: Calendar = .current,
                         personalBaseline: Bool) async -> DaytimeStress.ScoringMode {
        guard personalBaseline else { return .dayRelative }
        let today = Repository.localDayKey(startOfToday)
        let from = Repository.stressDayKey(offset: -StressMonitor.baselineWindowDays, from: today) ?? today
        let stored = await repo.stressStoredValues(keys: [StressMonitor.wakeFloorKey], from: from, to: today)
        return StressMonitor.scoringMode(priorFloors: Repository.stressPriors(before: today, stored: stored).floors)
    }
}
