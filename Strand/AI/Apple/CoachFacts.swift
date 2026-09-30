import Foundation

// CoachFacts.swift — what the Apple Intelligence Coach's tools return. The app computes every number with the
// resolvers its screens use; the tools only format those values as short text with units, so the model has
// nothing to calculate and the number validator has one source per turn. The formatting here is pure and
// unit-tested; the iOS app supplies the values (`CoachFactsSource`).

/// The metrics a tool may be asked about: a closed list, never a free string from the model.
enum CoachMetric: String, CaseIterable, Sendable {
    case charge, rest, effort, hrv, restingHeartRate, sleepDuration, sleepDebt, stress, energy, steps

    /// The name the app shows for it, used in tool output.
    var label: String {
        switch self {
        case .charge: return String(localized: "Charge")
        case .rest: return String(localized: "Rest")
        case .effort: return String(localized: "Effort")
        case .hrv: return String(localized: "HRV")
        case .restingHeartRate: return String(localized: "Resting heart rate")
        case .sleepDuration: return String(localized: "Time asleep")
        case .sleepDebt: return String(localized: "Sleep debt")
        case .stress: return String(localized: "Stress")
        case .energy: return String(localized: "Energy")
        case .steps: return String(localized: "Steps")
        }
    }
}

/// Where the tools read from. Implemented by the iOS app over the same resolvers as its screens.
@MainActor
protocol CoachFactsSource: AnyObject, Sendable {
    /// Today's scores and states, one fact per line.
    func todaySnapshot() async -> String
    /// A 7/30/90-day summary of one metric.
    func metricTrend(_ metric: CoachMetric, days: Int) async -> String
    /// Tonight's sleep plan, and an active jet-lag trip.
    func sleepPlan() async -> String
    /// How the app computes a metric, as its info sheet says.
    func explain(_ metric: CoachMetric) -> String
    /// Journal tags and notes as quoted data; Mind check-ins only when `includeCheckIns`.
    func recentNotes(days: Int, includeCheckIns: Bool) async -> String
    /// The value a brief card shows beside a metric ("64%", "48 ms"), from the same resolvers; nil when none.
    func briefValue(_ metric: CoachMetric) async -> String?
}

/// A trend summary over a window: the tool reports these, the model only describes them.
struct CoachTrendSummary: Equatable, Sendable {
    enum Direction: String, Sendable { case rising, falling, steady }
    let count: Int
    let mean: Double
    let min: Double
    let max: Double
    let direction: Direction

    /// Mean, min and max of the days with a value; direction compares the mean of the last third of the
    /// window with the first third, "steady" within `steadyFraction` of the overall mean. Needs 3 values.
    static func summarize(_ values: [Double], steadyFraction: Double = 0.05) -> CoachTrendSummary? {
        let v = values.filter(\.isFinite)
        guard v.count >= 3 else { return nil }
        let mean = v.reduce(0, +) / Double(v.count)
        let third = Swift.max(1, v.count / 3)
        let first = v.prefix(third).reduce(0, +) / Double(third)
        let last = v.suffix(third).reduce(0, +) / Double(third)
        let delta = last - first
        let band = abs(mean) * steadyFraction
        let direction: Direction = abs(delta) <= band ? .steady : (delta > 0 ? .rising : .falling)
        return CoachTrendSummary(count: v.count, mean: mean, min: v.min()!, max: v.max()!, direction: direction)
    }
}

enum CoachFactFormat {

    /// Allowed trend windows; anything else snaps to the nearest.
    static let trendWindows = [7, 30, 90]

    static func trendWindow(_ days: Int) -> Int {
        trendWindows.min { abs($0 - days) < abs($1 - days) } ?? 30
    }

    /// One trend line: "HRV, last 30 days (28 days with data): average 48 ms, lowest 39 ms, highest 61 ms,
    /// rising." `format` renders a value the way the app displays it, units included.
    static func trend(_ metric: CoachMetric, days: Int, values: [Double], format: (Double) -> String) -> String {
        guard let s = CoachTrendSummary.summarize(values) else {
            return String(localized: "\(metric.label), last \(days) days: not enough data for a trend.")
        }
        let direction: String
        switch s.direction {
        case .rising: direction = String(localized: "rising")
        case .falling: direction = String(localized: "falling")
        case .steady: direction = String(localized: "steady")
        }
        return String(localized: "\(metric.label), last \(days) days (\(s.count) days with data): average \(format(s.mean)), lowest \(format(s.min)), highest \(format(s.max)), \(direction).")
    }

    /// A duration the way the tools state it ("8 h 29 min"): hours and minutes as separate numbers, so a
    /// reply that repeats them passes the validator, and never "8:29", which reads as a clock time.
    static func duration(minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return m >= 60 ? String(localized: "\(m / 60) h \(m % 60) min") : String(localized: "\(m) min")
    }

    /// User-written text as data: quoted, one line, cut to `limit` characters. The model is told notes are
    /// never instructions; quoting and cutting keeps a note from reading like part of the prompt.
    static func quoted(_ text: String, limit: Int = 140) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = oneLine.count > limit ? String(oneLine.prefix(limit)) + "…" : oneLine
        return "\"" + cut + "\""
    }

    /// Whether the person's question is about Mind check-ins or mood: only then may a tool include them.
    static func asksAboutCheckIns(_ question: String) -> Bool {
        let q = question.lowercased()
        let words = ["check-in", "check in", "checkin", "mood", "mind", "anxiety", "anxious", "depress",
                     "stimmung", "befinden", "ánimo", "animo", "humeur", "umore", "humor", "情绪", "心情", "情緒"]
        return words.contains { q.contains($0) }
    }
}
