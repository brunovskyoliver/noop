#if !os(watchOS)
// These interactive charts are shown on iOS and macOS, but not watchOS.
import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    /// Pointer hover or a short hold followed by scrubbing. A normal swipe remains available to scroll.
    func chartInspectionInput(enabled: Bool = true, onChange: @escaping (CGPoint?) -> Void) -> some View {
        modifier(ChartInspectionInput(enabled: enabled, onChange: onChange))
    }
}

private struct ChartInspectionInput: ViewModifier {
    let enabled: Bool
    let onChange: (CGPoint?) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): update(location)
                    case .ended: update(nil)
                    }
                }
                #if os(iOS)
                .overlay {
                    ChartInspectionTouchSurface(onChange: update)
                        .accessibilityHidden(true)
                }
                #endif
                .onDisappear { update(nil) }
        } else {
            content.allowsHitTesting(false)
        }
    }

    private func update(_ location: CGPoint?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onChange(location) }
    }
}

#if os(iOS)
/// A native long press supplies stationary touch coordinates without a zero-distance pan stealing
/// the enclosing ScrollView's swipe. It also keeps tracking after recognition, until release/cancel.
private struct ChartInspectionTouchSurface: UIViewRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0.25
        press.allowableMovement = 10
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onChange = onChange
    }

    final class Coordinator: NSObject {
        var onChange: (CGPoint?) -> Void

        init(onChange: @escaping (CGPoint?) -> Void) { self.onChange = onChange }

        @objc func handle(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began, .changed: onChange(press.location(in: press.view))
            case .ended, .cancelled, .failed: onChange(nil)
            default: break
            }
        }
    }
}
#endif

// MARK: - Chart Hover Toolkit (reusable across every visualization)
//
// A shared, instrument-grade hover affordance: a small dark tooltip card that
// names the exact datum under the cursor, plus geometry helpers for crosshairs
// and nearest-point lookup. Every StrandDesign visualization inherits the same
// look so nothing is ever a static, unexplained colour.
//
// Design tokens only: surfaceOverlay background, hairline border, StrandFont +
// StrandPalette text, StrandMotion fade-in. Never hardcode hex.

// MARK: - ChartTooltip

/// A readout card for the selected chart point.
/// Renders a bold primary value line and a secondary label/date line.
public struct ChartTooltip: View {

    /// The bold value line (e.g. "62 ms", "Recovery 88").
    public var value: String
    /// The secondary context line (e.g. a formatted date, stage clock, index).
    public var label: String?
    /// An optional accent swatch shown as a leading dot (e.g. the sampled
    /// gradient colour for that datum) so the tooltip explains the colour.
    public var accent: Color?

    public init(value: String, label: String? = nil, accent: Color? = nil) {
        self.value = value
        self.label = label
        self.accent = accent
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let accent {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: accent.opacity(0.8), radius: 3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(StrandFont.captionNumber)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                if let label {
                    Text(label)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NoopPanelSurface(cornerRadius: 12, elevated: true))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder((accent ?? StrandPalette.hairlineStrong).opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label != nil ? "\(value), \(label!)" : value)
    }
}

// MARK: - Tooltip positioning

/// Position a tooltip near an anchor point while keeping it inside `container`.
/// Estimates the tooltip's size, then flips/clamps so it never spills off-edge.
public struct ChartTooltipPlacement {

