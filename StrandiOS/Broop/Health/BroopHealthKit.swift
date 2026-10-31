#if os(iOS)
import SwiftUI
import StrandDesign

// Shared building blocks for the Broop Health group (Health tab, Health Monitor, Stress, trends, Lab Book,
// Rhythm, Hydration, Compare). Presentation only: every number these draw is handed in by a screen that
// read it through the same Repository / engine path its counterpart uses.

/// Colours sampled from the WHOOP Health, Stress and Trend View references (notes C and D).
enum BroopHealthPalette {
    /// "within" text and check glyphs.
    static let mint = Color(broopHex: 0x02F3A2)
    static let mintPill = Color(broopHex: 0x234B42)
    static let checkTile = Color(broopHex: 0x23473D)
    static let amber = Color(broopHex: 0xF3AB45)
    static let amberPill = Color(broopHex: 0x4A3A22)
    static let noDataPill = Color(broopHex: 0x45484D)

    static let vitalCard = Color(broopHex: 0x2D3135)
    static let innerPanel = Color(broopHex: 0x1D2124)
    static let dropdown = Color(broopHex: 0x353A40)
    static let segTrack = Color(broopHex: 0x151618)
    static let segSelected = Color(broopHex: 0x2C3136)
    static let grid = Color.white.opacity(0.07)
    static let typicalBand = Color.white.opacity(0.07)

    static let chartBlue = Color(broopHex: 0x4091E0)
    static let liveBlue = Color(broopHex: 0x0095E9)
    static let infoBanner = Color(broopHex: 0x1D2A36)
    static let infoText = Color(broopHex: 0x77AAE9)

    // Stress bands (bright = today, dim = reference).
    static let stressLow = Color(broopHex: 0x77AAE9)
    static let stressMedium = Color(broopHex: 0x6FEDA6)
    static let stressHigh = Color(broopHex: 0xF3AB45)

    // Delta chips.
    static let chipGoodText = Color(broopHex: 0x16E0A0)
    static let chipGoodFill = Color(broopHex: 0x173A30)
    static let chipBadText = Color(broopHex: 0xF5A623)
    static let chipBadFill = Color(broopHex: 0x3F3325)
    static let chipNeutralText = Color(broopHex: 0xC8CDD2)
    static let chipNeutralFill = Color(broopHex: 0x33383E)

    /// Heart-rate zones 1…5 (zone 0 is white).
    static func zone(_ zone: Int) -> Color {
        switch zone {
        case ...0: return .white
        case 1: return Color(broopHex: 0xAEC2CD)
        case 2: return Color(broopHex: 0x479AC2)
        case 3: return Color(broopHex: 0x7FBEA3)
        case 4: return Color(broopHex: 0xEFB164)
        default: return Color(broopHex: 0xED6E39)
        }
    }

    /// The stress ramp (blue → green → amber) sampled at a 0–3 level.
    static func stress(_ level: Double) -> Color {
        let t = min(max(level / 3, 0), 1)
        return StrandPalette.sample(stops: [
            .init(color: stressLow, location: 0),
            .init(color: stressMedium, location: 0.5),
            .init(color: stressHigh, location: 1),
        ], at: t)
    }
}

// MARK: - Screen chrome

/// Pinned header for a pushed Health screen: the shared `BroopNavHeader`.
struct BroopHealthHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsBack = true
    var fill: Color = BroopPalette.bgTop
    @ViewBuilder var trailing: Trailing

    var body: some View {
        BroopNavHeader(showsBack: showsBack, fill: fill,
                       center: { BroopNavTitle(title: title, subtitle: subtitle) },
                       trailing: { trailing })
    }
}

extension BroopHealthHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsBack: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsBack: showsBack) { EmptyView() }
    }
}

extension View {
    /// A pushed Health screen: Broop background, the system bar hidden (the header replaces it).
    func broopHealthScreen() -> some View {
        self
            .background(BroopBackground())
            .broopBarChrome()
            .tint(BroopPalette.textPrimary)
            .preferredColorScheme(.dark)
    }
}

/// A trailing icon for the header (gear, info): the shared `BroopNavIcon`.
struct BroopHealthHeaderIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View { BroopNavIcon(symbol: symbol, label: label, action: action) }
}

