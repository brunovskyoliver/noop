#if os(iOS)
import SwiftUI
import StrandAnalytics

/// "What shaped it": the engine's Charge drivers in Broop form, replacing the classic
/// `ChargeBreakdownSection` inside the What shaped your Charge sheets. A header with the confidence tag, one
/// row per `ChargeDriver` (biggest mover first, as the engine orders them) with the signed points in the
/// Charge band colours, value against baseline, a diverging bar scaled to the day's biggest mover and the
/// engine's verdict, then the relative skin-temperature marker. Every value and word comes from the engine
/// and `ChargeBreakdownFormat`; nothing is recomputed here.
struct BroopFinalAChargeBreakdown: View {
    let drivers: [ChargeDriver]
    let confidence: ScoreConfidence
    var skinTempRel: SkinTempRelative? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                BroopCaps(String(localized: "What shaped it"), size: 11)
                Spacer()
                BroopFinalAConfidenceTag(confidence: confidence)
            }
            let maxMag = Double(max(1, drivers.map { abs($0.deltaPoints) }.max() ?? 1))
            ForEach(Array(drivers.enumerated()), id: \.offset) { i, driver in
                if i > 0 { BroopHairline() }
                row(driver, maxMag: maxMag)
            }
            if let rel = skinTempRel {
                BroopHairline()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BroopPalette.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Skin temperature").font(BroopType.demi(15)).foregroundStyle(BroopPalette.textPrimary)
                        Text(verbatim: ChargeBreakdownFormat.skinTempTierWord(rel.tier))
                            .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    Spacer()
                    Text(verbatim: ChargeBreakdownFormat.skinTempDeviationLabel(rel))
                        .font(BroopType.number(15))
                        .foregroundStyle(BroopPalette.warning)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(String(localized: "Skin temperature")) \(ChargeBreakdownFormat.skinTempDeviationLabel(rel)). \(ChargeBreakdownFormat.skinTempTierWord(rel.tier))."))
            }
        }
    }

    private func color(_ d: Int) -> Color {
        d > 0 ? BroopPalette.bandHigh : (d < 0 ? BroopPalette.bandLow : BroopPalette.textSecondary)
    }

    private func row(_ driver: ChargeDriver, maxMag: Double) -> some View {
        let tint = color(driver.deltaPoints)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(driver.label))
                    .font(BroopType.demi(15))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer(minLength: 8)
                Text(verbatim: ChargeBreakdownFormat.chipLabel(deltaPoints: driver.deltaPoints))
                    .font(BroopType.number(16))
                    .foregroundStyle(tint)
            }
            HStack(spacing: 6) {
                Text(verbatim: driver.valueText).font(BroopType.number(13)).foregroundStyle(BroopPalette.textBody)
                if !driver.baselineText.isEmpty {
                    Text(verbatim: "·").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                    Text(verbatim: driver.baselineText).font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            BroopFinalADivergingBar(fraction: Double(driver.deltaPoints) / maxMag, color: tint)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(driver.verdict))
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ChargeBreakdownFormat.driverAccessibilityLabel(driver)))
    }
}

/// CALIBRATING / EST. / REL. as a small tag, the tier words from `ChargeBreakdownFormat`.
struct BroopFinalAConfidenceTag: View {
    let confidence: ScoreConfidence

    var body: some View {
        let tint: Color = {
            switch confidence {
            case .solid: return BroopPalette.teal
            case .building: return BroopPalette.textBody
            case .calibrating: return BroopPalette.warning
            }
        }()
        BroopFinalAChip(text: ChargeBreakdownFormat.tierTag(confidence), tint: tint)
            .accessibilityLabel(Text(verbatim: {
                switch confidence {
                case .calibrating: return String(localized: "Confidence: calibrating")
                case .building: return String(localized: "Confidence: estimate")
                case .solid: return String(localized: "Confidence: reliable")
                }
            }()))
    }
}

/// A bar centred on zero: positive fills right, negative fills left, on a flat track.
struct BroopFinalADivergingBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let w = max(2, half * CGFloat(min(1, abs(fraction))))
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track)
                Rectangle().fill(color)
                    .frame(width: w, height: height)
                    .offset(x: fraction >= 0 ? half : half - w)
                Rectangle().fill(BroopPalette.textSecondary).frame(width: 1.5, height: height + 6).offset(x: half - 0.75)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 6)
    }
}
#endif
