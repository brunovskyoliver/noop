#if os(iOS)
import SwiftUI
import StrandDesign

// Overview group building blocks: the deep-dive ring, the notched contributor card, the coach card, the
// custom nav bar and the Home dials. Presentation only; every value comes in from the caller.

/// Colours the Overview screens need beyond the shared Broop palette (sampled from the references).
enum BroopOverviewPalette {
    static let stageAwake = Color(broopHex: 0xC9C9C9)
    static let stageLight = Color(broopHex: 0xA5A2F1)
    static let stageDeep = Color(broopHex: 0xFA96F9)
    static let stageREM = Color(broopHex: 0xAB5BEE)

    static let optimal = Color(broopHex: 0x16EC9A)
    static let poor = Color(broopHex: 0xF3AA3B)
    static let sufficient = Color(broopHex: 0x9A9EA2)
    static let segmentOff = Color(broopHex: 0x3A3F44)

    static let popover = Color(broopHex: 0x1E2327)
    static let popoverTop = Color(broopHex: 0x2A3035)
    static let chip = Color(broopHex: 0x0B0E10)
    static let hairline = Color(broopHex: 0x33383D)
    static let ringTrack = Color(broopHex: 0x333A40)
    static let targetBand = Color(broopHex: 0x5E666C)
    static let button = Color(broopHex: 0x3F4449)
    static let inner = Color(broopHex: 0x3C4044)
    static let hatch = Color(broopHex: 0x1B1F22)

    static let coachStart = Color(broopHex: 0x6B5BD8)
    static let coachEnd = Color(broopHex: 0x3AA8B8)
    static let linkStart = Color(broopHex: 0x8574E8)
    static let linkEnd = Color(broopHex: 0x89B0EA)

    static let alarmOn = Color(broopHex: 0x73EBA4)
    static let alarmOff = Color(broopHex: 0xFFA621)

    static let outlookWarm = Color(broopHex: 0x8A7F70)
    static let outlookSlate = Color(broopHex: 0x3F4B57)
    static let reviewPurple = Color(broopHex: 0x3E3A68)
    static let reviewIndigo = Color(broopHex: 0x2C3446)
}

/// Poor / Sufficient / Optimal band for a contributor percentage.
enum BroopOverviewRating: Int {
    case poor, sufficient, optimal

    /// WHOOP's performance bands: 85%+ optimal, 70–85% sufficient, under 70% poor.
    static func performance(_ pct: Double) -> BroopOverviewRating {
        pct >= 85 ? .optimal : (pct >= 70 ? .sufficient : .poor)
    }

    /// Restorative share bands: over 45% high, 30–45% sufficient, under 30% low.
    static func restorative(_ pct: Double) -> BroopOverviewRating {
        pct > 45 ? .optimal : (pct >= 30 ? .sufficient : .poor)
    }

    var color: Color {
        switch self {
        case .poor: return BroopOverviewPalette.poor
        case .sufficient: return BroopOverviewPalette.sufficient
        case .optimal: return BroopOverviewPalette.optimal
        }
    }
}

// MARK: - Navigation bar

/// Back chevron, centred tracked-caps title with quiet day chevrons, and an (i) button.
struct BroopOverviewNavBar: View {
    let title: String
    var canGoBack = false
    var canGoForward = false
    var onBack: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onInfo: (() -> Void)? = nil

    var body: some View {
        BroopNavHeader {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").frame(width: 28, height: 36)
                    }
                    .opacity(canGoBack ? 0.9 : 0.25)
                    .disabled(!canGoBack)
                    .accessibilityLabel(Text("Previous day"))
                }
                BroopNavTitle(title: title)
                if let onForward {
                    Button(action: onForward) {
                        Image(systemName: "chevron.right").frame(width: 28, height: 36)
                    }
                    .opacity(canGoForward ? 0.9 : 0.25)
                    .disabled(!canGoForward)
                    .accessibilityLabel(Text("Next day"))
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(BroopPalette.textPrimary)
            .buttonStyle(.plain)
        } trailing: {
            if let onInfo {
                BroopNavIcon(symbol: "info.circle", label: String(localized: "How this is calculated"), action: onInfo)
            }
        }
    }
}