// MARK: - Controls

/// "W | M | 6M": a dark track with the selected segment on a lighter pill.
struct BroopHealthSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var isEnabled: (Option) -> Bool = { _ in true }
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                let enabled = isEnabled(option)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(verbatim: label(option).uppercased())
                        .font(BroopType.caps(12))
                        .tracking(0.8)
                        .foregroundStyle(on ? BroopPalette.textPrimary
                                         : (enabled ? BroopPalette.textSecondary : BroopPalette.textTertiary.opacity(0.6)))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(BroopHealthPalette.segSelected)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(BroopHealthPalette.segTrack))
    }
}

/// "‹ JUL 6 - AUG 4, 26 ›" with a dimmed forward arrow at the present.
struct BroopHealthDateNav: View {
    let label: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.3)
            .accessibilityLabel(Text("Previous"))
            Text(verbatim: label.uppercased())
                .font(BroopType.caps(12.5))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            Button(action: onForward) {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
            .accessibilityLabel(Text("Next"))
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .buttonStyle(.plain)
    }
}

/// "▼ 16% vs. prior month" on a tinted chip. `good` nil = neutral grey.
struct BroopHealthDeltaChip: View {
    let pct: Double
    let good: Bool?
    let suffix: String

    var body: some View {
        let up = pct >= 0
        let text: Color = good == nil ? BroopHealthPalette.chipNeutralText
            : (good! ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText)
        let fill: Color = good == nil ? BroopHealthPalette.chipNeutralFill
            : (good! ? BroopHealthPalette.chipGoodFill : BroopHealthPalette.chipBadFill)
        HStack(spacing: 5) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
            Text(verbatim: "\(BroopFormat.whole(abs(pct)))% \(suffix)")
                .font(BroopType.demi(13))
        }
        .foregroundStyle(text)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
    }
}

/// The small status chip under a vital: "✓ In your range", "! Off baseline", "• No data".
struct BroopHealthStatusPill: View {
    enum Tone { case good, warn, none }
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            switch tone {
            case .good: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            case .warn: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .heavy))
            case .none: Circle().fill(BroopPalette.textPrimary).frame(width: 5, height: 5)
            }
            Text(verbatim: text)
                .font(BroopType.demi(13))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(tone == .good ? BroopHealthPalette.mint
                         : (tone == .warn ? BroopHealthPalette.amber : BroopPalette.textPrimary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(
            tone == .good ? BroopHealthPalette.mintPill
                : (tone == .warn ? BroopHealthPalette.amberPill : BroopHealthPalette.noDataPill)))
    }
}

/// The square status tile of the Health Monitor strip: green check, amber "!", or a grey dash.
struct BroopHealthStatusSquare: View {
    let tone: BroopHealthStatusPill.Tone
    var size: CGFloat = 20
    var solid = false

    var body: some View {
        let glyph: String = tone == .good ? "checkmark" : (tone == .warn ? "exclamationmark" : "minus")
        let color: Color = tone == .good ? BroopHealthPalette.mint
            : (tone == .warn ? BroopHealthPalette.amber : BroopPalette.textSecondary)
        Image(systemName: glyph)
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(solid ? Color.black : color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(solid ? color : (tone == .good ? BroopHealthPalette.checkTile
                                       : (tone == .warn ? BroopHealthPalette.amberPill : BroopPalette.track))))
    }
}

// MARK: - Rows and cards

/// A full-width row card: outline icon, caps title, optional detail, chevron (WHOOP More / action rows).
struct BroopHealthRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var trailingSymbol = "chevron.right"

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(title, size: 12)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail)
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: trailingSymbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.tileRadius, style: .continuous).fill(BroopPalette.card))
        .contentShape(Rectangle())
    }
}

