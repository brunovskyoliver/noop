// Compiled ONLY when the OURA_CLOUD_IMPORT compilation condition is set (by the untracked
// OuraSecrets.xcconfig — see OuraConfig.xcconfig). A default build contains none of this code,
// keeping "fully offline" a byte-level property of the shipped binary, not a runtime promise.
#if OURA_CLOUD_IMPORT
import AuthenticationServices
import UIKit

/// The app's key window as an ASPresentationAnchor for ASWebAuthenticationSession. Modeled on
/// DisplayScreenshot's window lookup. Falls back to a bare anchor (OuraOAuthProvider tolerates it).
@MainActor func ouraPresentationAnchor() -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
}
#endif // OURA_CLOUD_IMPORT
