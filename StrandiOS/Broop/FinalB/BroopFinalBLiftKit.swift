#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import WhoopStore

// Shared pieces for the Strength Trainer sheets (program builder, exercise editor, spreadsheet import,
// past session, set editor, add exercise). Presentation only: persistence and every rule stay in the
// classic helpers (`LiftExerciseVocabulary`, `LiftSessionEditSheet.changes`, `LiftMetrics`, ...).

extension View {
    /// Chrome for a Strength Trainer sheet that owns a `NavigationStack`: the caps title in the system
    /// bar, an X on the left, the Broop background, white tint, dark.
    func broopFinalBSheetChrome<Trailing: View>(_ title: String, subtitle: String? = nil,
                                                onClose: @escaping () -> Void,
                                                @ViewBuilder trailing: () -> Trailing) -> some View {
        let trailingView = trailing()
        return self
            .background(BroopBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { BroopNavTitle(title: title, subtitle: subtitle) }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
                if Trailing.self != EmptyView.self {
                    ToolbarItem(placement: .topBarTrailing) { trailingView }
                }
            }
            .tint(BroopPalette.textPrimary)
            .preferredColorScheme(.dark)
    }

    func broopFinalBSheetChrome(_ title: String, subtitle: String? = nil,
                                onClose: @escaping () -> Void) -> some View {
        broopFinalBSheetChrome(title, subtitle: subtitle, onClose: onClose) { EmptyView() }
    }

    /// A "Done" key above the keyboard that resigns whichever field is focused.
    func broopFinalBKeyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(BroopType.demi(16))
            }
        }
    }

    /// WHOOP's input box: near-black fill, a thin grey border, bold white value.
    func broopFinalBInputBox(height: CGFloat = 48, number: Bool = false) -> some View {
        self
            .font(number ? BroopType.number(18) : BroopType.demi(16))
            .foregroundStyle(BroopPalette.textPrimary)
            .tint(BroopActivityPalette.mint)
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(BroopActivityPalette.input))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(BroopActivityPalette.inputBorder, lineWidth: 1))
    }

    /// The pinned bottom call to action of a builder page, over a fade so content scrolls under it. It
    /// steps aside while the keyboard is up, so it never sits on top of the field being typed into.
    func broopFinalBBottomCTA<CTA: View>(@ViewBuilder _ cta: () -> CTA) -> some View {
        modifier(BroopFinalBBottomCTA(cta: cta()))
    }
}

private struct BroopFinalBBottomCTA<CTA: View>: ViewModifier {
    let cta: CTA
    @State private var keyboardUp = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardUp {
                    VStack(spacing: 0) { cta }
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .background(
                            LinearGradient(stops: [.init(color: BroopPalette.bgBottom.opacity(0), location: 0),
                                                  .init(color: BroopPalette.bgBottom, location: 0.3)],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
    }
}

/// Caps field label above an input ("EXERCISE NAME").
struct BroopFinalBFieldLabel: View {
    let text: String
    var body: some View {
        BroopCaps(text, size: 10.5, color: BroopPalette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The black tile with the Broop mark that stands in for WHOOP's exercise photos.
struct BroopFinalBThumb: View {
    var width: CGFloat = 64
    var height: CGFloat = 50
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black)
            BroopMark().fill(style: FillStyle(eoFill: true))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: height * 0.5, height: height * 0.5)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Sentence-case section heading inside a builder ("Track Muscular Load", "Exercise Tags").
struct BroopFinalBHeading: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(BroopType.demi(20))
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Grey explanatory copy.
struct BroopFinalBNote: View {
    let text: String
    var color: Color = BroopPalette.textSecondary
    var body: some View {
        Text(verbatim: text)
            .font(BroopType.regular(13))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One remembered exercise, as the pickers list it.
struct BroopFinalBExerciseSuggestion: View {
    let row: LiftExerciseRow
    let onAdopt: () -> Void
    var onForget: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAdopt) {
                HStack(spacing: 12) {
                    BroopFinalBThumb(width: 52, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.name)
                            .font(BroopType.demi(15))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .lineLimit(1)
                        Text(verbatim: LiftMuscleSummary.line(primary: row.primaryMuscle, secondaries: row.secondaryMuscles))
                            .font(BroopType.regular(12))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BroopPressableStyle())
            .accessibilityLabel(Text(verbatim: row.name))
            if let onForget {
                // A typo becomes a permanent picker entry otherwise. Forgetting is safe: every logged set
                // snapshots its exercise name and muscles.
                Button(action: onForget) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Forget this exercise"))
            }
        }
        .padding(6)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
    }
}

/// The muscle classification, WHOOP's "Exercise Tags" look over the classic rules: a primary muscle
/// (a direct set) from a dropdown card, and the muscles it also works (half a set each) as chips. A
/// primary is never also a secondary.
struct BroopFinalBMusclePicker: View {
    @Binding var primary: LiftMuscle?
    @Binding var secondaries: Set<LiftMuscle>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopFinalBHeading(text: String(localized: "Muscles"))
            BroopFinalBNote(text: String(localized: "Asked once per exercise and remembered with its name. Direct sets count once, indirect sets count as a half: that split is what makes the weekly per-muscle figures mean anything."))
            BroopFinalBFieldLabel(text: String(localized: "Primary muscle")).padding(.top, 6)
            Menu {
                Button("Not classified") { primary = nil }
                ForEach(LiftMuscle.Region.allCases, id: \.self) { region in
                    Section(region.displayName) {
                        ForEach(LiftMuscle.inRegion(region), id: \.self) { muscle in
                            Button(muscle.displayName) {
                                primary = muscle
                                secondaries.remove(muscle)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    BroopCaps(primary?.displayName ?? String(localized: "Not classified"), size: 12.5,
                              color: primary == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BroopPalette.textPrimary)
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopPalette.card))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Primary muscle"))

            BroopFinalBFieldLabel(text: String(localized: "Also works · counted as half a set")).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(LiftMuscle.allCases, id: \.self) { muscle in
                    if muscle != primary { chip(muscle) }
                }
            }
        }
    }

    private func chip(_ muscle: LiftMuscle) -> some View {
        let on = secondaries.contains(muscle)
        return Button {
            if on { secondaries.remove(muscle) } else { secondaries.insert(muscle) }
        } label: {
            Text(verbatim: muscle.displayName)
                .font(BroopType.demi(13))
                .foregroundStyle(on ? BroopActivityPalette.mint : BroopPalette.textBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? BroopActivityPalette.mintTint : BroopPalette.card))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(on ? BroopActivityPalette.mint : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The small square "−" / "+" button of the set tables.
struct BroopFinalBSquareButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? BroopPalette.textPrimary : BroopPalette.textTertiary)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(BroopActivityPalette.inputBorder))
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// The alert shown when the exercise vocabulary is full, shared by the pickers.
extension View {
    func broopFinalBVocabularyFullAlert(_ limit: Binding<Int?>) -> some View {
        alert("You've saved the most exercises Broop remembers",
              isPresented: Binding(get: { limit.wrappedValue != nil }, set: { if !$0 { limit.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { limit.wrappedValue = nil }
        } message: {
            Text("Forget one you no longer use and this one will save. Your logged sessions are never affected.")
        }
    }
}
#endif