/// A My Dashboard row: icon + caps name at left, big value with a ▲/▼ and the 30-day baseline under it.
struct BroopHealthDashboardRow: View {
    let symbol: String
    let title: String
    let value: String?
    let baseline: String?
    /// +1 up, -1 down, 0 flat / unknown.
    let direction: Int
    /// nil = neutral metric (grey arrow).
    let good: Bool?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 28)
            BroopCaps(title, size: 12)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: value)
                        .font(BroopType.number(25))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .broopNumeral(25)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let baseline {
                        Text(verbatim: baseline)
                            .font(BroopType.number(13))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                arrow.frame(width: 12)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundStyle(BroopPalette.textPrimary)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.tileRadius, style: .continuous).fill(BroopPalette.card))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var arrow: some View {
        if direction == 0 {
            Color.clear.frame(width: 8, height: 8)
        } else {
            let color: Color = good == nil ? BroopPalette.textSecondary
                : (good! ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText)
            Image(systemName: direction > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)
        }
    }
}

/// Slate-blue information banner with a leading symbol (calibration, estimates).
struct BroopHealthInfoBanner: View {
    var symbol = "info.circle"
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BroopHealthPalette.infoText)
            Text(verbatim: text)
                .font(BroopType.medium(14))
                .foregroundStyle(BroopHealthPalette.infoText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopHealthPalette.infoBanner))
    }
}

/// Large sentence-case section heading ("Fitness", "Trend View").
struct BroopHealthHeading: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: text)
                .font(BroopType.demi(BroopType.sectionSize))
                .foregroundStyle(BroopPalette.textPrimary)
            Spacer()
            if let trailing { BroopCaps(trailing, size: 10, color: BroopPalette.textSecondary) }
        }
    }
}

/// Card title row: caps title, optional trailing caps link, optional chevron.
struct BroopHealthCardTitle: View {
    let title: String
    var trailing: String? = nil
    var chevron = true

    var body: some View {
        HStack(spacing: 8) {
            BroopCaps(title, size: 12.5)
            Spacer()
            if let trailing { BroopCaps(trailing, size: 10.5, color: BroopPalette.textSecondary) }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BroopPalette.textPrimary)
            }
        }
    }
}

/// White capsule with black caps (primary) or an outlined capsule (secondary).
struct BroopHealthButton: View {
    enum Kind { case primary, secondary }
    let title: String
    var symbol: String? = nil
    var kind: Kind = .primary
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                Text(verbatim: title.uppercased()).font(BroopType.caps(12.5)).tracking(1.3)
            }
            .foregroundStyle(kind == .primary ? Color.black : BroopPalette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if kind == .primary {
                    Capsule().fill(Color.white)
                } else {
                    Capsule().stroke(BroopPalette.textSecondary.opacity(0.7), lineWidth: 1.2)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// Grey fine print closing a screen.
struct BroopHealthFootnote: View {
    let text: String
    var body: some View { BroopFootnote(text: text) }
}

/// A plain surface card with WHOOP padding.
struct BroopHealthCard<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = BroopPalette.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(fill))
    }
}

/// Quiet empty state: centred symbol, caps title, grey sentence.
struct BroopHealthEmpty: View {
    var symbol = "chart.bar"
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(BroopPalette.textSecondary)
            BroopCaps(title, size: 11, color: BroopPalette.textSecondary)
            Text(verbatim: message)
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
    }
}

// MARK: - Formatting

enum BroopHealthFormat {
    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ day: String) -> Date? { dayParser.date(from: day) }
    static func day(_ date: Date) -> String { dayParser.string(from: date) }

    private static func utc(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }
    private static let monthDay = utc("MMMd")
    private static let monthDayYear = utc("MMMdyy")
    private static let weekdayMonthDay = utc("EEEMMMd")

    /// "Jul 6 - Aug 4, 26" (UTC day keys, the year on the end only).
    static func range(_ from: String, _ to: String) -> String {
        guard let a = date(from), let b = date(to) else { return "\(from) - \(to)" }
        return "\(monthDay.string(from: a)) - \(monthDayYear.string(from: b))"
    }

    /// "Sun, Sep 7".
    static func weekday(_ day: String) -> String {
        guard let d = date(day) else { return day }
        return weekdayMonthDay.string(from: d)
    }

    static func shortDay(_ day: String) -> String {
        guard let d = date(day) else { return day }
        return monthDay.string(from: d)
    }

    /// "h:mm" for a count of minutes.
    static func hm(_ minutes: Double) -> String { BroopFormat.duration(minutes) }
}
#endif
