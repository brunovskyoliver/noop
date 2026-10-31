#if os(iOS)
import SwiftUI

// Shared building blocks for the Insights group (Journal, Journal Insights, What Moves You, Intelligence,
// Fused Record, Coach and the Sleep Planner). Presentation only; every figure comes from the classic
// screens' own loaders and engines.

enum BroopInsightsPalette {
    /// Journal answer "yes" fill and the numeric value capsule.
    static let answerBlue = Color(broopHex: 0x5AA8E6)
    /// Unselected answer square on the dark canvas.
    static let answerIdle = Color.white.opacity(0.10)
    /// Coach gradient ends.
    static let coachPurple = Color(broopHex: 0x8A6CF0)
    static let coachCyan = Color(broopHex: 0x5AD0F0)
    static let userBubble = Color(broopHex: 0x35314A)
    /// Impact bar colours.
    static let helps = Color(broopHex: 0x3EE6A0)
    static let hurts = Color(broopHex: 0xF7A324)
    static let neutralBar = Color(broopHex: 0x9A9EA2)
    static let hatch = Color.white.opacity(0.13)
    /// Toggle "on" track (WHOOP teal).
    static let toggleOn = Color(broopHex: 0x00F1A0)
    /// Sleep planner lower band and bottom sheet.
    static let plannerLower = Color(broopHex: 0x0B0F12)
    static let plannerSheet = Color(broopHex: 0x333F47)
    static let plannerTile = Color(broopHex: 0x424D54)
    static let plannerRange = Color(broopHex: 0x7F9CB3)
    static let alarmRed = Color(broopHex: 0xE4082A)
    static let cardRaised = Color(broopHex: 0x2F3438)
}

// MARK: - Chrome

extension View {
    /// The shared pinned header with a centred caps title ("JOURNAL", "SLEEP PLANNER"). `fill` matches
    /// the top of the screen's own background.
    func broopInsightsChrome<Trailing: View>(_ title: String, fill: Color = BroopPalette.bgTop,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        broopNavPage(header: BroopNavHeader(fill: fill, center: { BroopNavTitle(title: title) }, trailing: trailing))
    }

    func broopInsightsChrome(_ title: String, fill: Color = BroopPalette.bgTop) -> some View {
        broopInsightsChrome(title, fill: fill) { EmptyView() }
    }
}

/// Caps grey label followed by a hairline that runs to the edge ("DAYTIME ———————").
struct BroopInsightsSectionRule: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            BroopCaps(title, size: 11, color: BroopPalette.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            if let trailing {
                BroopCaps(trailing, size: 10, color: BroopPalette.textTertiary).lineLimit(1)
            }
        }
    }
}

/// Large sentence-case heading used inside pages ("What moves your Charge").
struct BroopInsightsHeadline: View {
    let text: String
    var size: CGFloat = 24

    var body: some View {
        Text(verbatim: text)
            .font(BroopType.demi(size))
            .foregroundStyle(BroopPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Grey body paragraph.
struct BroopInsightsBody: View {
    let text: String
    var size: CGFloat = 14
    var color: Color = BroopPalette.textBody

    var body: some View {
        Text(verbatim: text)
            .font(BroopType.regular(size))
            .foregroundStyle(color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A flat dark card with the page radius.
struct BroopInsightsCard<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = BroopPalette.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(fill))
    }
}

/// An honest note: small outline icon, a title and a paragraph.
struct BroopInsightsNote: View {
    let symbol: String
    var tint: Color = BroopPalette.textSecondary
    let title: String?
    let text: String

    var body: some View {
        BroopInsightsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(verbatim: title)
                            .font(BroopType.demi(15))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    BroopInsightsBody(text: text, size: 13, color: BroopPalette.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// Full-width white capsule with black caps ("SAVE & SET ALARM").
struct BroopInsightsPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                BroopCaps(title, size: 12, color: .black)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(Color.white))
            .contentShape(Capsule())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// Full-width outlined capsule with white caps.
struct BroopInsightsOutlineButton: View {
    let title: String
    var symbol: String? = nil
    var color: Color = BroopPalette.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(color) }
                BroopCaps(title, size: 12, color: color)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.6))
            .contentShape(Capsule())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// Small rounded pill button with caps text ("INSIGHTS", "TODAY").
struct BroopInsightsPill: View {
    let title: String
    var symbol: String? = nil
    var fill: Color = Color.white.opacity(0.12)
    var stroke: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            BroopCaps(title, size: 10.5)
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(fill))
        .overlay { if let stroke { Capsule().strokeBorder(stroke, lineWidth: 1.2) } }
    }
}

/// The WHOOP-style switch: teal track when on.
struct BroopInsightsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? BroopInsightsPalette.toggleOn : Color.white.opacity(0.18))
                        .frame(width: 50, height: 30)
                    Circle().fill(Color.white).frame(width: 26, height: 26).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

