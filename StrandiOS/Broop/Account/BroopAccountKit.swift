#if os(iOS)
import SwiftUI
import StrandDesign

// Building blocks for the Account group (More, Settings, Device, integrations). Measured from the WHOOP
// More / My Account / Device Settings / Heart Rate Settings references at 3 px/pt: every menu entry is its
// own rounded card (about 56 pt tall, 10 pt apart) with a thin grey outline icon and a tracked caps label;
// settings pages put sentence-case titles beside their controls with a grey explanation underneath.

enum BroopAccountStyle {
    /// Card fill sampled from the More list (#2c3135 to #303539).
    static let card = Color(broopHex: 0x2E3337)
    /// The darker inset field behind numeric inputs (Heart Rate Settings).
    static let field = Color(broopHex: 0x161A1D)
    static let fieldBorder = Color.white.opacity(0.12)
    static let icon = Color(broopHex: 0x8A8F93)
    static let caption = Color(broopHex: 0x9EA3A7)
    /// "CONNECTED TO" green on Device Settings.
    static let connected = Color(broopHex: 0x55B923)
    static let batteryFill = Color(broopHex: 0x44CB04)
    static let broadcast = Color(broopHex: 0x0193E8)
    static let danger = Color(broopHex: 0xFF4D4D)
    static let rowRadius: CGFloat = BroopMetrics.tileRadius
    static let rowHeight: CGFloat = 56
    static let rowGap: CGFloat = 10
}

// MARK: - Routes

/// Account sub-pages, pushed by value so links inside them (to `BroopScreen`s) keep working: a value
/// link does nothing inside a page that was pushed with a view-destination link on a path-bound stack.
enum BroopAccountRoute: Hashable {
    case profile, heartRate, units, notifications, appearance, features, strap, data, scoring, experimental
    case about, integrations
}

struct BroopAccountRouteView: View {
    let route: BroopAccountRoute

    var body: some View {
        switch route {
        case .profile: BroopAccountProfilePage()
        case .heartRate: BroopAccountHeartRatePage()
        case .units: BroopAccountUnitsPage()
        case .notifications: BroopAccountNotificationsPage()
        case .appearance: BroopAccountAppearancePage()
        case .features: BroopAccountFeaturesPage()
        case .strap: BroopAccountStrapPage()
        case .data: BroopAccountDataPage()
        case .scoring: BroopAccountScoringPage()
        case .experimental: BroopAccountExperimentalPage()
        case .about: BroopAccountAboutPage()
        case .integrations: BroopAccountIntegrationsView()
        }
    }
}

// MARK: - Page chrome

extension View {
    /// A pushed Account page: the shared pinned header with a centred caps title.
    func broopAccountChrome(_ title: String) -> some View {
        broopNavPage(title)
    }
}

/// Scrolling page body with the standard side margins and room under the floating tab bar.
struct BroopAccountPage<Content: View>: View {
    var spacing: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, BroopMetrics.tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// Large sentence-case heading with an optional grey paragraph ("Heart Rate Zones" + the formula note).
struct BroopAccountHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(BroopType.demi(26))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(verbatim: detail)
                    .font(BroopType.regular(15))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tracked caps section label ("ACCOUNT & SETTINGS").
struct BroopAccountSectionLabel: View {
    let text: String
    var body: some View {
        BroopCaps(text, size: 12.5, color: BroopPalette.textBody)
            .padding(.leading, 1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled group of rows.
struct BroopAccountSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { BroopAccountSectionLabel(text: title) }
            content
            if let footer { BroopAccountFootnote(text: footer).padding(.horizontal, 4) }
        }
    }
}

// MARK: - Menu rows

/// The WHOOP menu entry: its own card, outline icon, caps label, optional grey line, no chevron.
struct BroopAccountMenuRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var tint: Color = BroopAccountStyle.icon

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 3) {
                BroopCaps(title, size: 13)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(BroopType.medium(13.5))
                        .foregroundStyle(BroopAccountStyle.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 20)
            Spacer(minLength: 8)
            if let trailing {
                Text(verbatim: trailing)
                    .font(BroopType.demi(13))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: BroopAccountStyle.rowHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A menu row that pushes a screen.
struct BroopAccountLink<Value: Hashable>: View {
    let value: Value
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        NavigationLink(value: value) {
            BroopAccountMenuRow(symbol: symbol, title: title, subtitle: subtitle, trailing: trailing)
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// A menu row that pushes an inline destination (sub-pages that are not `BroopScreen`s).
struct BroopAccountPageLink<Destination: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            BroopAccountMenuRow(symbol: symbol, title: title, subtitle: subtitle, trailing: trailing)
        }
        .buttonStyle(BroopPressableStyle())
    }
}

/// A menu row that runs an action; the caption sits under the card (Device Settings > Advanced).
struct BroopAccountActionCard: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    var tint: Color = BroopAccountStyle.icon
    var titleColor: Color = BroopPalette.textPrimary
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                HStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .padding(.leading, 14)
                    BroopCaps(title, size: 13, color: titleColor)
                        .padding(.leading, 18)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BroopAccountStyle.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(BroopPressableStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
            if let caption {
                Text(verbatim: caption)
                    .font(BroopType.medium(14))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
        }
    }
}

