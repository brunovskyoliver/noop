import Foundation

/// "Ask Coach about this" on the Charge, Effort, Sleep and Stress screens: the question handed to Coach
/// (`AICoachEngine.pendingPrompt`) for the metric and the day the screen shows. A past day is named by its
/// date, so the Apple Intelligence Coach looks it up with its day tool and a cloud provider finds it in the
/// two weeks of context it is sent. Pure; unit-tested.
enum CoachAskAbout {
    enum Topic: Sendable { case charge, rest, effort, stress }

    /// The day key handed to Coach with the question: nil for today (its own snapshot covers it).
    static func dayKey(daysAgo: Int, day: Date) -> String? {
        daysAgo <= 0 ? nil : Repository.localDayKey(day)
    }

    static func question(_ topic: Topic, daysAgo: Int, day: Date, calendar: Calendar = .current,
                         locale: Locale = AppLanguage.activeLocale) -> String {
        if daysAgo <= 0 {
            switch topic {
            case .charge: return String(localized: "Why is my Charge where it is today, and what should I do with it?")
            case .rest: return String(localized: "How did I sleep last night, and what shaped my Rest?")
            case .effort: return String(localized: "How is my Effort today against my target, and what should I do with the rest of the day?")
            case .stress: return String(localized: "How has my stress been today, and what can I do about it?")
            }
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let named = f.string(from: day)
        let onDay = daysAgo == 1 ? String(localized: "yesterday (\(named))") : String(localized: "on \(named)")
        switch topic {
        case .charge: return String(localized: "Why was my Charge what it was \(onDay)?")
        // Rest belongs to the morning it is scored on, so the night is named by that morning.
        case .rest: return String(localized: "How did I sleep on the night into \(named), and what shaped my Rest?")
        case .effort: return String(localized: "How did my Effort \(onDay) compare with my usual?")
        case .stress: return String(localized: "How was my stress \(onDay)?")
        }
    }
}
