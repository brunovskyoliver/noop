#if os(iOS)
import SwiftUI

// Broop design system: tokens and building blocks for the Broop iOS interface. Sizes, weights and
// colours were measured from reference screenshots at 3 px/pt (see Prototype/Broop/README.md).
// Everything here is presentation only; the data comes in through `BroopModel`.

enum BroopPalette {
    // Canvas: slate at the top fading to near-black.
    static let bgTop = Color(broopHex: 0x283339)
    static let bgMid = Color(broopHex: 0x13181C)
    static let bgBottom = Color(broopHex: 0x0D1114)

    static let card = Color(broopHex: 0x272B2E)
    static let tile = Color(broopHex: 0x2B2F32)
    static let row = Color(broopHex: 0x3E4245)
    static let pillOuter = Color(broopHex: 0x30373F)
    static let pillInner = Color(broopHex: 0x464A4D)
    static let track = Color(broopHex: 0x2E353B)
    static let hairline = Color.white.opacity(0.07)

    static let textPrimary = Color.white
    static let textBody = Color(broopHex: 0xBABEC0)
    static let textSecondary = Color(broopHex: 0x8F959A)
    static let textTertiary = Color(broopHex: 0x5E666B)

    // Charge bands (67 / 34 split).
    static let bandHigh = Color(broopHex: 0x16EC06)
    static let bandMid = Color(broopHex: 0xFFDE00)
    static let bandLow = Color(broopHex: 0xFF0026)

    static let effort = Color(broopHex: 0x0093E7)
    static let rest = Color(broopHex: 0x7BA1BB)
    static let teal = Color(broopHex: 0x5FEBA5)
    static let connected = Color(broopHex: 0x1DE9A0)
    static let warning = Color(broopHex: 0xF5A623)

    static let avatarStart = Color(broopHex: 0x1FB4D1)
    static let avatarEnd = Color(broopHex: 0x7EE8C0)

    static let stageAwake = Color(broopHex: 0xE4E8EB)
    static let stageREM = Color(broopHex: 0xB6CCDD)
    static let stageLight = Color(broopHex: 0x7BA1BB)
    static let stageDeep = Color(broopHex: 0x42627F)

    static func band(_ charge: Double) -> Color {
        charge >= 67 ? bandHigh : (charge >= 34 ? bandMid : bandLow)
    }
}

/// DIN Alternate and Avenir Next ship with iOS, so no font files are bundled.
enum BroopType {
    static func number(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size) }
    static func caps(_ size: CGFloat) -> Font { .custom("AvenirNext-Bold", size: size) }
    static func demi(_ size: CGFloat) -> Font { .custom("AvenirNext-DemiBold", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("AvenirNext-Medium", size: size) }
    static func regular(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
    static func wordmark(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
}

enum BroopMetrics {
    static let page: CGFloat = 16
    static let gap: CGFloat = 10
    static let section: CGFloat = 32
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10
    static let badgeRadius: CGFloat = 5
}

extension Color {
    init(broopHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct BroopBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: BroopPalette.bgTop, location: 0),
                .init(color: BroopPalette.bgMid, location: 0.5),
                .init(color: BroopPalette.bgBottom, location: 0.85),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// The reference numerals have ~25% thicker stems and a ~10% wider set than DIN Alternate Bold at
    /// the same cap height (measured). Two hard zero-radius shadows thicken without blurring.
    func broopNumeral(_ size: CGFloat, color: Color = BroopPalette.textPrimary) -> some View {
        let w = size * 0.012
        return self
            .tracking(size * 0.03)
            .shadow(color: color, radius: 0, x: w, y: 0)
            .shadow(color: color, radius: 0, x: -w, y: 0)
    }

    /// Solid backdrop behind the status bar so scrolled content does not collide with it.
    func broopStatusBarScrim() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
                .background(BroopPalette.bgTop.ignoresSafeArea(edges: .top))
        }
    }
}

