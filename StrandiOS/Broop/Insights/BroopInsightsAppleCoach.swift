#if os(iOS)
import SwiftUI
import UIKit

// The Apple Intelligence Coach's own surfaces: what the Coach screen shows when the model cannot run (one
// view per `AppleCoachAvailability` case, never an error dump) and the Coach settings sheet with the backend
// choice and the "Use Apple servers when needed" toggle. Fork change.

/// The Coach screen when Apple Intelligence cannot answer: why, and the one thing that helps.
struct BroopInsightsCoachUnavailable: View {
    @EnvironmentObject private var coach: AICoachEngine
    let state: AppleCoachAvailability

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BroopBadge(size: 44, gradientRing: true)
                Text(verbatim: title)
                    .font(BroopType.demi(25))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                BroopInsightsBody(text: detail, size: 15.5)
                if state == .appleIntelligenceOff {
                    BroopInsightsPrimaryButton(title: String(localized: "Open Settings"), symbol: "gearshape") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if state == .modelDownloading {
                    HStack(spacing: 10) {
                        ProgressView().tint(BroopPalette.textSecondary)
                        Text("Checking again when you come back to the app.")
                            .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                if state != .modelDownloading {
                    BroopInsightsOutlineButton(title: String(localized: "Use a cloud provider instead"), symbol: "key") {
                        coach.backend = .cloud
                    }
                    BroopInsightsBody(text: String(localized: "A cloud provider sends a summary of your data and your question to the company you pick, with your own API key."),
                                      size: 12.5, color: BroopPalette.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private var title: String {
        switch state {
        case .appleIntelligenceOff: return String(localized: "Turn on Apple Intelligence")
        case .deviceNotEligible: return String(localized: "This iPhone can't run Apple Intelligence")
        case .modelDownloading: return String(localized: "Apple Intelligence is getting ready")
        case .languageNotSupported: return String(localized: "Coach isn't available in this language yet")
        case .osTooOld: return String(localized: "Coach needs iOS 26 or later")
        case .onDeviceReady, .appleServersOnly: return String(localized: "Coach")
        }
    }

    private var detail: String {
        switch state {
        case .appleIntelligenceOff:
            return String(localized: "Coach runs on Apple Intelligence. Turn it on in Settings under Apple Intelligence & Siri, then come back here.")
        case .deviceNotEligible:
            return String(localized: "Apple Intelligence needs an iPhone 15 Pro or later. The rest of the app works the same without it.")
        case .modelDownloading:
            return String(localized: "The model is still downloading to this iPhone. Coach becomes available when it finishes.")
        case .languageNotSupported:
            return String(localized: "Apple Intelligence doesn't support the app's language yet. You can switch the app to a supported language in Settings, or use a cloud provider.")
        case .osTooOld:
            return String(localized: "Apple Intelligence Coach needs iOS 26. On this version you can use a cloud provider with your own key.")
        case .onDeviceReady, .appleServersOnly:
            return ""
        }
    }
}

/// Coach settings: which backend answers, the Apple servers fallback, and the cloud provider's own settings.
struct BroopInsightsCoachSettingsSheet: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var showProvider = false
    @State private var showCloudSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        BroopCaps(String(localized: "Coach answers with"), size: 10.5, color: BroopPalette.textSecondary)
                        BroopAccountGroup {
                            ForEach(CoachBackend.allCases) { backend in
                                backendRow(backend)
                            }
                        }
                    }
                    if coach.backend == .appleIntelligence {
                        BroopAccountGroup {
                            BroopAccountToggle(title: String(localized: "Use Apple servers when needed"),
                                               detail: String(localized: "Only when the on-device model can't answer. That turn's question and the data Coach looked up for it go to Apple's Private Cloud Compute, and the reply is labelled \"via Apple servers\". Needs iOS 27."),
                                               isOn: $coach.allowAppleServers)
                        }
                    } else {
                        BroopAccountGroup {
                            navRow(String(localized: "Provider, model and key")) { showProvider = true }
                            navRow(String(localized: "Data sharing and brief")) { showCloudSettings = true }
                        }
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(BroopBackground())
            .broopSheetBar(String(localized: "Coach settings")) { dismiss() }
        }
        .sheet(isPresented: $showProvider) { CoachProviderSettingsView(coach: coach) }
        .sheet(isPresented: $showCloudSettings) { CoachSettingsView().environmentObject(coach).environmentObject(repo) }
    }

    private func backendRow(_ backend: CoachBackend) -> some View {
        Button { coach.backend = backend } label: {
            BroopAccountRow(title: backend.displayName, detail: detail(backend)) {
                Image(systemName: coach.backend == backend ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(coach.backend == backend ? BroopPalette.teal : BroopPalette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(coach.backend == backend ? .isSelected : [])
    }

    private func detail(_ backend: CoachBackend) -> String {
        switch backend {
        case .appleIntelligence:
            return String(localized: "No key needed. Runs on this iPhone, with Apple's servers as a fallback if you allow it.")
        case .cloud:
            return String(localized: "Sends a summary of your data and your question to the provider you pick (OpenAI, Anthropic, Gemini or your own server).")
        }
    }

    private func navRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopAccountRow(title: title) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BroopPalette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
