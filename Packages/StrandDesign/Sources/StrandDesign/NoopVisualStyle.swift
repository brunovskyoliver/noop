import SwiftUI

// MARK: - NOOP visual foundation
//
// These tokens describe the visual treatment used by NOOP's existing views. They deliberately
// contain no navigation, state, or domain semantics: screens keep their current hierarchy and data
// bindings, while cards, gauges, typography, and chrome share one maintainable source of truth.

public enum NoopVisualStyle {
    // Neutral, low-chroma surfaces sampled from the supplied dark-mode reference. Under the Broop skin
    // (`StrandSkin.broop`, iOS only) the DARK variants resolve to the Broop slate palette instead.
    public static let canvas = Color(light: "#F3F4F6", dark: "#1D1E23", broop: StrandSkin.Hex.bgMid)
    public static let surface = Color(light: "#FFFFFF", dark: "#2A2C34", broop: StrandSkin.Hex.card)
    public static let surfaceTop = Color(light: "#FFFFFF", dark: "#30323B", broop: StrandSkin.Hex.card)
    public static let surfaceBottom = Color(light: "#F4F5F7", dark: "#282A31", broop: StrandSkin.Hex.card)
    public static let inset = Color(light: "#E8E9ED", dark: "#23252C", broop: StrandSkin.Hex.inset)

    public static let border = Color(light: "#D8DAE0", dark: "#373A44", broop: StrandSkin.Hex.hairline)
    public static let borderHighlight = Color(light: "#FFFFFF", dark: "#4B4E59", broop: StrandSkin.Hex.hairlineStrong)
    public static let divider = Color(light: "#E4E5E9", dark: "#383A43", broop: StrandSkin.Hex.hairline)

    public static let primaryText = Color(light: "#17181C", dark: "#F7F7FA", broop: StrandSkin.Hex.textPrimary)
    public static let secondaryText = Color(light: "#555861", dark: "#C3C4CA", broop: StrandSkin.Hex.textBody)
    public static let tertiaryText = Color(light: "#7D808A", dark: "#7D7F88", broop: StrandSkin.Hex.textSecondary)

    // The default chrome accent. Under the skin it is the Broop blue, which carries a white label.
    public static let mint = Color(light: "#149A78", dark: "#69DDB8", broop: StrandSkin.Hex.effort)
    public static let mintDeep = Color(light: "#0D765C", dark: "#13A982", broop: StrandSkin.Hex.effort)
    public static let mintGlow = Color(light: "#38C99E", dark: "#54E6BD", broop: StrandSkin.Hex.effortBright)

    public static let cardRadius: CGFloat = StrandSkin.broop ? StrandSkin.cardRadius : 22
    public static let compactRadius: CGFloat = StrandSkin.broop ? 10 : 16
    public static let pillRadius: CGFloat = 999
    public static let pagePadding: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let sectionGap: CGFloat = 26
}

/// Shared card/panel treatment: a solid surface on iOS, gradient and soft elevation elsewhere.
/// `tint` is intentionally faint so metric identity never turns the whole card into a coloured tile.
public struct NoopPanelSurface: View {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var elevated: Bool
    public var surfaceOpacity: Double
    #if !os(iOS)
    @Environment(\.colorScheme) private var scheme
    #endif

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.surfaceOpacity = surfaceOpacity
    }

    public var body: some View {
        if StrandSkin.broop {
            // Broop: one flat slate fill, no tint wash, no rim highlight, no drop shadow.
            RoundedRectangle(cornerRadius: min(cornerRadius, StrandSkin.cardRadius), style: .continuous)
                .fill(NoopVisualStyle.surface)
                .opacity(surfaceOpacity)
        } else {
            classic
        }
    }

    @ViewBuilder private var classic: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(iOS)
        // Scrolling stacks contain many panels. Layered translucent gradients and blurred shadows
        // multiply their compositing work, so iOS uses one theme-aware fill and a thin tinted rim.
        // This changes decorative depth only; card geometry and the design-system colors stay the same.
        shape
            .fill(NoopVisualStyle.surface)
            .overlay(shape.strokeBorder(
                tint?.opacity(0.14) ?? NoopVisualStyle.borderHighlight.opacity(elevated ? 0.9 : 0.65),
                lineWidth: 0.8
            ))
            .opacity(surfaceOpacity)
        #else
        shape
            .fill(
                LinearGradient(
                    colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                if let tint {
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(0.055), tint.opacity(0.012), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay(
                // Gradient VIEW masked by a solid stroke, not `strokeBorder(LinearGradient)`: a gradient-painted
                // stroke is rasterized on the CPU, and on-device (2026-09-23) these card borders were replayed
                // every scroll frame, ~half the main thread. This form stays on the GPU and looks the same.
                LinearGradient(
                    colors: [NoopVisualStyle.borderHighlight.opacity(0.72), NoopVisualStyle.border.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(shape.strokeBorder(lineWidth: 0.8))
            )
            .shadow(
                color: scheme == .dark ? .black.opacity(elevated ? 0.34 : 0.18) : .black.opacity(0.10),
                radius: elevated ? 18 : 9,
                x: 0,
                y: elevated ? 10 : 5
            )
            .opacity(surfaceOpacity)
        #endif
    }
}

/// Shared edge-to-edge chrome for sheet and split-view headers. Unlike a card it has no
/// rounded outline or elevation, but it uses the same top-lit surface ramp and divider token.
public struct NoopChromeSurface: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoopVisualStyle.divider)
                .frame(height: 0.5)
        }
    }
}

public extension View {
    func noopPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) -> some View {
        background {
            NoopPanelSurface(
                tint: tint,
                cornerRadius: cornerRadius,
                elevated: elevated,
                surfaceOpacity: surfaceOpacity
            )
        }
    }
}