// MARK: - Grouped setting rows

/// A card holding settings rows separated by hairlines.
struct BroopAccountGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { subviews in
                        ForEach(subviews) { subview in
                            if subview.id != subviews.first?.id { BroopHairline().padding(.leading, 16) }
                            subview
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(BroopAccountStyle.card))
    }
}

/// Title (+ optional grey detail) on the left, any control on the right.
struct BroopAccountRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var titleColor: Color = BroopPalette.textPrimary
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(verbatim: title)
                    .font(BroopType.demi(15.5))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
                    .layoutPriority(1)
            }
            if let detail {
                Text(verbatim: detail)
                    .font(BroopType.regular(13))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }
}

struct BroopAccountToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        BroopAccountRow(title: title, detail: detail,
                        titleColor: enabled ? BroopPalette.textPrimary : BroopPalette.textTertiary) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BroopPalette.teal)
                .disabled(!enabled)
                .accessibilityLabel(Text(verbatim: title))
        }
    }
}

/// A picker shown as the current value with an up-down glyph; tapping opens a menu.
struct BroopAccountPicker<Value: Hashable>: View {
    let title: String
    var detail: String? = nil
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        BroopAccountRow(title: title, detail: detail) {
            Menu {
                Picker(selection: $selection) {
                    ForEach(options.indices, id: \.self) { i in
                        Text(verbatim: options[i].1).tag(options[i].0)
                    }
                } label: { EmptyView() }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: options.first(where: { $0.0 == selection })?.1 ?? "–")
                        .font(BroopType.demi(14.5))
                        .foregroundStyle(BroopAccountStyle.caption)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BroopAccountStyle.icon)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(verbatim: title))
        }
    }
}

/// A row that runs an action, with the value on the right and a chevron.
struct BroopAccountButtonRow: View {
    let title: String
    var value: String? = nil
    var detail: String? = nil
    var titleColor: Color = BroopPalette.textPrimary
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BroopAccountRow(title: title, detail: detail, titleColor: titleColor) {
                if showsChevron {
                    BroopAccountChevronValue(value: value)
                } else if let value {
                    Text(verbatim: value)
                        .font(BroopType.demi(14.5))
                        .foregroundStyle(BroopAccountStyle.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
    }
}

struct BroopAccountChevronValue: View {
    var value: String?
    var body: some View {
        HStack(spacing: 8) {
            if let value {
                Text(verbatim: value)
                    .font(BroopType.demi(14.5))
                    .foregroundStyle(BroopAccountStyle.caption)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BroopAccountStyle.icon)
        }
    }
}

/// The dark inset value field with − / + buttons ("156 bpm").
struct BroopAccountStepper: View {
    let value: String
    var unit: String? = nil
    var dimmed = false
    var accessibility: String
    var canDecrement = true
    var canIncrement = true
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            round("minus", enabled: canDecrement, action: onDecrement)
                .accessibilityLabel(Text("Decrease"))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(BroopType.number(18))
                    .foregroundStyle(dimmed ? BroopPalette.textTertiary : BroopPalette.textPrimary)
                    .monospacedDigit()
                if let unit {
                    Text(verbatim: unit)
                        .font(BroopType.medium(12))
                        .foregroundStyle(BroopAccountStyle.caption)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 58)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(BroopAccountStyle.field))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BroopAccountStyle.fieldBorder, lineWidth: 1))
            round("plus", enabled: canIncrement, action: onIncrement)
                .accessibilityLabel(Text("Increase"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: accessibility))
    }

    private func round(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(BroopPalette.row))
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

