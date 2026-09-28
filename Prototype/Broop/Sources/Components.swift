import SwiftUI

// MARK: - Brand

/// The Broop "B": a heavy upright letter with chamfered bowls, on a 100×100 grid.
/// The same geometry renders the app icon (Tools/render_icon.swift).
struct BrandMark: Shape {
    static let outer: [CGPoint] = [
        .init(x: 24, y: 14), .init(x: 62, y: 14), .init(x: 74, y: 26), .init(x: 74, y: 40),
        .init(x: 67, y: 49), .init(x: 78, y: 60), .init(x: 78, y: 74), .init(x: 66, y: 86),
        .init(x: 24, y: 86),
    ]
    static let upperCounter: [CGPoint] = [
        .init(x: 40, y: 28), .init(x: 56, y: 28), .init(x: 58, y: 30), .init(x: 58, y: 38),
        .init(x: 54, y: 42), .init(x: 40, y: 42),
    ]
    static let lowerCounter: [CGPoint] = [
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

/// The thin, widely tracked wordmark that sits under the header.
struct Wordmark: View {
    var size: CGFloat = 17
    var body: some View {
        Text("BROOP")
            .font(Broop.Typeface.wordmark(size))
            .tracking(size * 0.24)
            .foregroundStyle(Broop.Palette.textPrimary)
    }
}

/// The "B" inside a thin ring: the Coach entry point and the insight bullet.
struct BrandBadge: View {
    var size: CGFloat = 30
    var gradientRing = false

    var body: some View {
        ZStack {
            if gradientRing {
                Circle().stroke(
                    AngularGradient(colors: [Color(hex: 0x6A7BFF), Color(hex: 0xB07CFF), Color(hex: 0x5AD8FF), Color(hex: 0x6A7BFF)], center: .center),
                    lineWidth: size * 0.07
                )
            } else {
                Circle().stroke(Broop.Palette.textPrimary.opacity(0.85), lineWidth: 1.4)
            }
            BrandMark()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(Broop.Palette.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Type

/// Uppercase, bold, tracked label: section titles, dial labels, activity names.
struct Caps: View {
    let text: String
    var size: CGFloat = 10.5
    var color: Color = Broop.Palette.textPrimary

    init(_ text: String, size: CGFloat = 10.5, color: Color = Broop.Palette.textPrimary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Broop.Typeface.caps(size))
            .tracking(size * 0.11)
            .foregroundStyle(color)
    }
}

/// Sentence-case section title ("My Day").
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Broop.Typeface.demi(20))
                .foregroundStyle(Broop.Palette.textPrimary)
            Spacer()
            trailing
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

/// Small grey header row above a list: "SLEEP STATISTICS · VS. PREVIOUS 30 DAYS".
struct ListHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Caps(title, size: 10, color: Broop.Palette.textSecondary)
            Spacer()
            if let trailing { Caps(trailing, size: 10, color: Broop.Palette.textSecondary) }
        }
    }
}

// MARK: - Surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Broop.Radius.card, style: .continuous)
                    .fill(Broop.Palette.card)
            )
    }
}

/// A lighter tile inside a card (activity rows, stat rows).
struct Tile<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Broop.Radius.row, style: .continuous)
                    .fill(Broop.Palette.row)
            )
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Broop.Palette.hairline).frame(height: 1)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Scores

/// Thin flat-ended ring with the score inside. Optional white tick marks a target.
struct ScoreDial: View {
    let kind: ScoreKind
    let value: Double
    var diameter: CGFloat = 82
    var lineWidth: CGFloat = 5.3
    var marker: Double? = nil
    @State private var shown: Double = 0

    private func fraction(_ v: Double) -> Double {
        (v - kind.domain.lowerBound) / (kind.domain.upperBound - kind.domain.lowerBound)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Broop.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(kind.color(for: value), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            if let marker {
                Rectangle()
                    .fill(Broop.Palette.textPrimary)
                    .frame(width: 2, height: lineWidth + 2)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(360 * fraction(marker)))
            }
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(kind.format(value))
                    .font(Broop.Typeface.number(diameter * 0.33))
                    .contentTransition(.numericText(value: value))
                if !kind.unit.isEmpty {
                    Text(kind.unit).font(Broop.Typeface.number(diameter * 0.24))
                }
            }
            .foregroundStyle(Broop.Palette.textPrimary)
            .numeral(diameter * 0.33)
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = fraction(value) } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.4)) { shown = fraction(v) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title) \(kind.format(value))\(kind.unit)")
    }
}

/// A typical-range band with the reading as a dot (Health monitor).
struct RangeBar: View {
    let contributor: Contributor

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = x(contributor.typical.lowerBound, w)
            let hi = x(contributor.typical.upperBound, w)
            ZStack(alignment: .leading) {
                Capsule().fill(Broop.Palette.track).frame(height: 3)
                Capsule().fill(Broop.Palette.textSecondary).frame(width: max(6, hi - lo), height: 3).offset(x: lo)
                Circle()
                    .fill(contributor.status == .typical ? Broop.Palette.textPrimary : contributor.tint)
                    .frame(width: 9, height: 9)
                    .offset(x: x(contributor.value, w) - 4.5)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
    }

    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        let d = contributor.domain
        let t = (min(max(v, d.lowerBound), d.upperBound) - d.lowerBound) / (d.upperBound - d.lowerBound)
        return CGFloat(t) * width
    }
}

/// "▲ 12%" in a small grey box, as on WHOOP's stress breakdown.
struct DeltaPill: View {
    let contributor: Contributor

