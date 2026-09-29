#if os(iOS)
import SwiftUI

// Shared pieces for the Broop launch gates (Terms, onboarding, What's New): the WHOOP-style
// onboarding page (back chevron, grey illustration, large sentence-case title, grey subtitle) and the
// full-width capsule buttons pinned to the bottom. Presentation only; the gates keep their logic.

/// Full-width capsule button. `.primary` is the white capsule with black caps text; `.outline` is the
/// thin white ring; a disabled primary greys out rather than fading, as WHOOP's NEXT does.
struct BroopFinalBOnbCapsuleButton: View {
    enum Kind { case primary, outline }
    let title: String
    var symbol: String? = nil
    var kind: Kind = .primary
    var height: CGFloat = 52
    /// Put the symbol after the title (a forward arrow) instead of before it.
    var symbolTrailing = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol, !symbolTrailing { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
                Text(verbatim: title.uppercased())
                    .font(BroopType.caps(13))
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let symbol, symbolTrailing { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background)
            .contentShape(Capsule())
        }
        .buttonStyle(BroopPressableStyle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return isEnabled ? .black : BroopPalette.textSecondary
        case .outline: return isEnabled ? BroopPalette.textPrimary : BroopPalette.textTertiary
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            Capsule().fill(isEnabled ? Color.white : BroopPalette.pillOuter)
        case .outline:
            Capsule().strokeBorder(isEnabled ? Color.white : BroopPalette.textTertiary, lineWidth: 1.5)
        }
    }
}

/// Small outlined caps capsule for a top-bar action ("HELP").
struct BroopFinalBOnbBarPill: View {
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title.uppercased())
                .font(BroopType.caps(11))
                .tracking(1.4)
                .foregroundStyle(active ? Color.black : BroopPalette.textPrimary)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background {
                    if active { Capsule().fill(Color.white) }
                    else { Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.3) }
                }
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// The back chevron WHOOP's onboarding pages carry top-left.
struct BroopFinalBOnbBackChevron: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
    }
}

/// The grey, softly lit illustration above an onboarding title (WHOOP draws a grey 3D padlock or
/// hands; Broop uses a grey SF Symbol on the same footprint).
struct BroopFinalBOnbIllustration: View {
    let symbol: String
    var size: CGFloat = 58

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(colors: [Color(broopHex: 0x8C9296), Color(broopHex: 0x51575B)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(height: size * 1.25, alignment: .bottomLeading)
            .accessibilityHidden(true)
    }
}

/// Large sentence-case title plus grey subtitle, left-aligned (WHOOP "Welcome to WHOOP!").
struct BroopFinalBOnbTitleBlock: View {
    let title: String
    var subtitle: String? = nil
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(verbatim: title)
                .font(BroopType.demi(29))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(BroopType.medium(16.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

/// Caps grey field label ("FIRST NAME").
struct BroopFinalBOnbFieldLabel: View {
    let text: String
    var body: some View {
        BroopCaps(text, size: 11.5, color: BroopPalette.textBody)
            .padding(.leading, 4)
    }
}

/// The dark, thin-bordered field WHOOP's onboarding inputs sit in.
struct BroopFinalBOnbField<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(broopHex: 0x0C0F11).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

/// Capsule segmented control: grey track, white selected pill with black caps text.
struct BroopFinalBOnbSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(verbatim: label(option).uppercased())
                        .font(BroopType.caps(11))
                        .tracking(1.1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.black : BroopPalette.textBody)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(BroopPalette.pillOuter))
    }
}

/// One tick line: small green check, grey body text.
struct BroopFinalBOnbCheckline: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(BroopPalette.connected)
                .frame(width: 18, height: 20)
            Text(verbatim: text)
                .font(BroopType.medium(15))
                .foregroundStyle(BroopPalette.textBody)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// An icon + title + body row on a Broop card, for expectation/info callouts.
struct BroopFinalBOnbInfoRow: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = BroopPalette.textPrimary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(BroopType.demi(15.5))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: message)
                    .font(BroopType.regular(14))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// WHOOP's square consent checkbox: a white rounded square, filled with a black tick when on.
struct BroopFinalBOnbCheckbox: View {
    let isOn: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOn ? Color.white : Color.clear)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 1.6)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// The white capsule pinned at the foot of a gate, over a short fade so scrolled content does not
/// butt against it.
struct BroopFinalBOnbFooter<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(alignment: .top) {
                LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .offset(y: -28)
                    .allowsHitTesting(false)
            }
    }
}

/// The thin onboarding progress track under the top bar.
struct BroopFinalBOnbProgressTrack: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BroopPalette.track)
                Capsule().fill(Color.white)
                    .frame(width: max(4, geo.size.width * progress))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
#endif