// MARK: - Rings

/// Arc geometry shared by the dials: 12 o'clock start, clockwise, flat ends.
struct BroopOverviewArc: Shape {
    var from: Double
    var to: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set { from = newValue.first; to = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        guard to > from else { return p }
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(-90 + 360 * from), endAngle: .degrees(-90 + 360 * to), clockwise: false)
        return p
    }
}

/// The big deep-dive ring: track, optional target band and tick, the score arc, and the centre stack
/// (wordmark, number with small unit, caps label, optional three-dash rating).
struct BroopOverviewHeroRing: View {
    let fraction: Double?
    let color: Color
    let valueText: String?
    var unit: String = ""
    let label: [String]
    var band: ClosedRange<Double>? = nil
    var tick: Double? = nil
    var rating: BroopOverviewRating? = nil
    var diameter: CGFloat = 236
    var lineWidth: CGFloat = 14
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(BroopOverviewPalette.ringTrack, lineWidth: lineWidth)
            if let band {
                BroopOverviewArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(BroopOverviewPalette.targetBand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            BroopOverviewArc(from: 0.004, to: max(0.004, shown))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            if let tick {
                Rectangle()
                    .fill(BroopPalette.textPrimary)
                    .frame(width: 2.5, height: lineWidth + 3)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(360 * tick))
            }
            VStack(spacing: 0) {
                BroopWordmark(size: 15)
                    .opacity(0.55)
                    .padding(.bottom, 4)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(verbatim: valueText ?? "--")
                        .font(BroopType.number(diameter * 0.275))
                    if valueText != nil, !unit.isEmpty {
                        Text(verbatim: unit).font(BroopType.number(diameter * 0.15))
                    }
                }
                .foregroundStyle(valueText == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                .broopNumeral(diameter * 0.275, color: valueText == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                .frame(height: diameter * 0.26)
                VStack(spacing: 2) {
                    ForEach(label, id: \.self) { BroopCaps($0, size: 13) }
                }
                .padding(.top, 6)
                if let rating {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i == rating.rawValue ? BroopPalette.textSecondary : BroopOverviewPalette.segmentOff)
                                .frame(width: 13, height: 3)
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = clamp(fraction) } }
        .onChange(of: fraction) { _, v in withAnimation(.easeOut(duration: 0.4)) { shown = clamp(v) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label.joined(separator: " ")) \(valueText ?? "–")\(unit)"))
    }

    private func clamp(_ v: Double?) -> Double { min(max(v ?? 0, 0), 1) }
}

/// Home-size dial: thin flat ring, optional target band and tick, number with a small "%".
struct BroopOverviewDial: View {
    let fraction: Double?
    let color: Color
    let valueText: String?
    var unit: String = ""
    var band: ClosedRange<Double>? = nil
    var tick: Double? = nil
    var diameter: CGFloat = 94
    var lineWidth: CGFloat = 6
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(BroopOverviewPalette.ringTrack, lineWidth: lineWidth)
            if let band {
                BroopOverviewArc(from: band.lowerBound, to: band.upperBound)
                    .stroke(BroopOverviewPalette.targetBand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            BroopOverviewArc(from: 0.006, to: max(0.006, shown))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            if let tick {
                Rectangle()
                    .fill(BroopPalette.textPrimary)
                    .frame(width: 2, height: lineWidth + 2)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(360 * tick))
            }
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(verbatim: valueText ?? "--").font(BroopType.number(diameter * 0.35))
                if !unit.isEmpty {
                    Text(verbatim: unit).font(BroopType.number(diameter * 0.2))
                }
            }
            .foregroundStyle(valueText == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
            .broopNumeral(diameter * 0.35, color: valueText == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = clamp(fraction) } }
        .onChange(of: fraction) { _, v in withAnimation(.easeOut(duration: 0.4)) { shown = clamp(v) } }
    }

