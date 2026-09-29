#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// Shared building blocks for the Activity group (workouts, live heart rate, strength, breathing,
// intervals). Presentation only: every number comes from the same models the classic screens read.

/// Colours this group needs that the shared Broop palette does not carry: WHOOP's heart-rate zone set
/// (bright for bars and labels, muted for the inactive live zone bar) and the mint of Strength Trainer.
enum BroopActivityPalette {
    static let mint = Color(broopHex: 0x16E6A0)
    static let mintTint = Color(broopHex: 0x1F3A32)
    static let strainBlue = Color(broopHex: 0x1A8CE8)
    static let startBlue = Color(broopHex: 0x0A8AE6)
    static let liveBand = Color(broopHex: 0x2FA0E6)
    static let chip = Color(broopHex: 0x33383E)
    static let input = Color(broopHex: 0x15191D)
    static let inputBorder = Color(broopHex: 0x3A4046)
    static let hatch = Color(broopHex: 0x3A3F45)
    static let popover = Color(broopHex: 0x3E454D)
    static let rest = Color(broopHex: 0x8A9096)

    /// Zone 0 (below Zone 1) through Zone 5, bright.
    static func zone(_ z: Int) -> Color {
        switch z {
        case 1: return Color(broopHex: 0xAEC2CD)
        case 2: return Color(broopHex: 0x479AC2)
        case 3: return Color(broopHex: 0x7FBEA3)
        case 4: return Color(broopHex: 0xEFB164)
        case 5: return Color(broopHex: 0xED6E39)
        default: return Color.white
        }
    }

    /// The dim tint an inactive segment of the live zone bar takes.
    static func zoneMuted(_ z: Int) -> Color {
        switch z {
        case 1: return Color(broopHex: 0x3A4148)
        case 2: return Color(broopHex: 0x243A4E)
        case 3: return Color(broopHex: 0x26443C)
        case 4: return Color(broopHex: 0x4A4238)
        case 5: return Color(broopHex: 0x4A2E26)
        default: return Color(broopHex: 0x3A4148)
        }
    }
}

enum BroopActivityFormat {
    /// "0:59:48": the activity-duration form.
    static func hms(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let t = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// "1h 5m" / "45m".
    static func shortDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let t = Int(seconds.rounded())
        let h = t / 3600, m = (t % 3600) / 60
        return h > 0 ? String(localized: "\(h)h \(m)m") : String(localized: "\(m)m")
    }

    static func grouped(_ v: Double) -> String { Int(v.rounded()).formatted() }

    static func time(_ ts: Int) -> String {
        AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// "11:19 AM to 12:19 PM", or the start alone when the row has no real end.
    static func span(_ start: Int, _ end: Int) -> String {
        end > start ? String(localized: "\(time(start)) to \(time(end))") : time(start)
    }

    static func dayLabel(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// The screen header WHOOP uses on pushed pages: back chevron, a centred caps title (optionally with a
/// grey subtitle), and an optional trailing control.
struct BroopActivityHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var leadingSymbol: String = "chevron.left"
    /// On a pushed page (in its top inset) the header rides the system bar; in a sheet it is a row.
    var inBar = false
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if inBar {
            BroopNavHeader(center: { BroopNavTitle(title: title, subtitle: subtitle) }, trailing: { trailing })
        } else {
            // The shared inline header; callers sit it in a padded sheet, so undo its own page padding.
            BroopNavHeader(fill: .clear, inline: true, onBack: onBack,
                           leadingSymbol: leadingSymbol == "chevron.left" ? nil : leadingSymbol,
                           center: { BroopNavTitle(title: title, subtitle: subtitle) },
                           trailing: { trailing })
                .padding(.horizontal, -BroopMetrics.page)
        }
    }
}

extension BroopActivityHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, leadingSymbol: String = "chevron.left", inBar: Bool = false,
         onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, leadingSymbol: leadingSymbol, inBar: inBar, onBack: onBack) { EmptyView() }
    }
}

/// Grey caps label followed by a hairline that fills the row ("MOST RECENT ————").
struct BroopActivityDivider: View {
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
            Rectangle().fill(BroopPalette.hairline).frame(height: 1)
        }
    }
}

/// Capsule call to action. `.filled` is the white primary, `.blue` the Start Activity pill, `.outline`
/// and `.mint` the Strength Trainer outlines.
struct BroopActivityButton: View {
    enum Kind { case filled, blue, outline, mint, grey, destructive }
    let title: String
    var symbol: String? = nil
    var kind: Kind = .filled
    var height: CGFloat = 52
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                Text(verbatim: title.uppercased())
                    .font(BroopType.caps(12))
                    .tracking(1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(BroopPressableStyle())
    }

    private var foreground: Color {
        switch kind {
        case .filled: return .black
        case .blue: return .white
        case .outline, .grey: return BroopPalette.textPrimary
        case .mint: return BroopActivityPalette.mint
        case .destructive: return BroopPalette.bandLow
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .filled: Capsule().fill(Color.white)
        case .blue: Capsule().fill(BroopActivityPalette.startBlue)
        case .outline: Capsule().strokeBorder(Color.white, lineWidth: 2)
        case .mint: Capsule().strokeBorder(BroopActivityPalette.mint, lineWidth: 2)
        case .grey: RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopActivityPalette.chip)
        case .destructive: Capsule().strokeBorder(BroopPalette.bandLow.opacity(0.8), lineWidth: 1.5)
        }
    }
}

