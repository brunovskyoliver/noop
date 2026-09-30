import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Today's Apple Intelligence brief: a headline and two or three points, each a metric id plus one sentence.
/// The card shows each metric's value from the app's resolvers beside the model's sentence, so a number on
/// the card can never come from the model. Stored in UserDefaults like the Coach's other settings.
struct AppleCoachBrief: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        /// `CoachMetric.rawValue`.
        let metric: String
        let sentence: String
    }

    let day: String
    /// The data the brief was written from; a change means new data (see `AppleCoachBriefPolicy`).
    let dataKey: String
    let headline: String
    let points: [Point]
    let offDevice: Bool
    /// The model's prose failed the number check twice: show the values alone.
    let factsOnly: Bool

    static let storageKey = "coach.appleBrief.v1"

    static func load(_ defaults: UserDefaults = .standard) -> AppleCoachBrief? {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(AppleCoachBrief.self, from: $0) }
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    /// The brief as plain text for the morning-brief notification and widget, values from `value`.
    func plainText(value: (CoachMetric) -> String?) -> String {
        var lines = [headline]
        for p in points {
            guard let m = CoachMetric(rawValue: p.metric) else { continue }
            let v = value(m).map { " " + $0 } ?? ""
            lines.append("• \(m.label)\(v)" + (p.sentence.isEmpty ? "" : ": " + p.sentence))
        }
        return lines.joined(separator: "\n")
    }
}

/// When to write a new brief: once per local day, and again that day only after new data. Generated when
/// the app comes to the foreground (background generation is rate-limited). Pure; unit-tested.
enum AppleCoachBriefPolicy {
    static func shouldGenerate(stored: AppleCoachBrief?, today: String, dataKey: String) -> Bool {
        guard let stored else { return true }
        return stored.day != today || stored.dataKey != dataKey
    }

    /// The facts-only brief: no prose, every metric the facts cover.
    static func factsOnly(day: String, dataKey: String, metrics: [CoachMetric], offDevice: Bool) -> AppleCoachBrief {
        AppleCoachBrief(day: day, dataKey: dataKey, headline: String(localized: "Today's numbers"),
                        points: metrics.map { .init(metric: $0.rawValue, sentence: "") }, offDevice: offDevice, factsOnly: true)
    }
}

#if canImport(FoundationModels)
/// What the model writes: no numbers, only which metrics matter and a sentence about each.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachBriefDraft {
    @Guide(description: "A short, warm headline for today. No numbers.")
    var headline: String
    @Guide(description: "The two or three metrics that matter most today", .minimumCount(2), .maximumCount(3))
    var points: [CoachBriefDraftPoint]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct CoachBriefDraftPoint {
    @Guide(description: "Which metric")
    var metric: CoachMetricChoice
    @Guide(description: "One short sentence of advice about this metric today. No numbers.")
    var sentence: String
}
#endif