enum BroopFormat {
    static func whole(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
    static func one(_ v: Double) -> String { String(format: "%.1f", v) }
    static func signed(_ v: Double) -> String { String(format: "%+.1f", v) }
    static func duration(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

// MARK: - Scores

enum BroopScore: String, CaseIterable, Identifiable, Hashable {
    case rest, charge, effort

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rest: return String(localized: "Rest")
        case .charge: return String(localized: "Charge")
        case .effort: return String(localized: "Effort")
        }
    }
    var domain: ClosedRange<Double> { self == .effort ? 0...21 : 0...100 }
    var unit: String { self == .effort ? "" : "%" }
    var axisTicks: [Double] { self == .effort ? [0, 7, 14, 21] : [0, 34, 67, 100] }

    func color(for value: Double) -> Color {
        switch self {
        case .rest: return BroopPalette.rest
        case .charge: return BroopPalette.band(value)
        case .effort: return BroopPalette.effort
        }
    }

    func format(_ value: Double) -> String {
        self == .effort ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}

/// One metric measured against the wearer's own baseline.
struct BroopReading: Identifiable {
    enum Better { case higher, lower, neutral }
    enum Status { case typical, above, below }

    let name: String
    let value: Double
    let unit: String
    let typical: ClosedRange<Double>
    let baseline: Double
    let better: Better
    let format: (Double) -> String

    var id: String { name }
    var text: String { format(value) }

    var status: Status {
        if value > typical.upperBound { return .above }
        if value < typical.lowerBound { return .below }
        return .typical
    }

    /// Scale for the range bar: wide enough for the band and the reading.
    var domain: ClosedRange<Double> {
        let half = max((typical.upperBound - typical.lowerBound) * 1.5, abs(value - baseline) * 1.3, 0.1)
        return (baseline - half)...(baseline + half)
    }

    var tint: Color {
        switch (status, better) {
        case (.typical, _): return BroopPalette.textTertiary
        case (.above, .higher), (.below, .lower): return BroopPalette.teal
        default: return BroopPalette.warning
        }
    }

    var trendSymbol: String? {
        if abs(value - baseline) < max((typical.upperBound - typical.lowerBound) * 0.08, 0.0001) { return nil }
        return value > baseline ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    var trendTint: Color {
        switch better {
        case .neutral: return BroopPalette.textTertiary
        case .higher: return value >= baseline ? BroopPalette.teal : BroopPalette.warning
        case .lower: return value <= baseline ? BroopPalette.teal : BroopPalette.warning
        }
    }
}

// MARK: - Brand

/// The Broop "B": a heavy upright letter with chamfered bowls, on a 100×100 grid.
struct BroopMark: Shape {
    private static let outer: [CGPoint] = [
        .init(x: 24, y: 14), .init(x: 62, y: 14), .init(x: 74, y: 26), .init(x: 74, y: 40),
        .init(x: 67, y: 49), .init(x: 78, y: 60), .init(x: 78, y: 74), .init(x: 66, y: 86),
        .init(x: 24, y: 86),
    ]
    private static let upperCounter: [CGPoint] = [
        .init(x: 40, y: 28), .init(x: 56, y: 28), .init(x: 58, y: 30), .init(x: 58, y: 38),
        .init(x: 54, y: 42), .init(x: 40, y: 42),
    ]
    private static let lowerCounter: [CGPoint] = [
        .init(x: 40, y: 56), .init(x: 58, y: 56), .init(x: 62, y: 60), .init(x: 62, y: 69),
        .init(x: 59, y: 72), .init(x: 40, y: 72),
    ]

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let ox = rect.midX - 51 * s
        let oy = rect.midY - 50 * s
        var path = Path()
        for poly in [Self.outer, Self.upperCounter, Self.lowerCounter] {
            path.addLines(poly.map { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) })
            path.closeSubpath()
        }
        return path
    }
}

struct BroopWordmark: View {
    var size: CGFloat = 17
    var body: some View {
        Text(verbatim: "BROOP")
            .font(BroopType.wordmark(size))
            .tracking(size * 0.24)
            .foregroundStyle(BroopPalette.textPrimary)
            .accessibilityHidden(true)
    }
}

/// The "B" inside a thin ring: the Coach entry point and the insight bullet.
struct BroopBadge: View {
    var size: CGFloat = 30
    var gradientRing = false