    private func clamp(_ v: Double?) -> Double { min(max(v ?? 0, 0), 1) }
}

/// A tiny ring for the collapsed Home header.
struct BroopOverviewMiniRing: View {
    let fraction: Double?
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(BroopOverviewPalette.ringTrack, lineWidth: 3)
            BroopOverviewArc(from: 0, to: min(max(fraction ?? 0, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Contributor card

/// One contributor row: outline icon, caps label, optional rating bar, value with a baseline under it
/// and a coloured triangle.
struct BroopOverviewContributor: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let value: String
    var baseline: String? = nil
    var rating: BroopOverviewRating? = nil
    /// Up / down vs baseline, and whether that direction is good.
    var trendUp: Bool? = nil
    var trendColor: Color = BroopPalette.textSecondary
    var link: BroopScreen? = nil
}

extension BroopOverviewContributor {
    /// A contributor built from a snapshot reading against its 30-day baseline.
    init(reading: BroopReading, symbol: String, label: String, link: BroopScreen? = nil) {
        self.init(id: label, symbol: symbol, label: label,
                  value: reading.text + (reading.unit == "%" ? "%" : ""),
                  baseline: reading.format(reading.baseline) + (reading.unit == "%" ? "%" : ""),
                  trendUp: reading.trendSymbol.map { $0.contains("up") },
                  trendColor: reading.trendTint,
                  link: link)
    }
}

/// The card under a deep-dive ring: a notch pointing up at the ring, hairline-separated rows, and a
/// legend chip.
struct BroopOverviewContributorCard<Legend: View>: View {
    let rows: [BroopOverviewContributor]
    @ViewBuilder var legend: Legend

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1)
                }
                if let link = row.link {
                    NavigationLink(value: link) { rowView(row) }
                        .buttonStyle(BroopPressableStyle())
                } else {
                    rowView(row)
                }
            }
            legend
                .padding(.top, 14)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .background(
            BroopOverviewNotchedShape(notch: 9)
                .fill(LinearGradient(colors: [BroopOverviewPalette.popoverTop, BroopOverviewPalette.popover],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(BroopOverviewNotchedShape(notch: 9).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func rowView(_ row: BroopOverviewContributor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 24)
            BroopCaps(row.label, size: 11.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let rating = row.rating {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == rating.rawValue ? rating.color : BroopOverviewPalette.segmentOff)
                            .frame(width: 15, height: 3.5)
                    }
                }
                .padding(.trailing, 8)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: row.value)
                    .font(BroopType.number(21))
                    .broopNumeral(21)
                    .foregroundStyle(BroopPalette.textPrimary)
                if let baseline = row.baseline {
                    Text(verbatim: baseline)
                        .font(BroopType.number(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .frame(minWidth: 44, alignment: .trailing)
            if row.rating == nil {
                Group {
                    if let up = row.trendUp {
                        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .foregroundStyle(row.trendColor)
                    } else if row.baseline != nil {
                        Circle().fill(BroopPalette.textSecondary).frame(width: 4, height: 4)
                    } else {
                        Color.clear
                    }
                }
                .font(.system(size: 8))
                .frame(width: 12)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

/// A rounded rectangle with a small triangle on its top edge, centred.
struct BroopOverviewNotchedShape: Shape {
    var notch: CGFloat = 9
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        var tri = Path()
        tri.move(to: CGPoint(x: rect.midX - notch, y: rect.minY + 0.5))
        tri.addLine(to: CGPoint(x: rect.midX, y: rect.minY - notch + 0.5))
        tri.addLine(to: CGPoint(x: rect.midX + notch, y: rect.minY + 0.5))
        tri.closeSubpath()
        p.addPath(tri)
        return p
    }
}

/// "— Poor — Sufficient — Optimal" in a near-black chip.
struct BroopOverviewRatingLegend: View {
    var labels: [String] = [String(localized: "Poor"), String(localized: "Sufficient"), String(localized: "Optimal")]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 8) {
                    Capsule().fill(BroopOverviewRating(rawValue: i)!.color).frame(width: 13, height: 3.5)
                    Text(verbatim: labels[i])
                        .font(BroopType.medium(13))
                        .foregroundStyle(BroopPalette.textBody)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopOverviewPalette.chip))
    }
}

/// "▲▼ Today vs. last 30 days".
struct BroopOverviewTrendLegend: View {
    var dayWord: String = String(localized: "Today")

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrowtriangle.up.fill").foregroundStyle(BroopOverviewPalette.optimal)
            Image(systemName: "arrowtriangle.down.fill").foregroundStyle(BroopOverviewPalette.poor)
                .padding(.trailing, 8)
            (Text(verbatim: dayWord).foregroundColor(BroopPalette.textPrimary)
             + Text(verbatim: " " + String(localized: "vs. last 30 days")).foregroundColor(BroopPalette.textSecondary))
                .font(BroopType.medium(13))
            Spacer(minLength: 0)
        }
        .font(.system(size: 8))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopOverviewPalette.chip))
    }
}

