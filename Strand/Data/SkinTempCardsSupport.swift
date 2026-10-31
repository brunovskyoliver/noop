import StrandAnalytics
import StrandDesign
import SwiftUI

/// Estimated body-clock phase + an optional jet-lag / shift plan. The plan is LIGHT + SLEEP
/// TIMING only — never a supplement. Behavioural awareness, approximate.
struct BodyClockCard: View {
    /// The phase estimate from `CircadianEngine.estimatePhase(...)`, computed in the analytics pass.
    let estimate: CircadianEngine.PhaseEstimate
    /// Optional active re-entrainment plan (jet-lag / shift). nil = no plan running.
    var plan: CircadianEngine.JetLagPlan? = nil
    /// Opens the body-clock detail / jet-lag planner. nil makes the card non-navigating.
    var onOpenPlanner: (() -> Void)? = nil

    // The body clock reads in the cool Rest world — calm, sleep-adjacent, non-valenced.
    private var hue: Color { StrandPalette.restColor }

    var body: some View {
        NoopCard(tint: hue) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header

                offsetHeadline

                Text(localizedBodyClockNote(estimate))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The estimated temperature-minimum clock time — the canonical phase marker.
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hue)
                        .accessibilityHidden(true)
                    Text("Estimated body-clock low around \(clockString(estimate.tempMinHour))")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .accessibilityElement(children: .combine)

                if let plan, plan.direction != .none, let firstDay = plan.days.first {
                    Divider().overlay(StrandPalette.hairline)
                    planSummary(plan, firstDay: firstDay)
                }

                if let onOpenPlanner {
                    Button(plan == nil
                           ? String(localized: "Plan a trip or shift")
                           : String(localized: "View the full plan"), action: onOpenPlanner)
                        .buttonStyle(.noopGhost)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Body clock").strandOverline()
                Text("Light + sleep timing only")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            ScoreStatePill(scoreState, text: confidenceLabel)
        }
    }

    private var offsetHeadline: some View {
        Text(offsetTitle)
            .font(StrandFont.title2)
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(offsetTitle)
    }

    private func planSummary(_ plan: CircadianEngine.JetLagPlan, firstDay: CircadianEngine.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan · \(plan.estimatedDays)-day shift")
                .strandOverline()
            // Day 1's concrete light + lights-out cue — light + sleep timing only.
            Text("Day 1: bright light \(clockString(firstDay.brightLightStartHour))-\(clockString(firstDay.brightLightEndHour)), lights-out around \(clockString(firstDay.targetSleepHour)).")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(localizedPlanNote(plan))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: derived copy

    /// "About 25 min later than your schedule" — a plain, skimmable headline.
    private var offsetTitle: String { Self.offsetTitle(estimate) }

    /// The headline for an estimate. Static so the Broop card words it through the same rule.
    static func offsetTitle(_ estimate: CircadianEngine.PhaseEstimate) -> String {
        let mins = Int(abs(estimate.offsetVsScheduleMinutes).rounded())
        if estimate.confidence == .unreadable {
            return String(localized: "Hard to read right now")
        }
        if mins <= 20 {
            return String(localized: "About in sync with your schedule")
        }
        return estimate.offsetVsScheduleMinutes > 0
            ? String(localized: "About \(mins) min later than your schedule")
            : String(localized: "About \(mins) min earlier than your schedule")
    }

    private var confidenceLabel: LocalizedStringKey {
        switch estimate.confidence {
        case .unreadable: return "Calibrating"
        case .wide:       return "Building"
        case .solid:      return "Solid"
        }
    }

    private var scoreState: ScoreState {
        switch estimate.confidence {
        case .unreadable: return .calibrating
        case .wide:       return .building
        case .solid:      return .solid
        }
    }

    /// Render a fractional clock hour using the app-selected locale's 12/24-hour convention.
    private func clockString(_ hour: Double) -> String {
        var h = hour.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        var hh = Int(h)
        var mm = Int(((h - Double(hh)) * 60).rounded())
        if mm == 60 { mm = 0; hh = (hh + 1) % 24 }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hh
        components.minute = mm
        guard let date = components.date else { return "\(hh):\(String(format: "%02d", mm))" }
        return AppClock.hourMinute(date)   // #1821
    }
}

func localizedBodyClockNote(_ estimate: CircadianEngine.PhaseEstimate) -> String {
    if estimate.confidence == .unreadable {
        return String(localized: "Your rhythm is hard to read right now. Keep wearing your device for a clearer picture.")
    }
    if estimate.offsetVsScheduleMinutes > 20 {
        return String(localized: "Your body clock looks later, with a night-owl tendency.")
    }
    if estimate.offsetVsScheduleMinutes < -20 {
        return String(localized: "Your body clock looks earlier, with a morning tendency.")
    }
    return String(localized: "Your body clock looks aligned with your schedule.")
}

