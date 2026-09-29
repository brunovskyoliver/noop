#if os(iOS)
import SwiftUI

// Small building blocks shared by the final-pass rebuilds (Customize Sleep, the sleep-time editor, Caffeine,
// Mood, the Lab Book entry sheet, Storage, Apple Watch, the skin-temperature cards and the cycle tracker).
// Everything else comes from `BroopDesign` and the group kits.

enum BroopFinalAPalette {
    /// WHOOP's light-blue outline accent (the Customize Dashboard SAVE pill, checked boxes).
    static let accent = Color(broopHex: 0x5BA4E6)
    static let field = Color(broopHex: 0x161A1D)
    static let fieldBorder = Color.white.opacity(0.12)
    static let danger = Color(broopHex: 0xFF4D4D)
    static let rowFill = Color(broopHex: 0x2E3337)
    // Menstrual Cycle Insights phase colours (cycle-calendar-luteal / appstore-09-mci).
    static let menstrual = Color(broopHex: 0xF2665A)
    static let follicular = Color(broopHex: 0x8C8FE0)
    static let ovulatory = Color(broopHex: 0x2A8FA8)
    static let luteal = Color(broopHex: 0xB45CF0)
}

/// The bar of a Broop sheet with its own stack: X on the left, a caps title in the centre and an optional
/// trailing control (a check, SAVE). Matches CUSTOMIZE DASHBOARD / CUSTOMIZE JOURNAL.
struct BroopFinalASheetBar<Trailing: View>: ViewModifier {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var trailing: Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .principal) { BroopNavTitle(title: title) }
                if Trailing.self != EmptyView.self {
                    ToolbarItem(placement: .topBarTrailing) { trailing }
                }
            }
            .tint(BroopPalette.textPrimary)
    }
}

extension View {
    func broopFinalASheetBar<Trailing: View>(_ title: String, onClose: @escaping () -> Void,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(BroopFinalASheetBar(title: title, onClose: onClose, trailing: trailing))
    }

    func broopFinalASheetBar(_ title: String, onClose: @escaping () -> Void) -> some View {
        modifier(BroopFinalASheetBar(title: title, onClose: onClose) { EmptyView() })
    }
}

/// "ADD TO MY DASHBOARD ────": grey caps with a hairline running to the right edge.
struct BroopFinalARule: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            BroopCaps(title, size: 11, color: BroopPalette.textSecondary)
                .layoutPriority(1)
            Rectangle().fill(BroopPalette.hairline).frame(height: 1)
            if let trailing {
                BroopCaps(trailing, size: 10, color: BroopPalette.textTertiary).layoutPriority(1)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// WHOOP's full-width capsule: white fill with black caps (primary), a light-blue outline (save), or a red
/// outline (destructive).
struct BroopFinalAPill: View {
    enum Kind { case primary, outline, destructive, quiet }
    let title: String
    var kind: Kind = .primary
    var symbol: String? = nil
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).tint(kind == .primary ? .black : .white)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(foreground)
                }
                BroopCaps(title, size: 13, color: foreground)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(background)
            .contentShape(Capsule())
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .outline: return BroopFinalAPalette.accent
        case .destructive: return BroopFinalAPalette.danger
        case .quiet: return BroopPalette.textPrimary
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: Capsule().fill(Color.white)
        case .outline: Capsule().strokeBorder(BroopFinalAPalette.accent, lineWidth: 2)
        case .destructive: Capsule().strokeBorder(BroopFinalAPalette.danger.opacity(0.75), lineWidth: 1.5)
        case .quiet: Capsule().fill(BroopPalette.row)
        }
    }
}

/// A small tinted caps chip ("SOLID", "EST.", "APPLE HEALTH").
struct BroopFinalAChip: View {
    let text: String
    var tint: Color = BroopPalette.textBody

    var body: some View {
        BroopCaps(text, size: 9.5, color: tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.14)))
    }
}

/// The dark inset text field used by the entry forms.
struct BroopFinalAField<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(BroopType.medium(16))
            .foregroundStyle(BroopPalette.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopFinalAPalette.field))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BroopFinalAPalette.fieldBorder, lineWidth: 1))
    }
}

/// A lock glyph and the standing "never leaves your device" line, grey.
struct BroopFinalAPrivacyLine: View {
    var text = String(localized: "This never leaves your device unless you export a backup yourself.")

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BroopPalette.textTertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A caps card title with an optional right-hand chip, for the stacked cards on these screens.
struct BroopFinalACardTitle: View {
    let title: String
    var subtitle: String? = nil
    var chip: String? = nil
    var chipTint: Color = BroopPalette.textBody

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(title, size: 11.5)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(BroopType.regular(12.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let chip { BroopFinalAChip(text: chip, tint: chipTint) }
        }
    }
}

enum BroopFinalAFormat {
    private static let keyParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(fromKey key: String) -> Date? { keyParser.date(from: key) }

    /// "12 Jun" from a day key, in the app's locale.
    static func shortDay(_ key: String) -> String {
        guard let d = date(fromKey: key) else { return key }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.activeLocale))
    }

    /// "Tue, 12 Jun 2026" from a day key.
    static func longDay(_ key: String) -> String {
        guard let d = date(fromKey: key) else { return key }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(AppLanguage.activeLocale))
    }
}
#endif