    /// Compute the tooltip centre for an anchor (typically the highlighted point
    /// or the cursor), given the tooltip's measured size and the chart bounds.
    /// Prefers to sit above-and-right of the anchor, flipping when near an edge.
    public static func position(
        anchor: CGPoint,
        tooltipSize: CGSize,
        in container: CGSize,
        gap: CGFloat = 12
    ) -> CGPoint {
        let halfW = tooltipSize.width / 2
        let halfH = tooltipSize.height / 2

        // Default: above the anchor.
        var y = anchor.y - gap - halfH
        if y - halfH < 0 {
            // Not enough room above — drop below.
            y = anchor.y + gap + halfH
        }
        y = min(max(y, halfH), max(halfH, container.height - halfH))

        // Default: centred on the anchor x, clamped to bounds.
        var x = anchor.x
        x = min(max(x, halfW), max(halfW, container.width - halfW))

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Nearest-point lookup

/// Geometry helpers for mapping a hover location to the nearest datum.
public enum ChartHoverMath {

    /// Screen-space distance distinguishes overlapping series with the same date.
    public static func nearestIndex(to location: CGPoint, positions: [CGPoint]) -> Int? {
        positions.indices.min { lhs, rhs in
            let a = positions[lhs], b = positions[rhs]
            return hypot(a.x - location.x, a.y - location.y)
                < hypot(b.x - location.x, b.y - location.y)
        }
    }

    /// Index of the sample whose x-position (evenly spaced across `width`) is
    /// closest to `x`. Returns nil for an empty series.
    public static func nearestIndex(toX x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1, width > 0 else { return 0 }
        let step = width / CGFloat(count - 1)
        let raw = Int((x / step).rounded())
        return min(max(raw, 0), count - 1)
    }

    /// Index of the point in `xs` (arbitrary x-positions) closest to `x`.
    public static func nearestIndex(toX x: CGFloat, xs: [CGFloat]) -> Int? {
        guard !xs.isEmpty else { return nil }
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, px) in xs.enumerated() {
            let d = abs(px - x)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }
}

// MARK: - Crosshair rule

/// A thin vertical crosshair line drawn at a given x with a hairline-strong
/// stroke. Shared by TrendChart / Sparkline so the rule reads identically.
/// `public`: app-target chart types outside this package (WorkoutRecoveryTrendChart, TrainingLoadCard,
/// LiveTimeChart) reuse this instead of hand-rolling their own crosshair.
public struct CrosshairRule: View {
    public var x: CGFloat
    public var height: CGFloat
    public var color: Color

    public init(x: CGFloat, height: CGFloat, color: Color = StrandPalette.hairlineStrong) {
        self.x = x
        self.height = height
        self.color = color
    }

    public var body: some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(
            color,
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Highlighted point dot

/// A small accented dot used to mark the highlighted sample on a line.
/// `public`: shared with app-target chart hover overlays — see `CrosshairRule`.
public struct HighlightDot: View {
    public var color: Color
    public var diameter: CGFloat

    public init(color: Color, diameter: CGFloat = 9) {
        self.color = color
        self.diameter = diameter
    }

    public var body: some View {
        // Design Reset (WHOOP): a crisp solid dot with a clean surface ring, no blurred bloom halo.
        ZStack {
            Circle()
                .fill(StrandPalette.surfaceBase)
                .frame(width: diameter + 3, height: diameter + 3)
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - "Now" end-cap

/// The crisp "now" marker pinned to a trend line's latest point: a soft tinted outer ring, a brighter
/// mid-ring, and a white core — flat, no bloom (WHOOP). Positioned by `TrendChart` inside its own plot
/// coordinate space so it sits exactly on the curve (#458).
struct NowCapDot: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.30)).frame(width: 18, height: 18)
            Circle().fill(color.opacity(0.65)).frame(width: 11, height: 11)
            Circle().fill(StrandPalette.tipCore).frame(width: 5, height: 5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tooltip overlay container

/// Wraps a tooltip so its measured size feeds back into placement. Fades in
/// with StrandMotion and positions itself within `container` near `anchor`.
/// `public`: shared with app-target chart hover overlays — see `CrosshairRule`.
public struct PositionedTooltip: View {
    public var anchor: CGPoint
    public var container: CGSize
    public var tooltip: ChartTooltip

    @State private var measured: CGSize = .zero

    public init(anchor: CGPoint, container: CGSize, tooltip: ChartTooltip) {
        self.anchor = anchor
        self.container = container
        self.tooltip = tooltip
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            tooltip.fixedSize()
            tooltip.frame(width: max(0, container.width - 8))
        }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { measured = g.size }
                        .onChangeCompat(of: g.size) { measured = $0 }
                }
            )
            .position(
                ChartTooltipPlacement.position(
                    anchor: anchor,
                    tooltipSize: measured == .zero ? CGSize(width: 90, height: 40) : measured,
                    in: container
                )
            )
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("ChartTooltip") {
    VStack(spacing: 24) {
        ChartTooltip(value: "Recovery 88", label: "Tue 3 Jun", accent: StrandPalette.recoveryColor(88))
        ChartTooltip(value: "62 ms", label: "HRV · sample 14")
        ChartTooltip(value: "18.7", label: "STRAIN · all-out", accent: StrandPalette.strainColor(18.7))
    }
    .padding(40)
    .frame(width: 320, height: 240)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
#endif