func localizedConfounder(_ value: String) -> String {
    switch value {
    case "alcohol": return String(localized: "Alcohol").lowercased(with: AppLanguage.activeLocale)
    case "stress": return String(localized: "Stress").lowercased(with: AppLanguage.activeLocale)
    case "sauna": return String(localized: "Sauna")
    case "hardOrLateWorkout", "a hard or late workout": return String(localized: "Hard or late workout")
    case "travel": return String(localized: "Travel")
    default: return value
    }
}

func localizedConfounder(_ reason: IllnessSignalEngine.SuppressionReason) -> String {
    switch reason {
    case .alcohol: return String(localized: "Alcohol").lowercased(with: AppLanguage.activeLocale)
    case .stress: return String(localized: "Stress").lowercased(with: AppLanguage.activeLocale)
    case .sauna: return String(localized: "Sauna")
    case .hardOrLateWorkout: return String(localized: "Hard or late workout")
    case .travel: return String(localized: "Travel")
    }
}

/// The analytics engines stay locale-free for Swift/Kotlin parity. Translate their finite presentation
/// states at the UI boundary so none of that engine copy leaks onto Home in English.
func localizedCycleStatus(_ result: CyclePhaseEngine.Result) -> String {
    if result.note.contains("different time") {
        return String(localized: "Your temperature shift came at a different time than your logged date – the logged start may be off.")
    }
    switch result.phase {
    case .follicular:
        return String(localized: "Follicular range – temperature is near your baseline.")
    case .periOvulatory:
        return String(localized: "Around your mid-cycle shift – temperature is changing.")
    case .luteal:
        return String(localized: "Luteal range – temperature is above your baseline.")
    case .unknown:
        return String(localized: "No clear temperature pattern yet. This can happen with irregular cycles, hormonal contraception or shift work.")
    case .learning:
        return String(localized: "Learning your pattern from your nightly temperature. Keep wearing your device overnight.")
    }
}

func localizedIllnessCopy(_ result: IllnessSignalEngine.Result) -> String {
    let signals = localizedList(result.firedSignals)
    let reasons = localizedList(result.suppressedBy.map(localizedConfounder))
    let message = result.message ?? fallbackIllnessMessage(result.level)
    switch message {
    case .raised:
        return String(localized: "Your body looks strained. Signals up: \(signals). No alcohol or travel was logged, so consider taking it easy. On-device estimate, not a diagnosis.")
    case .alreadyUnwellAgree:
        return String(localized: "You logged feeling unwell, and your signals agree. Take it easy today. On-device estimate, not a diagnosis.")
    case .alreadyUnwell:
        return String(localized: "You logged feeling unwell. Take it easy today. On-device estimate, not a diagnosis.")
    case .suppressed:
        return String(localized: "Some signals are up, but you logged \(reasons). That is the more likely explanation. On-device estimate, not a diagnosis.")
    case .mild:
        return String(localized: "A few signals are mildly up: \(signals). Nothing alarming, but a calmer day may help. On-device estimate, not a diagnosis.")
    case .learningBaseline:
        return String(localized: "Still learning your baseline and keeping an eye on your signals.")
    case .normal:
        return String(localized: "Nothing notable. Your signals look like their normal range.")
    }
}

func localizedPlanNote(_ plan: CircadianEngine.JetLagPlan) -> String {
    let hours = String(format: "%.1f", locale: AppLanguage.activeLocale, plan.totalShiftHours)
    switch plan.direction {
    case .advance:
        return String(localized: "Shifting your clock \(hours) h earlier, about an hour a day. Light and sleep timing only.")
    case .delay:
        return String(localized: "Shifting your clock \(hours) h later, about an hour a day. Light and sleep timing only.")
    case .none:
        return String(localized: "No meaningful body-clock shift is needed. You are about aligned.")
    }
}

/// Maps the parallel Mahalanobis distance to a plain confidence word + a one-decimal display value.
/// This is presentation-only: it NEVER decides whether the Heads-Up card shows (the engine's level
/// already did). Bands: >= 3.5 strong, >= 2.5 moderate, else slight. Identical to the Kotlin twin.
enum IllnessConfidence {
    static func band(_ distance: Double) -> String {
        if distance >= 3.5 { return String(localized: "strong") }
        if distance >= 2.5 { return String(localized: "moderate") }
        return String(localized: "slight")
    }
    static func formatted(_ distance: Double) -> String {
        String(format: "%.1f", locale: AppLanguage.activeLocale, distance)
    }
}

func fallbackIllnessMessage(_ level: IllnessSignalEngine.Level) -> IllnessSignalEngine.Message {
    switch level {
    case .raised: return .raised
    case .alreadyUnwell: return .alreadyUnwell
    case .suppressed: return .suppressed
    case .mild: return .mild
    case .quiet: return .normal
    }
}

func localizedList(_ values: [String]) -> String {
    let formatter = ListFormatter()
    formatter.locale = AppLanguage.activeLocale
    return formatter.string(from: values) ?? values.joined(separator: ", ")
}
