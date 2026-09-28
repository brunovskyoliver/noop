import SwiftUI

/// One metric measured against the user's own 30-day baseline.
struct Contributor: Identifiable {
    enum Better { case higher, lower, neutral }
    enum Status { case typical, above, below }

    let name: String
    let value: Double
    let unit: String
    let typical: ClosedRange<Double>
    let domain: ClosedRange<Double>
    let baseline: Double
    let better: Better
    /// The one screen that owns this fact. Every other appearance links here.
    let home: ScoreKind
    let format: (Double) -> String

    var id: String { name }
    var text: String { format(value) }

    var status: Status {
        if value > typical.upperBound { return .above }
        if value < typical.lowerBound { return .below }
        return .typical
    }

    /// Colour for a deviation: green when it moved the good way, amber otherwise.
    var tint: Color {
        switch (status, better) {
        case (.typical, _): return Broop.Palette.textTertiary
        case (.above, .higher), (.below, .lower): return Broop.Palette.teal
        default: return Broop.Palette.warning
        }
    }

    var trendSymbol: String? {
        if abs(value - baseline) < (typical.upperBound - typical.lowerBound) * 0.08 { return nil }
        return value > baseline ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    var trendTint: Color {
        switch better {
        case .neutral: return Broop.Palette.textTertiary
        case .higher: return value >= baseline ? Broop.Palette.teal : Broop.Palette.warning
        case .lower: return value <= baseline ? Broop.Palette.teal : Broop.Palette.warning
        }
    }
}

struct Readiness {
    let label: String
    let title: String
    let color: Color
    let target: ClosedRange<Double>
    let message: String
}

enum Route: Hashable {
    case score(ScoreKind)
}

enum AppTab: Hashable {
    case today, health, more
}

final class SampleStore: ObservableObject {
    let days: [DayMetrics]
    let streak = 42
    let battery = 0.82
    @Published private(set) var selectedIndex: Int

    init() {
        days = SampleGenerator.make(count: 200)
        selectedIndex = days.count - 1
    }

    var selected: DayMetrics { days[selectedIndex] }
    var isToday: Bool { selectedIndex == days.count - 1 }

    var dayLabel: String {
        switch days.count - 1 - selectedIndex {
        case 0: return "TODAY"
        case 1: return "YESTERDAY"
        default: return selected.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        }
    }

    func step(_ delta: Int) {
        let next = min(max(selectedIndex + delta, 0), days.count - 1)
        guard next != selectedIndex else { return }
        withAnimation(.snappy) { selectedIndex = next }
    }

    func goToToday() { step(days.count - 1 - selectedIndex) }

    // MARK: Baselines

    func contributor(
        _ name: String, unit: String = "", better: Contributor.Better, home: ScoreKind,
        format: @escaping (Double) -> String, _ metric: (DayMetrics) -> Double
    ) -> Contributor {
        let i = selectedIndex
        let value = metric(days[i])
        var window = days[max(0, i - 30)..<i].map(metric)
        if window.isEmpty { window = [value] }
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)
        let sd = max(variance.squareRoot(), abs(mean) * 0.02, 0.05)
        let pad = max(sd * 3, abs(value - mean) * 1.3)
        return Contributor(
            name: name, value: value, unit: unit,
            typical: (mean - sd)...(mean + sd),
            domain: (mean - pad)...(mean + pad),
            baseline: mean, better: better, home: home, format: format
        )
    }

    var vitals: [Contributor] {
        [
            contributor("HRV", unit: "ms", better: .higher, home: .charge, format: Fmt.whole) { $0.hrv },
            contributor("Resting heart rate", unit: "bpm", better: .lower, home: .charge, format: Fmt.whole) { $0.rhr },
            contributor("Respiratory rate", unit: "rpm", better: .neutral, home: .charge, format: Fmt.one) { $0.respiratory },
            contributor("Blood oxygen", unit: "%", better: .higher, home: .charge, format: Fmt.one) { $0.spo2 },
            contributor("Skin temperature", unit: "°C", better: .neutral, home: .charge, format: Fmt.signed) { $0.skinTempDelta },
        ]
    }

    /// 0–3 stress score from how far HR and HRV sit from baseline (sample-data stand-in).
    var stress: (value: Double, label: String, color: Color, time: Date) {
        let v = vitals
        let z = (v[1].value - v[1].baseline) / 3 - (v[0].value - v[0].baseline) / 12
        let value = min(max(1.4 + z, 0), 3)
        let time = selected.date.addingTimeInterval(isToday ? Date().timeIntervalSince(selected.date) : 20 * 3600 + 54 * 60)
        if value >= 2 { return (value, "High", Broop.Palette.warning, time) }
        if value >= 1 { return (value, "Medium", Broop.Palette.teal, time) }
        return (value, "Low", Broop.Palette.rest, time)
    }

    var outliers: [Contributor] { vitals.filter { $0.status != .typical } }

    var chargeContributors: [Contributor] {
        let v = vitals
        return [v[0], v[1], contributor("Rest", unit: "%", better: .higher, home: .rest, format: Fmt.whole) { $0.rest }] + v[2...]
    }

    var restContributors: [Contributor] {
        [
            contributor("Hours vs need", unit: "%", better: .higher, home: .rest, format: Fmt.whole) { $0.hoursVsNeed },
            contributor("Time asleep", better: .higher, home: .rest, format: Fmt.duration) { $0.asleepMinutes },
            contributor("Efficiency", unit: "%", better: .higher, home: .rest, format: Fmt.whole) { $0.efficiency },
            contributor("Restorative sleep", unit: "%", better: .higher, home: .rest, format: Fmt.whole) { $0.restorativePct },
        ]
    }

    var effortContributors: [Contributor] {
        [
            contributor("Steps", better: .neutral, home: .effort, format: Fmt.whole) { $0.steps },
            contributor("Calories", unit: "kcal", better: .neutral, home: .effort, format: Fmt.whole) { $0.calories },
            contributor("Zone 4–5", unit: "min", better: .neutral, home: .effort, format: Fmt.whole) { $0.zoneMinutes[3] + $0.zoneMinutes[4] },
        ]
    }

    var dashboard: [Contributor] {
        let v = vitals
        let e = effortContributors
        return [v[0], v[1], restContributors[3], v[2], e[0], e[1]]
    }

    var readiness: Readiness {
        let charge = selected.charge
        let driver = vitals.max { a, b in
            abs(a.value - a.baseline) / max(a.typical.upperBound - a.baseline, 0.01)
                < abs(b.value - b.baseline) / max(b.typical.upperBound - b.baseline, 0.01)
        }
        var note = ""
        if let d = driver, d.status != .typical {
            note = " \(d.name) is \(d.status == .above ? "above" : "below") your usual range, so keep an eye on it."
        }
        if charge >= 67 {
            return Readiness(
                label: "PUSH", title: "Ready to perform", color: Broop.Palette.bandHigh, target: 14...18,
                message: "Take advantage of your high Charge by reaching an Effort of 14–18. Your body can take on significant load today." + note
            )
        } else if charge >= 34 {
            return Readiness(
                label: "MAINTAIN", title: "Steady day", color: Broop.Palette.bandMid, target: 10...14,
                message: "Your body can handle moderate load. An Effort of 10–14 keeps you progressing without digging a hole." + note
            )
        } else {
            return Readiness(
                label: "RECOVER", title: "Take it easy", color: Broop.Palette.bandLow, target: 5...9,
                message: "Your body is asking for recovery. Keep Effort between 5 and 9 and prioritise sleep tonight." + note
            )
        }
    }
}