    var body: some View {
        ZStack {
            if gradientRing {
                Circle().stroke(
                    AngularGradient(colors: [Color(broopHex: 0x6A7BFF), Color(broopHex: 0xB07CFF), Color(broopHex: 0x5AD8FF), Color(broopHex: 0x6A7BFF)], center: .center),
                    lineWidth: size * 0.07
                )
            } else {
                Circle().stroke(BroopPalette.textPrimary.opacity(0.85), lineWidth: 1.4)
            }
            BroopMark()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Type

/// Uppercase, bold, tracked label.
struct BroopCaps: View {
    let text: String
    var size: CGFloat
    var color: Color

    init(_ text: String, size: CGFloat = 10.5, color: Color = BroopPalette.textPrimary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(BroopType.caps(size))
            .tracking(size * 0.11)
            .foregroundStyle(color)
    }
}

/// Sentence-case section title ("My Day").
struct BroopSectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: text)
                .font(BroopType.demi(20))
                .foregroundStyle(BroopPalette.textPrimary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension BroopSectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

/// Small grey header row above a list: "SLEEP STATISTICS · VS. PREVIOUS 30 DAYS".
struct BroopListHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
            Spacer()
            if let trailing { BroopCaps(trailing, size: 10, color: BroopPalette.textSecondary) }
        }
    }
}

/// Centred uppercase page title ("HEALTH MONITOR").
struct BroopPageHeader: View {
    let text: String
    var body: some View {
        BroopCaps(text, size: 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.top, 4)
    }
}

// MARK: - Surfaces

struct BroopCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous)
                    .fill(BroopPalette.card)
            )
    }
}

struct BroopHairline: View {
    var body: some View {
        Rectangle().fill(BroopPalette.hairline).frame(height: 1)
    }
}

struct BroopPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Dials and readings

/// Thin flat-ended ring with the score inside. A missing score shows an empty track and a dash.
struct BroopDial: View {
    let score: BroopScore
    let value: Double?
    /// Top of the scale: 100, or 21 for Effort on the WHOOP-style scale.
    var maxValue: Double = 100
    var diameter: CGFloat = 82
    var lineWidth: CGFloat = 5.3
    var marker: Double? = nil
    @State private var shown: Double = 0

    private func fraction(_ v: Double?) -> Double {
        guard let v, maxValue > 0 else { return 0 }
        return min(max(v / maxValue, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle().stroke(BroopPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(score.color(for: value ?? 0), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if let marker {
                Rectangle()
                    .fill(BroopPalette.textPrimary)
                    .frame(width: 2, height: lineWidth + 2)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(360 * fraction(marker)))
            }
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(verbatim: value.map(score.format) ?? "–")
                    .font(BroopType.number(diameter * 0.33))
                if value != nil && !score.unit.isEmpty {
                    Text(verbatim: score.unit).font(BroopType.number(diameter * 0.24))
                }
            }
            .foregroundStyle(value == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
            .broopNumeral(diameter * 0.33, color: value == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = fraction(value) } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.4)) { shown = fraction(v) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(score.title) \(value.map(score.format) ?? "–")\(score.unit)"))
    }
}

/// A typical-range band with the reading as a dot.
struct BroopRangeBar: View {
    let reading: BroopReading

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = x(reading.typical.lowerBound, w)
            let hi = x(reading.typical.upperBound, w)
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track).frame(height: 3)
                Capsule().fill(BroopPalette.textSecondary).frame(width: max(6, hi - lo), height: 3).offset(x: lo)
                Circle()
                    .fill(reading.status == .typical ? BroopPalette.textPrimary : reading.tint)
                    .frame(width: 9, height: 9)
                    .offset(x: x(reading.value, w) - 4.5)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
    }

    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        let d = reading.domain
        let t = (min(max(v, d.lowerBound), d.upperBound) - d.lowerBound) / (d.upperBound - d.lowerBound)
        return CGFloat(t) * width
    }
}

/// "▲ 12%" in a small grey box.
struct BroopDeltaPill: View {
    let reading: BroopReading