    var body: some View {
        let base = contributor.baseline
        let pct = base == 0 ? 0 : (contributor.value - base) / abs(base) * 100
        HStack(spacing: 4) {
            if abs(pct) >= 0.5 {
                Image(systemName: pct >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
            }
            Text("\(Fmt.whole(abs(pct)))%").font(Broop.Typeface.number(12))
        }
        .foregroundStyle(contributor.trendSymbol == nil ? Broop.Palette.textSecondary : contributor.trendTint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Broop.Palette.row))
    }
}

/// One statistic against its 30-day baseline: name, today, 30-day average.
struct StatRow: View {
    let contributor: Contributor

    var body: some View {
        HStack(spacing: 12) {
            Text(contributor.name)
                .font(Broop.Typeface.medium(14))
                .foregroundStyle(Broop.Palette.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(contributor.text).font(Broop.Typeface.number(19))
                if !contributor.unit.isEmpty {
                    Text(contributor.unit).font(Broop.Typeface.number(11)).foregroundStyle(Broop.Palette.textSecondary)
                }
            }
            .foregroundStyle(Broop.Palette.textPrimary)
            Image(systemName: contributor.trendSymbol ?? "minus")
                .font(.system(size: 8))
                .foregroundStyle(contributor.trendSymbol == nil ? Broop.Palette.textTertiary : contributor.trendTint)
                .frame(width: 10)
            Text(contributor.format(contributor.baseline))
                .font(Broop.Typeface.number(15))
                .foregroundStyle(Broop.Palette.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Header controls

/// Two-tone capsule: chevrons on the outer track, the day on a lighter inner pill.
struct DateNavigator: View {
    @EnvironmentObject var store: SampleStore

    var body: some View {
        HStack(spacing: 0) {
            Button { store.step(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 38, height: 28)
            }
            .opacity(store.selectedIndex == 0 ? 0.3 : 1)
            .disabled(store.selectedIndex == 0)

            Button { store.goToToday() } label: {
                Text(store.dayLabel)
                    .font(Broop.Typeface.caps(10.5))
                    .tracking(1.2)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 82, minHeight: 28)
                    .background(Capsule().fill(Broop.Palette.pillInner))
            }

            Button { store.step(1) } label: {
                Image(systemName: "chevron.right").frame(width: 38, height: 28)
            }
            .opacity(store.isToday ? 0.3 : 1)
            .disabled(store.isToday)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Broop.Palette.textPrimary)
        .background(Capsule().fill(Broop.Palette.pillOuter))
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: store.selectedIndex)
    }
}

struct Avatar: View {
    var initials = "OB"
    var body: some View {
        Text(initials)
            .font(Broop.Typeface.medium(13))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: 32, height: 32)
            .background(Circle().fill(LinearGradient(colors: [Broop.Palette.avatarStart, Broop.Palette.avatarEnd], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// Strap battery: grey percentage plus a side-view wrist strap with a green connection dot.
struct StrapStatus: View {
    let level: Double
    var body: some View {
        HStack(spacing: 7) {
            Text("\(Int(level * 100))%")
                .font(Broop.Typeface.number(14))
                .foregroundStyle(Broop.Palette.textSecondary)
                .numeral(14, color: Broop.Palette.textSecondary)
            ZStack(alignment: .topLeading) {
                StrapGlyph()
                    .stroke(Broop.Palette.textPrimary, style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 23.5)
                Circle()
                    .fill(Color(hex: 0x1DE9A0))
                    .frame(width: 6, height: 6)
                    .offset(x: 14, y: 3)
            }
            .frame(width: 20.5, height: 23.5, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strap battery \(Int(level * 100)) percent")
    }
}

/// A band seen from the side, hand-traced on an 18 × 23.5 pt grid: flat top with a sharp corner,
/// the body's inner edge running down from it, a stepped left edge, and the strap tail forming
/// the outer right side, left open under the connection dot.
struct StrapGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18, sy = rect.height / 23.5
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        // Outer outline, from the open tail end round to the top corner.
        path.move(to: p(17.4, 12))
        path.addLine(to: p(17.2, 17.5))
        path.addQuadCurve(to: p(12.8, 23), control: p(17, 23))
        path.addLine(to: p(4.6, 23))
        path.addLine(to: p(1.3, 18.1))
        path.addLine(to: p(0.4, 17.5))
        path.addLine(to: p(0.2, 11))
        path.addQuadCurve(to: p(5, 0.7), control: p(0.4, 1))
        path.addLine(to: p(14.2, 0.6))
        // Inner edge of the sensor body, down from the corner, ending in a small kink.
        path.addLine(to: p(12, 3.8))
        path.addQuadCurve(to: p(10.5, 9), control: p(10.6, 5.8))
        path.addLine(to: p(10.4, 17.4))
        path.addLine(to: p(9.7, 18.3))
        path.addLine(to: p(10.5, 20.8))
        // Clasp.
        path.move(to: p(2.6, 16.2))
        path.addLine(to: p(8.4, 16.2))
        return path
    }
}

/// Underlined text tabs (OVERVIEW · SLEEP · RECOVERY · STRAIN style).
struct UnderlineTabs<Option: Hashable>: View {
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
                        Caps(label(option), size: size, color: on ? Broop.Palette.textPrimary : Broop.Palette.textSecondary)
                        ZStack {
                            Rectangle().fill(Color.clear).frame(height: 2)
                            if on {
                                Rectangle().fill(Broop.Palette.textPrimary).frame(width: 28, height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 48)
            Caps(title, size: 12)
            Text("Not part of the prototype yet.")
                .font(Broop.Typeface.regular(14))
                .foregroundStyle(Broop.Palette.textBody)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BroopBackground())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Broop.Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 8)
        }
    }
}
