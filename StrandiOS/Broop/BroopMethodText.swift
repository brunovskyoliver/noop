#if os(iOS)
import Foundation
import StrandAnalytics

/// How each metric is computed, in the words its info sheet shows. One copy, read by the sheets and by the
/// Coach's `explainMetric` tool, so the Coach explains a metric exactly as the app does.
enum BroopMethodText {
    static var charge: String {
        String(localized: "Led by your heart-rate variability (HRV) measured against your own personal baseline, plus resting heart rate, last night's Rest, breathing rate, and a skin-temperature signal (an early illness or overreach flag). Higher HRV versus your baseline means more Charge. NOOP needs a few nights to learn your baseline first. Until then you'll see “Calibrating”.")
    }
    static var effort: String {
        String(localized: "Your cardiovascular load. NOOP turns every second of heart rate into a training-impulse using heart-rate-reserve zones (Karvonen), weights time in harder zones more heavily (Edwards / Banister), and places it on a logarithmic 0-100 scale, so easy days sit low and an all-out day approaches 100, which stays genuinely rare. A long walk with little cardio still counts, through a steps / active-energy floor.")
    }
    static var rest: String {
        String(localized: "A blend of how long you slept versus your personal need (the biggest factor), how efficiently (asleep versus in bed), how much was restorative (deep + REM sleep), and how consistent your sleep and wake timing is.")
    }
    static var hrvReadiness: String {
        String(localized: "Compares the last 7 calendar days' mean ln RMSSD with the preceding 60 days' mean ± 0.5 SD (SWC), shown in milliseconds. Needs 21 baseline nights and 3 recent nights; stale data has no card. Above usual can follow rest or fatigue. This trend does not change Charge and is not a diagnosis.")
    }
    /// The HRV readiness band as the card titles it.
    static func hrvBandTitle(_ b: HRVStatus.Band) -> String {
        switch b {
        case .balanced: return String(localized: "Balanced")
        case .above: return String(localized: "Above usual")
        case .below: return String(localized: "Below usual")
        case .low: return String(localized: "Low")
        }
    }
    static var stress: String {
        String(localized: "Stress is an on-device estimate on a 0–3 scale. Waking heart rate is compared with calm, non-exercise periods from the previous 14 days. Before enough history is available, today's calm periods provide a provisional reference. Movement and workouts are excluded. Sleep uses a separate personal heart-rate and HRV reference when R-R intervals are available. Daytime HRV is not scored because motion can distort wrist measurements. Live values use fresh heart-rate packets; an unusually elevated live pulse is withheld because movement cannot be confirmed. This is not WHOOP's proprietary algorithm or a mental-health assessment.")
    }
    static var energyIntro: String {
        String(localized: "Energy is a 0–100 estimate of your reserves. Restful sleep and calm, still rest charge it; being awake, stress and exercise drain it. It carries over from one day to the next instead of resetting at midnight.")
    }
    static var energyCharging: String {
        String(localized: "During sleep it charges toward 100, faster when it is low. Each 5 minutes counts in full when your sleeping stress is at its typical calm level and not at all when it reaches the high band. Eight calm hours from 40 end near 92. Awake, 10 or more minutes of low stress while still add a small amount.")
    }
    static var energyDraining: String {
        String(localized: "Being awake costs 2 per hour. Stress costs 6 per hour for each point above the calm level of 1, so an hour at level 2 costs 8 in total. Exercise costs 0.1 per point of Edwards heart-rate load, which is about 12 per hour in zone 2. Stress is not scored during exercise, so nothing is counted twice.")
    }
    static var energyGaps: String {
        String(localized: "When the strap is off the level holds flat; nothing is guessed. Energy stays in calibration until the Stress Monitor has learned your personal calm and sleeping references, which takes about 4 days.")
    }
    static var energyNotThis: String {
        String(localized: "Garmin's Body Battery comes from Firstbeat, whose model is proprietary and unpublished. This is NOOP's own estimate with its own constants, computed on your phone. It does not change Charge, Rest, Effort, Healthspan or Mind.")
    }
    static var sleepDebt: String {
        String(localized: "Sleep debt weighs the gap between your sleep need and the sleep you got over the last 14 nights, recent nights counting most, with naps credited. Your need is the upper quartile of your own nights, never below the adult target.")
    }
    static var restingHeartRate: String {
        String(localized: "Resting heart rate is your lowest steady heart rate during sleep, read by the strap each night.")
    }
    static var sleepDuration: String {
        String(localized: "Time asleep counts light, deep and REM sleep in your main sleep, not the time spent awake in bed.")
    }
    static var steps: String {
        String(localized: "Steps come from Apple Health, or from the strap's motion when Health has none.")
    }
}
#endif
