import Foundation

struct SleepSegment: Identifiable {
    enum Stage: Int, CaseIterable {
        case deep = 0, light, rem, awake
        var name: String {
            switch self {
            case .deep: return "Deep"
            case .light: return "Light"
            case .rem: return "REM"
            case .awake: return "Awake"
            }
        }
    }
    let id: Int
    let stage: Stage
    let start: Date
    let end: Date
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

struct Activity: Identifiable {
    let id: Int
    let name: String
    let symbol: String
    let start: Date
    let minutes: Int
    let effort: Double
    let avgHR: Int
}

struct DayMetrics: Identifiable {
    let id: Int
    let date: Date
    let charge: Double
    let hrv: Double
    let rhr: Double
    let respiratory: Double
    let spo2: Double
    let skinTempDelta: Double
    let rest: Double
    let asleepMinutes: Double
    let needMinutes: Double
    let bedtime: Date
    let wake: Date
    let segments: [SleepSegment]
    let effort: Double
    let activities: [Activity]
    let steps: Double
    let calories: Double
    let zoneMinutes: [Double]

    var inBedMinutes: Double { wake.timeIntervalSince(bedtime) / 60 }
    var efficiency: Double { asleepMinutes / inBedMinutes * 100 }
    var hoursVsNeed: Double { asleepMinutes / needMinutes * 100 }
    func minutes(_ stage: SleepSegment.Stage) -> Double {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }
    var restorativePct: Double { (minutes(.deep) + minutes(.rem)) / max(asleepMinutes, 1) * 100 }
}

/// Deterministic fake history so every launch shows the same days.
enum SampleGenerator {
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    static func make(count: Int) -> [DayMetrics] {
        var rng = SplitMix64(state: 20_260_928)
        func g() -> Double {
            let u1 = Double.random(in: 0.0001..<1, using: &rng)
            let u2 = Double.random(in: 0..<1, using: &rng)
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let templates: [(String, String, ClosedRange<Int>, ClosedRange<Double>)] = [
            ("Running", "figure.run", 30...65, 9...15),
            ("Cycling", "figure.outdoor.cycle", 45...110, 10...16),
            ("Strength", "dumbbell.fill", 40...70, 6...11),
            ("Walking", "figure.walk", 25...60, 3...7),
            ("Yoga", "figure.yoga", 30...60, 3...6),
        ]

        var days: [DayMetrics] = []
        var prevEffort = 11.0
        var activityID = 0
        var segmentID = 0

        for i in 0..<count {
            let isToday = i == count - 1
            let date = cal.date(byAdding: .day, value: i - (count - 1), to: today)!
            let fitness = sin(Double(i) / 21) * 0.6 + Double(i) / Double(count) * 0.4

            let hrv = clamp(55 + 7 * fitness - (prevEffort - 11) * 0.8 + 5 * g(), 28, 110)
            let rhr = clamp(53 - 2.2 * fitness + (prevEffort - 11) * 0.3 + 1.6 * g(), 42, 70)
            let need = 470 + (prevEffort - 11) * 4 + 8 * g()
            let asleep = clamp(445 + 38 * g(), 300, 560)
            let rest = clamp(asleep / need * 100 - Double.random(in: 0...6, using: &rng), 20, 100)
            let respiratory = 14.7 + 0.3 * g()
            let spo2 = clamp(96.4 + 0.8 * g(), 92, 99.5)
            // Today carries one elevated vital so the Health strip has something to say.
            let skin = isToday ? 0.62 : 0.16 * g()
            let charge = clamp(46 + (hrv - 55) * 2.4 - (rhr - 53) * 3.0 + (rest - 85) * 0.7 + 10 * g(), 4, 99)

            // Sleep: latency, then ~90-minute cycles with deep front-loaded and REM back-loaded.
            let bedtime = date.addingTimeInterval((-60 + 18 * g()) * 60)
            var cursor = bedtime
            var segments: [SleepSegment] = []
            func add(_ stage: SleepSegment.Stage, _ minutes: Double) {
                let end = cursor.addingTimeInterval(minutes * 60)
                segments.append(SleepSegment(id: segmentID, stage: stage, start: cursor, end: end))
                segmentID += 1
                cursor = end
            }
            add(.awake, 8 + abs(4 * g()))
            let cycles = max(3, Int(asleep / 90))
            let cycleLength = asleep / Double(cycles)
            for k in 0..<cycles {
                let deep = max(0.04, 0.34 - 0.08 * Double(k))
                let rem = min(0.42, 0.12 + 0.07 * Double(k))
                let light = 1 - deep - rem
                add(.light, cycleLength * light * 0.5)
                add(.deep, cycleLength * deep)
                add(.light, cycleLength * light * 0.5)
                add(.rem, cycleLength * rem)
                if k % 2 == 1 && k < cycles - 1 { add(.awake, 3 + abs(2 * g())) }
            }
            add(.awake, 4)
            let wake = cursor

            var activities: [Activity] = []
            let roll = Double.random(in: 0..<1, using: &rng)
            let activityCount = isToday ? 1 : (roll < 0.3 ? 0 : (roll < 0.85 ? 1 : 2))
            for n in 0..<activityCount {
                let t = isToday ? templates[0] : templates[Int.random(in: 0..<templates.count, using: &rng)]
                let hour = n == 0 ? 7 : 18
                let start = date.addingTimeInterval(Double(hour) * 3600 + Double(Int.random(in: 0...40, using: &rng)) * 60)
                activities.append(Activity(
                    id: activityID,
                    name: t.0,
                    symbol: t.1,
                    start: start,
                    minutes: Int.random(in: t.2, using: &rng),
                    effort: Double.random(in: t.3, using: &rng),
                    avgHR: Int.random(in: 118...156, using: &rng)
                ))
                activityID += 1
            }
            let activityEffort = activities.reduce(0) { $0 + $1.effort }
            let effort = clamp(4.5 + activityEffort * 0.55 + 1.2 * g(), 1, 20.5)
            let steps = max(1500, 6800 + 2400 * g() + (activities.contains { $0.name == "Walking" || $0.name == "Running" } ? 4200 : 0))
            let calories = 1850 + effort * 58 + 60 * g()
            let active = Double(activities.reduce(0) { $0 + $1.minutes })
            let zones = [0.30, 0.28, 0.24, 0.13, 0.05].map { ($0 * active + 45 * $0).rounded() }

            days.append(DayMetrics(
                id: i, date: date, charge: charge, hrv: hrv, rhr: rhr,
                respiratory: respiratory, spo2: spo2, skinTempDelta: skin,
                rest: rest, asleepMinutes: asleep, needMinutes: need,
                bedtime: bedtime, wake: wake, segments: segments,
                effort: effort, activities: activities, steps: steps,
                calories: calories, zoneMinutes: zones
            ))
            prevEffort = effort
        }
        return days
    }
}
