#if os(iOS)
import SwiftUI

/// The Broop face of `TermsGateView`, styled after WHOOP's "Privacy and Terms of Use" page: grey
/// padlock, large title, grey lead-in, square white checkboxes, and a white capsule pinned at the bottom.
///
/// Same clickwrap contract as the gate: the points and attestations are `Terms.points` /
/// `Terms.attestations` verbatim, every attestation starts unticked, and Accept stays disabled until all
/// of them are ticked. The caller owns what accepting stores (`noop.acceptedTermsVersion`).
struct BroopFinalBOnboardingTermsGate: View {
    let onAccept: () -> Void
    @State private var checks: [Bool] = Array(repeating: false, count: Terms.attestations.count)

    private var allChecked: Bool { checks.allSatisfy { $0 } }

    var body: some View {
        ZStack {
            BroopBackground()
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        BroopFinalBOnbIllustration(symbol: "lock.fill", size: 54)
                            .padding(.top, 36)
                            .padding(.bottom, 22)

                        BroopFinalBOnbTitleBlock(
                            title: String(localized: "Before you use Broop"),
                            subtitle: String(localized: "Please read the points below, then confirm each statement."))
                            .padding(.bottom, 28)

                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Terms.points, id: \.0) { point in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: point.0)
                                        .font(BroopType.demi(16))
                                        .foregroundStyle(BroopPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(verbatim: point.1)
                                        .font(BroopType.regular(14))
                                        .foregroundStyle(BroopPalette.textSecondary)
                                        .lineSpacing(1.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        BroopHairline().padding(.vertical, 26)

                        BroopCaps(String(localized: "Please confirm each of these:"), size: 11, color: BroopPalette.textSecondary)
                            .padding(.bottom, 18)

                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(Terms.attestations.enumerated()), id: \.offset) { idx, line in
                                attestationRow(idx: idx, line: line)
                            }
                        }

                        Text("The full terms are in TERMS.md, shipped with NOOP. This is not legal advice.")
                            .font(BroopType.regular(13))
                            .foregroundStyle(BroopPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

                BroopFinalBOnbFooter {
                    BroopFinalBOnbCapsuleButton(title: String(localized: "Accept & Continue"), action: onAccept)
                        .disabled(!allChecked)
                }
            }
            .broopStatusBarScrim()
        }
        .preferredColorScheme(.dark)
    }

    private func attestationRow(idx: Int, line: String) -> some View {
        Button {
            checks[idx].toggle()
        } label: {
            HStack(alignment: .top, spacing: 16) {
                BroopFinalBOnbCheckbox(isOn: checks[idx])
                    .padding(.top, 1)
                Text(verbatim: line)
                    .font(BroopType.medium(15))
                    .foregroundStyle(checks[idx] ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(checks[idx] ? "Checked" : "Unchecked"))
    }
}
#endif