    var body: some View {
        let base = reading.baseline
        let pct = base == 0 ? 0 : (reading.value - base) / abs(base) * 100
        HStack(spacing: 4) {
            if abs(pct) >= 0.5 {
                Image(systemName: pct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
            }
            Text(verbatim: "\(BroopFormat.whole(abs(pct)))%").font(BroopType.number(12))
        }
        .foregroundStyle(reading.trendSymbol == nil ? BroopPalette.textSecondary : reading.trendTint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(BroopPalette.row))
    }
}

/// One statistic against its baseline: name, today, baseline average.
struct BroopStatRow: View {
    let reading: BroopReading

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: reading.name)
                .font(BroopType.medium(14))
                .foregroundStyle(BroopPalette.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: reading.text).font(BroopType.number(19))
                if !reading.unit.isEmpty {
                    Text(verbatim: reading.unit).font(BroopType.number(11)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .foregroundStyle(BroopPalette.textPrimary)
            Image(systemName: reading.trendSymbol ?? "minus")
                .font(.system(size: 8))
                .foregroundStyle(reading.trendSymbol == nil ? BroopPalette.textTertiary : reading.trendTint)
                .frame(width: 10)
            Text(verbatim: reading.format(reading.baseline))
                .font(BroopType.number(15))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }
}

/// A vital on its own tile, with the typical-range bar underneath.
struct BroopVitalTile: View {
    let reading: BroopReading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BroopCaps(reading.name, size: 10.5)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: reading.text).font(BroopType.number(19))
                    if !reading.unit.isEmpty {
                        Text(verbatim: reading.unit).font(BroopType.number(11)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .foregroundStyle(BroopPalette.textPrimary)
                Image(systemName: reading.status == .typical ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(reading.status == .typical ? BroopPalette.textPrimary : BroopPalette.bgBottom)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(reading.status == .typical ? BroopPalette.pillInner : reading.tint))
            }
            BroopRangeBar(reading: reading)
            Text(verbatim: String(localized: "Typical") + " \(reading.format(reading.typical.lowerBound)) – \(reading.format(reading.typical.upperBound)) \(reading.unit)")
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
    }
}

// MARK: - Header controls

/// Two-tone capsule: chevrons on the outer track, the day on a lighter inner pill.
struct BroopDateNavigator: View {
    let label: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").frame(width: 38, height: 28)
            }
            .opacity(canGoBack ? 1 : 0.3)
            .disabled(!canGoBack)
            .accessibilityLabel(Text("Previous day"))

            Button(action: onToday) {
                Text(verbatim: label.uppercased())
                    .font(BroopType.caps(10.5))
                    .tracking(1.2)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 82, minHeight: 28)
                    .background(Capsule().fill(BroopPalette.pillInner))
            }

            Button(action: onForward) {
                Image(systemName: "chevron.right").frame(width: 38, height: 28)
            }
            .opacity(canGoForward ? 1 : 0.3)
            .disabled(!canGoForward)
            .accessibilityLabel(Text("Next day"))
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(BroopPalette.textPrimary)
        .background(Capsule().fill(BroopPalette.pillOuter))
        .buttonStyle(.plain)
    }
}

struct BroopAvatar: View {
    var initials: String
    var body: some View {
        Text(verbatim: initials)
            .font(BroopType.medium(13))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: 32, height: 32)
            .background(Circle().fill(LinearGradient(colors: [BroopPalette.avatarStart, BroopPalette.avatarEnd], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// Strap battery: grey percentage plus a side-view wrist strap with a connection dot.
struct BroopStrapStatus: View {
    let level: Int?
    let connected: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let level {
                Text(verbatim: "\(level)%")
                    .font(BroopType.number(14))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .broopNumeral(14, color: BroopPalette.textSecondary)
            }
            ZStack(alignment: .topLeading) {
                BroopStrapGlyph()
                    .stroke(BroopPalette.textPrimary, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 23.5)
                Circle()
                    .fill(connected ? BroopPalette.connected : BroopPalette.textTertiary)
                    .frame(width: 6, height: 6)
                    .offset(x: 14, y: 3)
            }
            .frame(width: 20.5, height: 23.5, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: level.map { String(localized: "Strap battery") + " \($0)%" } ?? String(localized: "Strap")))
    }
}

/// A band seen from the side on an 18 × 23.5 pt grid: flat top with a sharp corner, the body's inner
/// edge running down from it, a stepped left edge, and the strap tail forming the outer right side.
struct BroopStrapGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18, sy = rect.height / 23.5
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(17.4, 12))
        path.addLine(to: p(17.2, 17.5))
        path.addQuadCurve(to: p(12.8, 23), control: p(17, 23))
        path.addLine(to: p(4.6, 23))
        path.addLine(to: p(1.3, 18.1))
        path.addLine(to: p(0.4, 17.5))
        path.addLine(to: p(0.2, 11))
        path.addQuadCurve(to: p(5, 0.7), control: p(0.4, 1))
        path.addLine(to: p(14.2, 0.6))
        path.addLine(to: p(12, 3.8))
        path.addQuadCurve(to: p(10.5, 9), control: p(10.6, 5.8))
        path.addLine(to: p(10.4, 17.4))
        path.addLine(to: p(9.7, 18.3))
        path.addLine(to: p(10.5, 20.8))
        path.move(to: p(2.6, 16.2))
        path.addLine(to: p(8.4, 16.2))
        return path
    }
}