extension BroopAccountStepper {
    /// A stepper bound to a numeric value with a range and step.
    init<V: BinaryFloatingPoint>(value: Binding<V>, in range: ClosedRange<V>, step: V,
                                 text: String, unit: String? = nil, accessibility: String) {
        self.init(value: text, unit: unit, accessibility: accessibility,
                  canDecrement: value.wrappedValue > range.lowerBound,
                  canIncrement: value.wrappedValue < range.upperBound,
                  onDecrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
                  onIncrement: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) })
    }

    init(intValue: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         text: String? = nil, unit: String? = nil, accessibility: String) {
        self.init(value: text ?? "\(intValue.wrappedValue)", unit: unit, accessibility: accessibility,
                  canDecrement: intValue.wrappedValue > range.lowerBound,
                  canIncrement: intValue.wrappedValue < range.upperBound,
                  onDecrement: { intValue.wrappedValue = max(range.lowerBound, intValue.wrappedValue - step) },
                  onIncrement: { intValue.wrappedValue = min(range.upperBound, intValue.wrappedValue + step) })
    }
}

// MARK: - Buttons and notes

/// WHOOP's full-width capsule buttons: white with black caps (primary) or outlined (secondary).
struct BroopAccountButton: View {
    enum Kind { case primary, secondary, destructive }
    let title: String
    var kind: Kind = .primary
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(kind == .primary ? .black : .white) }
                BroopCaps(title, size: 13, color: foreground)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
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
        case .secondary: return BroopPalette.textPrimary
        case .destructive: return BroopAccountStyle.danger
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: Capsule().fill(Color.white)
        case .secondary: Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
        case .destructive: Capsule().strokeBorder(BroopAccountStyle.danger.opacity(0.7), lineWidth: 1.5)
        }
    }
}

/// "LEARN MORE →" style text link.
struct BroopAccountTextLink: View {
    let title: String
    var symbol = "arrow.right"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BroopCaps(title, size: 12.5)
                Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                    .foregroundStyle(BroopPalette.textPrimary)
            }
        }
        .buttonStyle(BroopPressableStyle())
    }
}

struct BroopAccountFootnote: View {
    let text: String
    var color: Color = BroopPalette.textSecondary
    var body: some View { BroopFootnote(text: text, color: color) }
}

/// A notice card: icon + text, amber for warnings.
struct BroopAccountNotice: View {
    var symbol = "exclamationmark.triangle.fill"
    var title: String? = nil
    let text: String
    var tint: Color = BroopPalette.warning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(verbatim: title)
                        .font(BroopType.demi(14.5))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: text)
                    .font(BroopType.regular(13))
                    .foregroundStyle(title == nil ? tint : BroopAccountStyle.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: BroopAccountStyle.rowRadius, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A small tinted status chip ("CONNECTED", "OFF").
struct BroopAccountChip: View {
    let text: String
    var tint: Color = BroopPalette.teal
    var body: some View {
        BroopCaps(text, size: 9.5, color: tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.14)))
    }
}

/// A read-only multi-line text sheet with Copy / Close (probe results, diagnostics).
struct BroopAccountTextSheet: View {
    let title: String
    var warning: String? = nil
    let text: String
    var waiting = false
    var waitingText = String(localized: "Waiting for the strap's reply…")
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let warning {
                        BroopAccountNotice(text: warning)
                    }
                    if waiting {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(verbatim: waitingText)
                                .font(BroopType.medium(15))
                                .foregroundStyle(BroopAccountStyle.caption)
                        }
                    } else {
                        Text(verbatim: text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(BroopPalette.textBody)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(BroopAccountStyle.field))
                    }
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BroopCaps(title, size: 12.5).lineLimit(1).minimumScaleFactor(0.6) }
                ToolbarItem(placement: .topBarLeading) {
                    Button { onClose() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
                if !waiting && !text.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { PlatformPasteboard.copy(text) } label: { Text("Copy").font(BroopType.demi(15)) }
                    }
                }
            }
            .tint(BroopPalette.textPrimary)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
