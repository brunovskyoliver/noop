import SwiftUI

/// Broop design tokens. Every view reads colour, type and spacing from here.
/// Values were measured from reference screenshots of the WHOOP app (see README).
enum Broop {
    enum Palette {
        // Canvas: slate at the top fading to near-black by the middle of the screen.
        static let bgTop = Color(hex: 0x283339)
        static let bgMid = Color(hex: 0x13181C)
        static let bgBottom = Color(hex: 0x0D1114)

        static let card = Color(hex: 0x272B2E)
        static let tile = Color(hex: 0x2B2F32)
        static let cardPeek = Color(hex: 0x191E21)
        static let row = Color(hex: 0x3E4245)
        static let pillOuter = Color(hex: 0x30373F)
        static let pillInner = Color(hex: 0x464A4D)
        static let track = Color(hex: 0x2E353B)
        static let hairline = Color.white.opacity(0.07)

        static let textPrimary = Color.white
        static let textBody = Color(hex: 0xBABEC0)
        static let textSecondary = Color(hex: 0x8F959A)
        static let textTertiary = Color(hex: 0x5E666B)

        // Charge bands (67 / 34 split).
        static let bandHigh = Color(hex: 0x16EC06)
        static let bandMid = Color(hex: 0xFFDE00)
        static let bandLow = Color(hex: 0xFF0026)

        static let effort = Color(hex: 0x0093E7)
        static let rest = Color(hex: 0x7BA1BB)
        /// Highlights, "sleep needed", positive deviations.
        static let teal = Color(hex: 0x5FEBA5)
        static let warning = Color(hex: 0xF5A623)

        static let outlookStart = Color(hex: 0x6F675F)
        static let outlookEnd = Color(hex: 0x2D3E4A)
        static let outlookChevron = Color(hex: 0xE8C27A)
        static let avatarStart = Color(hex: 0x1FB4D1)
        static let avatarEnd = Color(hex: 0x7EE8C0)

        static let stageAwake = Color(hex: 0xE4E8EB)
        static let stageREM = Color(hex: 0xB6CCDD)
        static let stageLight = Color(hex: 0x7BA1BB)
        static let stageDeep = Color(hex: 0x42627F)

        static func band(_ charge: Double) -> Color {
            charge >= 67 ? bandHigh : (charge >= 34 ? bandMid : bandLow)
        }
    }

    /// DIN Alternate and Avenir Next ship with iOS, so no font files are bundled.
    enum Typeface {
        static func number(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size) }
        static func caps(_ size: CGFloat) -> Font { .custom("AvenirNext-Bold", size: size) }
        static func demi(_ size: CGFloat) -> Font { .custom("AvenirNext-DemiBold", size: size) }
        static func medium(_ size: CGFloat) -> Font { .custom("AvenirNext-Medium", size: size) }
        static func regular(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
        static func wordmark(_ size: CGFloat) -> Font { .custom("AvenirNext-Regular", size: size) }
    }

    enum Space {
        static let page: CGFloat = 16
        static let gap: CGFloat = 10
        static let section: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12
        static let row: CGFloat = 10
        static let badge: CGFloat = 5
    }
}

extension View {
    /// WHOOP's numerals have ~25% thicker stems and ~10% wider set than DIN Alternate Bold at the
    /// same cap height (measured). Two hard zero-radius shadows thicken without blurring.
    func numeral(_ size: CGFloat, color: Color = Broop.Palette.textPrimary) -> some View {
        let w = size * 0.012
        return self
            .tracking(size * 0.03)
            .shadow(color: color, radius: 0, x: w, y: 0)
            .shadow(color: color, radius: 0, x: -w, y: 0)
    }

    /// Solid backdrop behind the status bar so scrolled content does not collide with it.
    func statusBarScrim() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0)
                .background(Broop.Palette.bgTop.ignoresSafeArea(edges: .top))
        }
    }
}

struct BroopBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Broop.Palette.bgTop, location: 0),
                .init(color: Broop.Palette.bgMid, location: 0.5),
                .init(color: Broop.Palette.bgBottom, location: 0.85),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum ScoreKind: String, CaseIterable, Identifiable, Hashable {
    case rest, charge, effort

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var domain: ClosedRange<Double> { self == .effort ? 0...21 : 0...100 }
    var unit: String { self == .effort ? "" : "%" }
    var axisTicks: [Double] { self == .effort ? [0, 7, 14, 21] : [0, 34, 67, 100] }

    func value(_ day: DayMetrics) -> Double {
        switch self {
        case .rest: return day.rest
        case .charge: return day.charge
        case .effort: return day.effort
        }
    }

    func color(for value: Double) -> Color {
        switch self {
        case .rest: return Broop.Palette.rest
        case .charge: return Broop.Palette.band(value)
        case .effort: return Broop.Palette.effort
        }
    }

    func format(_ value: Double) -> String {
        self == .effort ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}

enum Fmt {
    static func whole(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
    static func one(_ v: Double) -> String { String(format: "%.1f", v) }
    static func signed(_ v: Double) -> String { String(format: "%+.1f", v) }
    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