/// Underlined text tabs.
struct BroopUnderlineTabs<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var size: CGFloat = 11
    let label: (Option) -> String
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    VStack(spacing: 7) {
                        BroopCaps(label(option), size: size, color: on ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if on {
                                Rectangle().fill(BroopPalette.textPrimary).frame(width: 28, height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tiles and rows

/// Half-width tile: stacked caps title with a chevron, then a status badge beside tight status lines.
struct BroopMonitorTile<Badge: View>: View {
    let title: [String]
    let status: [String]
    let statusColor: Color
    let detail: String
    @ViewBuilder var badge: Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                lines(title, color: BroopPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .offset(y: 1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 10) {
                badge
                VStack(alignment: .leading, spacing: 0) {
                    lines(status, color: statusColor)
                    Text(verbatim: detail)
                        .font(BroopType.demi(12.5))
                        .foregroundStyle(BroopPalette.textBody)
                        .lineLimit(1)
                        .frame(height: 15, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.tile))
    }

    /// Caps lines on a fixed 14 pt pitch; Avenir's default leading is looser than the reference's.
    private func lines(_ text: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(text, id: \.self) { BroopCaps($0, color: color).frame(height: 14, alignment: .leading) }
        }
    }
}

/// Solid colour badge (icon + value), uppercase name, start/end times and a timeline tick.
struct BroopActivityRow: View {
    let symbol: String
    let value: String
    let color: Color
    let name: String
    let start: Date
    let end: Date

    var body: some View {
        HStack(spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(verbatim: value).font(BroopType.number(17)).broopNumeral(17)
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(width: 94, height: 36)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.badgeRadius, style: .continuous).fill(color))

            BroopCaps(name, size: 12).lineLimit(2)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: BroopFormat.time(start))
                Text(verbatim: BroopFormat.time(end))
            }
            .font(BroopType.demi(12))
            .foregroundStyle(BroopPalette.textBody)
            VStack(spacing: 0) {
                Circle().fill(BroopPalette.textPrimary).frame(width: 2.5, height: 2.5)
                Rectangle().fill(color).frame(width: 2)
                Circle().fill(BroopPalette.textPrimary).frame(width: 2.5, height: 2.5)
            }
            .frame(height: 28)
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
    }
}

struct BroopDashboardRow: View {
    let reading: BroopReading

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(reading.name, size: 10, color: BroopPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: reading.text).font(BroopType.number(20)).broopNumeral(20)
                    if !reading.unit.isEmpty {
                        BroopCaps(reading.unit, size: 9, color: BroopPalette.textSecondary)
                    }
                }
                .foregroundStyle(BroopPalette.textPrimary)
            }
            Spacer()
            BroopDeltaPill(reading: reading)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BroopPalette.textTertiary)
        }
        .padding(.vertical, 11)
    }
}

/// A navigation row on its own tile (More / Health lists).
struct BroopNavTile: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 26)
            BroopCaps(title, size: 11)
            Spacer()
            if let detail {
                Text(verbatim: detail)
                    .font(BroopType.demi(12))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
        .contentShape(Rectangle())
    }
}
#endif
