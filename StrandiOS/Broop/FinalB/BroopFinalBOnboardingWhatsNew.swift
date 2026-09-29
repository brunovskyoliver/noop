#if os(iOS)
import SwiftUI

/// The Broop face of `WhatsNewView`: the same `AppChangelog` content (expectations first, then every
/// release, newest first) on the Broop canvas, with a white "Got it" capsule. The caller owns what
/// closing stores (`noop.lastSeenChangelogVersion`).
struct BroopFinalBOnboardingWhatsNew: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                // The changelog grows every release: build the release cards lazily.
                LazyVStack(alignment: .leading, spacing: BroopMetrics.gap) {
                    header
                        .padding(.bottom, 18)
                    BroopListHeader(title: String(localized: "What to expect"))
                        .padding(.horizontal, 4)
                    BroopCard {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(AppChangelog.expectations) { e in
                                BroopFinalBOnbInfoRow(symbol: e.icon, title: e.title, message: e.body)
                            }
                        }
                    }
                    .padding(.bottom, 22)
                    BroopListHeader(title: String(localized: "Release notes"))
                        .padding(.horizontal, 4)
                    ForEach(Array(AppChangelog.releases.enumerated()), id: \.element.id) { index, release in
                        releaseCard(release, isLatest: index == 0)
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

            BroopFinalBOnbFooter {
                BroopFinalBOnbCapsuleButton(title: String(localized: "Got it"), action: onClose)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .background(BroopBackground())
        // A long changelog: open full height, with a grabber for swipe-to-dismiss.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(BroopPalette.bgTop)
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        ZStack {
            BroopNavTitle(title: String(localized: "What's New"))
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .frame(height: BroopMetrics.navHeight)
        .padding(.horizontal, BroopMetrics.page)
        .padding(.top, 8)
        .background(BroopPalette.bgTop)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            BroopMark()
                .fill(style: FillStyle(eoFill: true))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            BroopFinalBOnbTitleBlock(
                title: String(localized: "What's new in \(AppChangelog.currentVersion)"),
                subtitle: AppChangelog.releases.first?.title)
        }
        .padding(.top, 18)
        .padding(.horizontal, 4)
    }

    private func releaseCard(_ release: AppChangelog.Release, isLatest: Bool) -> some View {
        BroopCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BroopCaps("v\(release.version)", size: 10.5,
                              color: isLatest ? BroopPalette.connected : BroopPalette.textSecondary)
                    Spacer()
                    BroopCaps(release.date, size: 10, color: BroopPalette.textSecondary)
                }
                Text(verbatim: release.title)
                    .font(BroopType.demi(17))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(BroopPalette.textSecondary).frame(width: 4, height: 4)
                            .padding(.top, 8)
                        Text(Self.rendered(item))
                            .font(BroopType.regular(14))
                            .foregroundStyle(BroopPalette.textBody)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The changelog items carry `**bold**` leads; render that emphasis instead of printing the
    /// asterisks. Falls back to the plain string if the markdown does not parse.
    private static func rendered(_ item: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: item,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(item)
        }
        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                attributed[run.range].font = BroopType.demi(14)
                attributed[run.range].foregroundColor = BroopPalette.textPrimary
            }
        }
        return attributed
    }
}
#endif