/// Small rounded chip ("VIA APPLE HEALTH", "SUGGESTED").
struct BroopActivityChip: View {
    let text: String
    var symbol: String? = nil
    var color: Color = BroopPalette.textPrimary
    var fill: Color = Color(broopHex: 0x2E3440)

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            BroopCaps(text, size: 10, color: color)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}

/// Where a workout row came from, as WHOOP words an imported activity ("VIA APPLE HEALTH").
enum BroopActivitySource {
    static func label(_ source: String) -> String {
        switch WorkoutSource.classify(source) {
        case .whoop: return String(localized: "Via WHOOP import")
        case .apple: return String(localized: "Via Apple Health")
        case .detected: return String(localized: "Auto-detected")
        case .manual: return String(localized: "Logged on Broop")
        case .lifting: return String(localized: "Via lifting log")
        case .activityFile: return String(localized: "Via activity file")
        }
    }

    static func short(_ c: WorkoutSource) -> String {
        switch c {
        case .whoop: return String(localized: "Whoop")
        case .apple: return String(localized: "Apple")
        case .detected: return String(localized: "Detected")
        case .manual: return String(localized: "Manual")
        case .lifting: return String(localized: "Lifting")
        case .activityFile: return String(localized: "File")
        }
    }
}

/// The live six-segment zone bar (Zone 0 to Zone 5): the current zone lit with a knob at the exact
/// position, the others in their dim tints, labels underneath.
struct BroopActivityZoneBar: View {
    let bpm: Int?
    let zoneSet: HRZoneSet
    var showsLabels = true

    private var zone: Int { bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? -1 }

    /// Where inside its zone the reading sits, 0...1, for the knob.
    private var within: Double {
        guard let bpm, zone >= 0 else { return 0 }
        let lower: Double, upper: Double
        if zone == 0 {
            upper = zoneSet.zones.first?.lower ?? 100
            lower = max(30, upper - 40)
        } else if let z = zoneSet.zones.first(where: { $0.number == zone }) {
            lower = z.lower; upper = max(z.upper, z.lower + 1)
        } else { return 0 }
        return min(max((Double(bpm) - lower) / (upper - lower), 0.03), 0.97)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0...5, id: \.self) { z in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(z == zone ? BroopActivityPalette.zone(z) : BroopActivityPalette.zoneMuted(z))
                            if z == zone {
                                Circle().fill(Color.white)
                                    .frame(width: 13, height: 13)
                                    .shadow(color: .black.opacity(0.35), radius: 2)
                                    .offset(x: geo.size.width * within - 6.5)
                            }
                        }
                        .frame(height: 6)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 14)
                }
            }
            if showsLabels {
                HStack(spacing: 3) {
                    ForEach(0...5, id: \.self) { z in
                        Text(verbatim: String(localized: "Zone \(z)"))
                            .font(z == zone ? BroopType.number(15) : BroopType.number(14))
                            .foregroundStyle(z == zone ? BroopPalette.textPrimary : BroopActivityPalette.zone(z).opacity(0.35))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(zone >= 0 ? String(localized: "Heart rate zone \(zone)") : String(localized: "No heart rate")))
    }
}

/// The white pictogram-in-blue pill used by activity rows.
struct BroopActivityPill: View {
    let sport: String
    let value: String
    var color: Color = BroopActivityPalette.strainBlue
    var width: CGFloat = 94

    var body: some View {
        HStack(spacing: 8) {
            WorkoutTypeIcon(workoutType: sport, size: 17, weight: .semibold, color: .white)
            Text(verbatim: value).font(BroopType.number(17)).broopNumeral(17)
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .frame(width: width, height: 38)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.badgeRadius + 2, style: .continuous).fill(color))
    }
}

/// A key-statistic card (icon, caps label, big value with a small unit, optional caption chip).
struct BroopActivityStatCard: View {
    let symbol: String
    let title: String
    let value: String
    var unit: String? = nil
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BroopPalette.textSecondary)
                BroopCaps(title, size: 10.5, color: BroopPalette.textBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).font(BroopType.number(30)).broopNumeral(30)
                    .foregroundStyle(value == "–" ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                if let unit, value != "–" {
                    Text(verbatim: unit).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let caption {
                Text(verbatim: caption)
                    .font(BroopType.number(13))
                    .foregroundStyle(BroopPalette.textBody)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(BroopPalette.row))
            }
        }
        .padding(16)
        .frame(width: 162, alignment: .leading)
        .frame(minHeight: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }
}

/// An inline notice: grey text beside a symbol, on a quiet tile.
struct BroopActivityNotice: View {
    let symbol: String
    let text: String
    var tint: Color = BroopPalette.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(verbatim: text)
                .font(BroopType.regular(13))
                .foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(tint.opacity(0.10)))
    }
}

extension View {
    /// Page chrome for a native Activity screen: Broop background, no system bar (the screen draws its
    /// own header), hidden scroll indicators.
    func broopActivityPage() -> some View {
        self
            .scrollIndicators(.hidden)
            .broopStatusBarScrim()
            .background(BroopBackground())
            .broopBarChrome()
            .preferredColorScheme(.dark)
    }
}
#endif
