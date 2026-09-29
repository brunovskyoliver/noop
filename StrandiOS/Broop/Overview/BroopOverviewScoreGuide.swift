#if os(iOS)
import SwiftUI

/// "How your scores work" in Broop's look: the classic `ScoringGuideView`'s copy (same localized strings)
/// on Broop cards, with a thin dial per score in its Broop colour instead of the classic glow rings.
/// Opened from the (i) on every deep dive and from About. Presented as a sheet; it brings its own stack.
struct BroopOverviewScoreGuide: View {
    var initialSection: ScoreSection? = nil
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How your scores work")
                                .font(BroopType.demi(24))
                                .foregroundStyle(BroopPalette.textPrimary)
                            Text("NOOP gives you three daily scores (Charge, Effort and Rest), each on a 0-100 scale. They're built from your strap's raw signals using published, peer-reviewed sport science, and computed entirely on your device. They are NOT WHOOP's scores: we don't have WHOOP's private algorithms and don't pretend to. They aim at the same three questions using open science, so they'll usually track WHOOP's in direction, but won't match number-for-number. And that's the point.")
                                .font(BroopType.regular(14))
                                .foregroundStyle(BroopPalette.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 8)

                        card(.charge, score: .charge, sample: 82,
                             headline: String(localized: "Charge: how recovered are you?"),
                             body: String(localized: "Led by your heart-rate variability (HRV) measured against your own personal baseline, plus resting heart rate, last night's Rest, breathing rate, and a skin-temperature signal (an early illness or overreach flag). Higher HRV versus your baseline means more Charge. NOOP needs a few nights to learn your baseline first. Until then you'll see “Calibrating”."),
                             vsWhoop: String(localized: "Same core idea as WHOOP's Recovery % (HRV-led recovery), but our weighting and baseline maths are our own, and openly documented."))
                        card(.effort, score: .effort, sample: 64,
                             headline: String(localized: "Effort: how hard did your heart work?"),
                             body: String(localized: "Your cardiovascular load. NOOP turns every second of heart rate into a training-impulse using heart-rate-reserve zones (Karvonen), weights time in harder zones more heavily (Edwards / Banister), and places it on a logarithmic 0-100 scale, so easy days sit low and an all-out day approaches 100, which stays genuinely rare. A long walk with little cardio still counts, through a steps / active-energy floor."),
                             vsWhoop: String(localized: "Same cardiovascular-load idea as WHOOP's Day Strain (0-21). We rescaled the top of the ladder from 21 to 100 so all three scores share one scale. The rungs didn't move, so a 100 is as rare as a 21.0 was."))
                        card(.rest, score: .rest, sample: 88,
                             headline: String(localized: "Rest: how restorative was your sleep?"),
                             body: String(localized: "A blend of how long you slept versus your personal need (the biggest factor), how efficiently (asleep versus in bed), how much was restorative (deep + REM sleep), and how consistent your sleep and wake timing is."),
                             vsWhoop: String(localized: "Similar in spirit to WHOOP's Sleep Performance %; our composite is our own."))

                        BroopCard {
                            VStack(alignment: .leading, spacing: 10) {
                                BroopCaps(String(localized: "How sure is NOOP?"), size: 11)
                                HStack(spacing: 8) {
                                    chip(String(localized: "Solid"), BroopPalette.teal)
                                    chip(String(localized: "Building"), BroopPalette.warning)
                                    chip(String(localized: "Calibrating"), BroopPalette.textSecondary)
                                }
                                Text("Every score carries a small honesty label. Calibrating means NOOP is still learning your baseline, or doesn't have enough data yet. Building means there's enough to show, but it's thin. Solid means full inputs are present. When NOOP can't compute a score honestly, it shows nothing rather than a fake number.")
                                    .font(BroopType.regular(13.5))
                                    .foregroundStyle(BroopPalette.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("These are independent approximations from a consumer strap, built on open science: not medical advice, and not WHOOP's official scores.")
                            .font(BroopType.regular(12))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, BroopMetrics.page)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let initialSection else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(initialSection.id, anchor: .top) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                BroopNavHeader(showsBack: false, center: { BroopNavTitle(title: String(localized: "Your daily scores")) },
                               trailing: {
                                   Button(action: onClose) { Text("Done").font(BroopType.demi(16)) }
                                       .foregroundStyle(BroopPalette.textPrimary)
                               })
            }
            .background(BroopBackground())
            .broopBarChrome()
        }
        .presentationDragIndicator(.visible)
    }

    private func card(_ section: ScoreSection, score: BroopScore, sample: Double,
                      headline: String, body: String, vsWhoop: String) -> some View {
        BroopCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    BroopDial(score: score, value: sample, diameter: 64, lineWidth: 4.5)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        BroopCaps(section.displayName, size: 11, color: score.color(for: sample))
                        Text(verbatim: headline)
                            .font(BroopType.demi(16))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: body)
                    .font(BroopType.regular(13.5))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                BroopHairline()
                HStack(alignment: .top, spacing: 10) {
                    BroopCaps(String(localized: "vs WHOOP"), size: 9.5, color: BroopPalette.textSecondary)
                        .padding(.top, 2)
                    Text(verbatim: vsWhoop)
                        .font(BroopType.regular(12.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(section.id)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            BroopCaps(text, size: 9.5, color: color)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.badgeRadius).fill(color.opacity(0.14)))
    }
}
#endif