// MARK: - Impact bar

/// Diagonal stripes, the WHOOP "no data here" track texture.
struct BroopInsightsHatch: Shape {
    var spacing: CGFloat = 7
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return p
    }
}

/// A diverging bar centred on zero: a hatched track, a fill left (hurts) or right (helps), and a dark
/// ring marker at zero. `fraction` is signed, −1…1 of the half-width.
struct BroopInsightsImpactBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let half = w / 2
            let mag = CGFloat(min(abs(fraction), 1)) * (half - height / 2)
            ZStack(alignment: .leading) {
                BroopInsightsHatch()
                    .stroke(BroopInsightsPalette.hatch, lineWidth: 2.2)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                if mag > 0.5 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: mag + height / 2, height: height * 0.72)
                        .offset(x: fraction >= 0 ? half : half - mag - height / 2)
                }
                ZStack {
                    Circle().fill(Color(broopHex: 0x101315))
                    Circle().fill(Color.white).frame(width: height * 0.36, height: height * 0.36)
                }
                .frame(width: height * 1.9, height: height * 1.9)
                .offset(x: half - height * 0.95)
            }
        }
        .frame(height: height * 1.9)
        .accessibilityHidden(true)
    }
}

/// "▼ HURTS | % IMPACT | HELPS ▲" legend above an impact list.
struct BroopInsightsImpactLegend: View {
    var center: String = String(localized: "% impact")

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
                    .foregroundStyle(BroopInsightsPalette.hurts)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(broopHex: 0x3B3424)))
                BroopCaps(String(localized: "Hurts"), size: 10, color: BroopPalette.textSecondary)
            }
            Spacer()
            BroopCaps(center, size: 10)
            Spacer()
            HStack(spacing: 6) {
                BroopCaps(String(localized: "Helps"), size: 10, color: BroopInsightsPalette.helps)
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 7))
                    .foregroundStyle(BroopInsightsPalette.helps)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(broopHex: 0x15443A)))
            }
        }
    }
}

/// A tinted status chip ("POSITIVE IMPACT", "SOLID").
struct BroopInsightsChip: View {
    let text: String
    let color: Color

    var body: some View {
        BroopCaps(text, size: 9.5, color: color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.16)))
    }
}

// MARK: - Inputs

/// Dark rounded text-field surface.
struct BroopInsightsFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BroopType.medium(15))
            .foregroundStyle(BroopPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

extension View {
    func broopInsightsField() -> some View { modifier(BroopInsightsFieldSurface()) }
}

// MARK: - hosting

/// A card kept as-is (under the launch-time skin) inside a Broop page. Used only for niche
/// sub-features, each reached from a clearly labelled row.
struct BroopInsightsHostedPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
                .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .broopInsightsChrome(title)
    }
}

/// A row that opens a sub-page: caps title, grey detail line, chevron.
struct BroopInsightsLinkRow: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(title, size: 11.5)
                if let detail {
                    Text(verbatim: detail)
                        .font(BroopType.regular(12.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        .contentShape(Rectangle())
    }
}

enum BroopInsightsFormat {
    /// "+24%" / "−9%": the signed percent the impact list shows.
    static func signedPercent(_ v: Double) -> String {
        let r = Int(v.rounded())
        if r > 0 { return "+\(r)%" }
        if r < 0 { return "−\(abs(r))%" }
        return "0%"
    }

    static func magnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2: return String(localized: "negligible")
        case ..<0.5: return String(localized: "small")
        case ..<0.8: return String(localized: "moderate")
        default: return String(localized: "large")
        }
    }
}
#endif
