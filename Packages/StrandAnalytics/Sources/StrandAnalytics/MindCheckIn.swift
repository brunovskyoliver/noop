import Foundation

// MindCheckIn.swift — scoring for the optional monthly Mind check-in, and the correlation of its scores
// with the body's own signals.
//
// Three short self-report forms, the same three WHOOP's monthly Mental Health Survey used
// (JMIR 2025, e64955):
//
//   • PSS-4, the 4-item Perceived Stress Scale. Cohen S, Kamarck T, Mermelstein R. "A global measure of
//     perceived stress." J Health Soc Behav 1983;24(4):385–396; 4-item form in Cohen & Williamson 1988.
//     Each item 0 (never) … 4 (very often) about the last month; items 2 and 3 are positively worded and
//     reverse-scored. Total 0–16, higher = more perceived stress. The PSS has no diagnostic cutoff; it is a
//     relative measure, so NOOP shows the score and its change only.
//   • GAD-2. Kroenke K, Spitzer RL, Williams JBW, et al. "Anxiety disorders in primary care: prevalence,
//     impairment, comorbidity, and detection." Ann Intern Med 2007;146(5):317–325.
//     doi:10.7326/0003-4819-146-5-200703060-00004
//   • PHQ-2. Kroenke K, Spitzer RL, Williams JBW. "The Patient Health Questionnaire-2: validity of a
//     two-item depression screener." Med Care 2003;41(11):1284–1292. doi:10.1097/01.MLR.0000093487.78664.3C
//     Both two-item forms score each item 0 (not at all) … 3 (nearly every day) about the last two weeks,
//     total 0–6, with ≥ 3 as the published screening cutoff. PHQ and GAD forms are free to reproduce
//     without permission (Pfizer). A score at or above the cutoff is NOT a diagnosis; the UI shows a
//     neutral suggestion to talk to a professional and nothing more.
//
// Pure and deterministic; storage and UI live in the app. iOS-only fork engine; no Kotlin twin.
public enum MindCheckIn {

    public enum Form: String, CaseIterable, Sendable {
        case pss4, gad2, phq2

        /// Answer range per item.
        public var itemRange: ClosedRange<Int> { self == .pss4 ? 0...4 : 0...3 }
        public var itemCount: Int { self == .pss4 ? 4 : 2 }
        public var maxScore: Int { itemCount * itemRange.upperBound }
        /// 0-based indices of reverse-scored items.
        public var reversedItems: Set<Int> { self == .pss4 ? [1, 2] : [] }
        /// Published screening cutoff (score ≥ cutoff), nil when the form has none.
        public var screeningCutoff: Int? { self == .pss4 ? nil : 3 }
        /// Storage key for the form's total.
        public var seriesKey: String { "mind_\(rawValue)" }
    }

    /// The total for one completed form, or nil when an answer is missing or out of range.
    public static func score(_ form: Form, answers: [Int]) -> Int? {
        guard answers.count == form.itemCount,
              answers.allSatisfy({ form.itemRange.contains($0) }) else { return nil }
        return answers.enumerated().reduce(0) { sum, pair in
            sum + (form.reversedItems.contains(pair.offset) ? form.itemRange.upperBound - pair.element : pair.element)
        }
    }

    /// True when a total sits at or above the form's published screening cutoff.
    public static func atOrAboveCutoff(_ form: Form, score: Int) -> Bool {
        guard let cutoff = form.screeningCutoff else { return false }
        return score >= cutoff
    }

    /// Days after which the next check-in is offered. Monthly, with a little slack so a check-in on the
    /// 30th and one on the 28th of the next month both count.
    public static let intervalDays = 28

    /// True when no check-in exists or the latest is at least `intervalDays` old.
    public static func isDue(lastCheckInDay: String?, today: String) -> Bool {
        guard let last = lastCheckInDay.flatMap(MindEngine.epoch) else { return true }
        guard let now = MindEngine.epoch(today) else { return false }
        return now - last >= intervalDays
    }

    /// A correlation needs at least this many check-ins. Monthly data accrues slowly, and a Pearson r on
    /// fewer points is noise; below it the UI says how many more are needed.
    public static let minPairs = 5
    /// |r| below this is reported as "no clear link".
    public static let minAbsR = 0.3

    /// Pair each check-in score with the mean of `signal` over the `windowDays` ending on the check-in day
    /// (the period the form asks about: 14 days for GAD-2 and PHQ-2, a month for PSS-4), then correlate.
    /// nil until `minPairs` check-ins have a signal mean.
    public static func correlate(scores: [(day: String, value: Double)],
                                 signal: [(day: String, value: Double)],
                                 windowDays: Int) -> Correlation? {
        guard windowDays > 0 else { return nil }
        let uniqueSignal = Dictionary(signal.filter { $0.value.isFinite }.map { ($0.day, $0.value) },
                                      uniquingKeysWith: { _, new in new })
        let dated = uniqueSignal.compactMap { p -> (Int, Double)? in MindEngine.epoch(p.key).map { ($0, p.value) } }
        let uniqueScores = Dictionary(scores.filter { $0.value.isFinite }.map { ($0.day, $0.value) },
                                      uniquingKeysWith: { _, new in new })
        var pairs: [(Double, Double)] = []
        for s in uniqueScores.map({ (day: $0.key, value: $0.value) }).sorted(by: { $0.day < $1.day }) {
            guard let end = MindEngine.epoch(s.day) else { continue }
            let xs = dated.filter { $0.0 <= end && $0.0 > end - windowDays }.map { $0.1 }
            guard !xs.isEmpty else { continue }
            pairs.append((s.value, xs.reduce(0, +) / Double(xs.count)))
        }
        guard pairs.count >= minPairs else { return nil }
        return CorrelationEngine.pearson(pairs)
    }

    /// The form's recall window in days, used as the correlation window.
    public static func recallDays(_ form: Form) -> Int { form == .pss4 ? 30 : 14 }
}
