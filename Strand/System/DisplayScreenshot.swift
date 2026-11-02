import Foundation
import UIKit

// DisplayScreenshot.swift - captures the current screen as PNG bytes for the Display & Performance test
// mode's export bundle (spec section: screenshot into the bundle).
//
// The PNG is BINARY image bytes, not a text line, so it is NOT run through redactPii (that is correct and
// intentional - redaction scrubs text identifiers, not pixels). The screenshot IS covered by the mandatory
// review-before-share gate: the report never ships until the user taps Share on the review sheet, and the
// gate's note tells them a screenshot is attached. A capture only ever happens for the .display profile,
// gated by the assembler behind TestCentre.active(.display) / includesScreenshot, so a non-display report
// never grabs a shot.

enum DisplayScreenshot {

    /// The in-zip name of the captured screenshot.
    static let bundleName = "screenshot.png"

    /// Capture the key window as PNG bytes, or nil if there is no window to capture / the render failed.
    /// Called on the main thread (the Report button tap path), so it can touch UIKit directly.
    @MainActor
    static func capturePNG() -> Data? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.keyWindow ?? scene?.windows.first else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            // afterScreenUpdates=false: snapshot what is currently on screen without forcing a relayout,
            // so the shot shows exactly the (possibly broken) frame the user is reporting.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.pngData()
    }
}
