import Foundation

/// Resolves activity values and their comparison history with the same source priority per day.
enum BroopActivityReadings {
    struct Day {
        let day: String
        var steps: Double?
        var activeKcal: Double?
    }

    struct Reading {
        let value: Double
        let history: [Double]
    }

    struct Selection {
        let steps: Reading?
        let activeKcal: Reading?
    }

    static func resolve(day: String, native: [Day], apple: [Day],
                        estimates: [(day: String, value: Double)]) -> Selection {
        let nativeByDay = Dictionary(native.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        var appleByDay: [String: Day] = [:]
        for row in apple {
            var merged = appleByDay[row.day] ?? Day(day: row.day)
            if let steps = row.steps { merged.steps = max(merged.steps ?? steps, steps) }
            if let kcal = row.activeKcal { merged.activeKcal = max(merged.activeKcal ?? kcal, kcal) }
            appleByDay[row.day] = merged
        }
        let estimatesByDay = Dictionary(estimates.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
        let keys = Set(nativeByDay.keys).union(appleByDay.keys).union(estimatesByDay.keys)
        let previousDays = keys.filter { $0 < day }.sorted().suffix(30)

        func steps(_ key: String) -> Double? {
            nativeByDay[key]?.steps ?? appleByDay[key]?.steps ?? estimatesByDay[key]
        }
        func kcal(_ key: String) -> Double? {
            appleByDay[key]?.activeKcal ?? nativeByDay[key]?.activeKcal
        }
        return Selection(
            steps: steps(day).map { Reading(value: $0, history: previousDays.compactMap(steps)) },
            activeKcal: kcal(day).map { Reading(value: $0, history: previousDays.compactMap(kcal)) })
    }
}
