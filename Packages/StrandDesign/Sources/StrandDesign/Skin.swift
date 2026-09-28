import SwiftUI

// MARK: - Skin switch (Broop)
//
// The iOS fork ships a WHOOP-style "Broop" interface. Screens rebuilt natively for it live in the app
// target; everything else still renders through this design system. When the skin is on, the shared
// tokens resolve to the Broop values instead, so a classic screen reached from the Broop shell reads as
// part of the same app: flat slate cards on a slate-to-black canvas, DIN numerals, Avenir Next text,
// and WHOOP-style domain colours.
//
// The switch is read ONCE per process. Every token below is a `static let` built from it, so nothing
// here costs anything per frame, and flipping the preference takes effect on the next launch.

public enum StrandSkin {
    /// The preference key the iOS app stores the Broop toggle under. Absent means on.
    public static let broopDefaultsKey = "broop.uiEnabled"

    /// Whether the Broop skin is active in this process. Only the iOS app itself: macOS, watchOS and
    /// every app extension (widgets read their own defaults container) keep the classic look.
    public static let broop: Bool = {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if Bundle.main.bundlePath.hasSuffix(".appex") { return false }
        return UserDefaults.standard.object(forKey: broopDefaultsKey) as? Bool ?? true
        #else
        return false
        #endif
    }()

    /// Hex values mirrored from the app's `BroopPalette` (StrandiOS/Broop/BroopDesign.swift). The app
    /// target cannot be imported from here, so the values are repeated; keep the two in step.
    enum Hex {
        static let bgTop = "#283339"
        static let bgMid = "#13181C"
        static let bgBottom = "#0D1114"

        static let card = "#272B2E"
        static let inset = "#1E2225"
        static let track = "#2E353B"
        /// White at 7% / 12% (RRGGBBAA).
        static let hairline = "FFFFFF12"
        static let hairlineStrong = "FFFFFF1F"

        static let textPrimary = "#FFFFFF"
        static let textBody = "#BABEC0"
        static let textSecondary = "#8F959A"

        static let bandHigh = "#16EC06"
        static let bandMid = "#FFDE00"
        static let bandLow = "#FF0026"
        static let effort = "#0093E7"
        static let effortDeep = "#005E96"
        static let effortBright = "#4DB6F2"
        static let rest = "#7BA1BB"
        static let restDeep = "#42627F"
        static let restBright = "#B6CCDD"
        static let teal = "#5FEBA5"
        static let warning = "#F5A623"

        static let stageAwake = "#E4E8EB"
        static let stageREM = "#B6CCDD"
        static let stageLight = "#7BA1BB"
        static let stageDeep = "#42627F"
    }

    /// Card corner radius under the skin.
    static let cardRadius: CGFloat = 12
}

public extension Color {
    /// A light/dark token whose DARK variant is replaced by `broop` when the skin is on. The light
    /// variant never changes: the app forces dark mode while Broop is enabled.
    init(light: String, dark: String, broop: String) {
        self.init(light: light, dark: StrandSkin.broop ? broop : dark)
    }
}

/// Skin-only colour tokens, built once. `StrandPalette` accessors return these when the skin is on.
enum SkinPalette {
    static let chargeHigh = Color(hex: StrandSkin.Hex.bandHigh)
    static let chargeMid = Color(hex: StrandSkin.Hex.bandMid)
    static let chargeLow = Color(hex: StrandSkin.Hex.bandLow)
    static let chargeDeep = Color(hex: "#0FA804")
    static let chargeBright = Color(hex: "#7CF572")

    static let effort = Color(hex: StrandSkin.Hex.effort)
    static let effortDeep = Color(hex: StrandSkin.Hex.effortDeep)
    static let effortBright = Color(hex: StrandSkin.Hex.effortBright)

    static let rest = Color(hex: StrandSkin.Hex.rest)
    static let restDeep = Color(hex: StrandSkin.Hex.restDeep)
    static let restBright = Color(hex: StrandSkin.Hex.restBright)

    static let teal = Color(hex: StrandSkin.Hex.teal)
    static let warning = Color(hex: StrandSkin.Hex.warning)

    static let stageAwake = Color(hex: StrandSkin.Hex.stageAwake)
    static let stageREM = Color(hex: StrandSkin.Hex.stageREM)
    static let stageLight = Color(hex: StrandSkin.Hex.stageLight)
    static let stageDeep = Color(hex: StrandSkin.Hex.stageDeep)

    /// Charge scale: red below 34, yellow 34-66, green from 67 (the same split as `BroopPalette.band`),
    /// with short blends so a sampled gradient does not step harshly along a ring.
    static let recoveryStops: [Gradient.Stop] = [
        .init(color: chargeLow, location: 0.00),
        .init(color: chargeLow, location: 0.30),
        .init(color: chargeMid, location: 0.50),
        .init(color: chargeHigh, location: 0.70),
        .init(color: chargeHigh, location: 1.00),
    ]
    static let strainStops: [Gradient.Stop] = [
        .init(color: effortDeep, location: 0.00),
        .init(color: effort, location: 0.45),
        .init(color: effort, location: 0.75),
        .init(color: effortBright, location: 1.00),
    ]

    static let bgTop = Color(hex: StrandSkin.Hex.bgTop)
    static let bgMid = Color(hex: StrandSkin.Hex.bgMid)
    static let bgBottom = Color(hex: StrandSkin.Hex.bgBottom)
}

// MARK: - Backdrop

/// The Broop page backdrop: slate at the top fading to near-black. Stands in for the day-cycle sky,
/// scene images and time-of-day atmospheres while the skin is on. Full-bleed; the caller decides the
/// frame. `fadesToCanvas` ends the ramp on the canvas colour instead, for a top band drawn over it.
public struct StrandSkinBackdrop: View {
    public var fadesToCanvas: Bool

    public init(fadesToCanvas: Bool = false) {
        self.fadesToCanvas = fadesToCanvas
    }

    public var body: some View {
        LinearGradient(stops: fadesToCanvas ? Self.bandStops : Self.pageStops, startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let pageStops: [Gradient.Stop] = [
        .init(color: SkinPalette.bgTop, location: 0),
        .init(color: SkinPalette.bgMid, location: 0.5),
        .init(color: SkinPalette.bgBottom, location: 0.85),
    ]
    private static let bandStops: [Gradient.Stop] = [
        .init(color: SkinPalette.bgTop, location: 0),
        .init(color: SkinPalette.bgMid, location: 1),
    ]
}

/// The screen canvas: the Broop backdrop when the skin is on, otherwise the flat `surfaceBase` token.
public struct StrandCanvas: View {
    public init() {}

    public var body: some View {
        if StrandSkin.broop {
            StrandSkinBackdrop()
        } else {
            StrandPalette.surfaceBase
        }
    }
}