// MARK: - Coach card

/// Insight copy in a card with a purple-to-teal border and a gradient caps link.
struct BroopOverviewCoachCard: View {
    let text: String
    var link: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text)
                .font(BroopType.medium(16))
                .foregroundStyle(BroopPalette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let link, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Text(verbatim: link.uppercased())
                            .font(BroopType.caps(11.5))
                            .tracking(11.5 * 0.11)
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .regular))
                    }
                    .foregroundStyle(LinearGradient(colors: [BroopOverviewPalette.linkStart, BroopOverviewPalette.linkEnd],
                                                    startPoint: .leading, endPoint: .trailing))
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.bgBottom.opacity(0.55)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [BroopOverviewPalette.coachStart, BroopOverviewPalette.coachEnd],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4)
        )
    }
}

// MARK: - Section titles and cards

/// Sentence-case large section title with an optional subtitle line and trailing control.
struct BroopOverviewSectionTitle<Trailing: View>: View {
    let title: String
    var subtitle: Text? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(BroopType.demi(BroopType.sectionSize))
                    .foregroundStyle(BroopPalette.textPrimary)
                Spacer()
                trailing
            }
            if let subtitle {
                subtitle.font(BroopType.medium(14))
            }
        }
        .padding(.horizontal, 4)
    }
}

extension BroopOverviewSectionTitle where Trailing == EmptyView {
    init(_ title: String, subtitle: Text? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// "EDIT ✎" style trailing caps button.
struct BroopOverviewCapsButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                BroopCaps(title, size: 11.5)
                Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(BroopPalette.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// A Home/deep-dive surface card: rounded 16, flat fill.
struct BroopOverviewCard<Content: View>: View {
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

/// Grey filled rounded-rect button with a leading glyph and caps label ("+ ADD ACTIVITY").
struct BroopOverviewFillButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                BroopCaps(title, size: 10.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopOverviewPalette.button))
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// Diagonal-hatch track used behind the sleep stage bars.
struct BroopOverviewHatch: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BroopOverviewPalette.hatch))
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 1.6)
        }
    }
}

// MARK: - Formatting

enum BroopOverviewFormat {
    /// "H:MM" for a minute count, as WHOOP prints durations.
    static func hm(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        return BroopFormat.duration(minutes)
    }

    static func pct(_ v: Double?) -> String { v.map { BroopFormat.whole($0) } ?? "--" }

    /// Tracked-caps date title: "TODAY", "YESTERDAY" or "FRI, MAY 9".
    @MainActor static func dayTitle(_ store: BroopStore) -> String {
        switch store.dayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default:
            return store.selectedLogicalDay.formatted(
                .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.activeLocale))
        }
    }

    /// A minute-of-day as the device's short clock format.
    static func clock(_ minuteOfDay: Int) -> String {
        var c = DateComponents(); c.hour = (minuteOfDay / 60) % 24; c.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
#endif

