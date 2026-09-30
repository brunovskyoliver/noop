import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The evening review: in the evening the Home card looks back at today (Effort against its target, stress,
/// energy, the journal) and names one thing to do before bed. Stored as an `AppleCoachBrief` under its own
/// key, with the same rule as the morning brief: the model picks metrics and writes sentences, the card
/// shows the values from the app. Pure; unit-tested.
enum AppleCoachEveningPolicy {
    static let storageKey = "coach.appleEvening.v1"

    /// The evening starts at 17:00 and runs to midnight.
    static let startHour = 17

    static func isEvening(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= startHour
    }

    /// The journal day an evening's habits belong to: tomorrow. Journal answers are about the night and day
    /// leading into that morning (the WHOOP export's attribution), so tonight's wine or late coffee is
    /// logged against the morning it affects.
    static func journalDay(for now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: now) ?? now
    }

    /// Metrics for the values-only review when the wording fails the number check.
    static let factsOnlyMetrics: [CoachMetric] = [.effort, .stress, .sleepDebt]

    static let prompt = """
        Write this evening's review of today from these facts. Pick the two or three metrics that say most \
        about how today went, such as Effort against its target, stress, energy, steps or sleep debt. For \
        each, write one sentence on how today went. Then write one concrete thing to do this evening so \
        tonight's sleep goes well, following tonight's sleep plan. You may mention a journal answer from \
        today if it matters for tonight, such as late caffeine or alcohol. Do not write any numbers.
        """
}

/// When the evening-review reminder fires: an hour before tonight's wind-down reminder, kept between 19:00
/// and 22:30 of that evening so it neither lands in the afternoon nor after a normal bedtime. Pure.
enum EveningReviewTiming {
    static let leadMinutes = 60
    static let earliestMinute = 19 * 60
    static let latestMinute = 22 * 60 + 30

    static func reminderDate(windDownFire: Date, calendar: Calendar = .current) -> Date {
        let target = windDownFire.addingTimeInterval(-Double(leadMinutes) * 60)
        // A reminder after midnight belongs to the evening before.
        let evening = calendar.startOfDay(for: target.addingTimeInterval(-6 * 3600))
        let minute = calendar.dateComponents([.minute], from: evening, to: target).minute ?? latestMinute
        let clamped = min(max(minute, earliestMinute), latestMinute)
        return calendar.date(byAdding: .minute, value: clamped, to: evening) ?? target
    }

    /// The reminders to arm: one per coming evening from the wind-down fire dates, skipping any already
    /// past and tonight's when today's journal is already filled in.
    static func reminderDates(windDownFires: [Date], now: Date, skipTonight: Bool,
                              calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        for fire in windDownFires {
            let d = reminderDate(windDownFire: fire, calendar: calendar)
            guard d > now, !out.contains(where: { calendar.isDate($0, inSameDayAs: d) }) else { continue }
            if skipTonight && calendar.isDate(d, inSameDayAs: now) { continue }
            out.append(d)
        }
        return out.sorted()
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachEveningDraft {
    @Guide(description: "A short, warm headline about how today went. No numbers.")
    var headline: String
    @Guide(description: "The two or three metrics that say most about today", .minimumCount(2), .maximumCount(3))
    var points: [CoachEveningDraftPoint]
    @Guide(description: "One concrete thing to do this evening so tonight's sleep goes well. One sentence. No numbers.")
    var tonight: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachEveningDraftPoint {
    @Guide(description: "Which metric")
    var metric: CoachMetricChoice
    @Guide(description: "One short sentence on how today went for this metric. No numbers.")
    var sentence: String
}
#endif
