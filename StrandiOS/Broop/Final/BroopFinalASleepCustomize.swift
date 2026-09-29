#if os(iOS)
import SwiftUI

/// "CUSTOMIZE SLEEP": the Broop sleep screen's card arrangement, laid out like WHOOP's Customize Dashboard
/// (home-customize-dashboard-2025-05-1): the shown cards as tall caps rows with a drag handle, a red minus to
/// take one off, an "ADD TO SLEEP" rule with the hidden cards and a white plus, and an outlined SAVE pill.
///
/// It edits the same `EditableLayoutDraft` and writes the same two `@AppStorage` strings through
/// `SleepLayoutPrefs` as the classic `SleepCustomizationSheet`, so the classic Sleep screen and Android read
/// the same order. Last Night's Sleep (`.stages`) is always drawn at the top of the Broop screen and Hours of
/// Sleep (`.asleepDuration`) lives in its trend card, so neither is offered here; both keep their saved slot.
struct BroopFinalASleepCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    private let initialDraft: EditableLayoutDraft<SleepSection>
    @State private var draft: EditableLayoutDraft<SleepSection>

    /// Cards the Broop sleep screen draws by itself, whatever the arrangement says.
    private static let fixed: Set<SleepSection> = [.stages, .asleepDuration]

    init(sectionOrderRaw: Binding<String>, hiddenSectionsRaw: Binding<String>) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        let order = SleepLayoutPrefs.decodeOrder(sectionOrderRaw.wrappedValue)
        let hidden = Set(SleepLayoutPrefs.decodeHidden(hiddenSectionsRaw.wrappedValue))
        let d = EditableLayoutDraft(visible: order.filter { !hidden.contains($0) },
                                    hidden: order.filter { hidden.contains($0) })
        initialDraft = d
        _draft = State(initialValue: d)
    }

    private var shown: [SleepSection] { draft.visible.filter { !Self.fixed.contains($0) } }
    private var available: [SleepSection] { draft.hidden.filter { !Self.fixed.contains($0) } }
    private var isDirty: Bool { draft != initialDraft }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { section in
                        row(section, trailing: .handle)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Drag to reorder the cards under Last Night's Sleep. Take one off with the minus; it moves to the list below.")
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .listRowInsets(EdgeInsets(top: 0, leading: BroopMetrics.page + 4, bottom: 0, trailing: BroopMetrics.page))
                }

                Section {
                    if available.isEmpty {
                        Text("Every card is on your Sleep screen.")
                            .font(BroopType.regular(13))
                            .foregroundStyle(BroopPalette.textTertiary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: BroopMetrics.page + 4, bottom: 4, trailing: 4))
                    } else {
                        ForEach(available) { section in
                            row(section, trailing: .add)
                        }
                        .moveDisabled(true)
                    }
                } header: {
                    BroopFinalARule(title: String(localized: "Add to Sleep"))
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                        .listRowInsets(EdgeInsets(top: 0, leading: BroopMetrics.page, bottom: 0, trailing: BroopMetrics.page))
                }

                Section {
                    Button {
                        withAnimation(.snappy) {
                            draft = EditableLayoutDraft(visible: SleepSection.defaultOrder, allItems: SleepSection.defaultOrder)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold))
                            BroopCaps(String(localized: "Reset to default"), size: 11, color: BroopPalette.textSecondary)
                        }
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.top, 10)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .contentMargins(.horizontal, BroopMetrics.page, for: .scrollContent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BroopFinalAPill(title: String(localized: "Save"), kind: .outline, enabled: isDirty) { save() }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                                               startPoint: .top, endPoint: .center).ignoresSafeArea())
            }
            .background(BroopBackground())
            .broopFinalASheetBar(String(localized: "Customize Sleep"), onClose: { dismiss() })
        }
        .interactiveDismissDisabled(isDirty)
        .preferredColorScheme(.dark)
    }

    private enum Trailing { case handle, add }

    private func row(_ section: SleepSection, trailing: Trailing) -> some View {
        HStack(spacing: 14) {
            if trailing == .handle {
                Button {
                    withAnimation(.snappy) { draft.hide(section) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 19))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, BroopFinalAPalette.danger)
                }
                .buttonStyle(.plain)
                .disabled(draft.visible.count <= 1)
                .accessibilityLabel(Text(verbatim: String(localized: "Hide") + " " + section.title))
            }
            Image(systemName: section.customizationIcon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BroopPalette.textBody)
                .frame(width: 26)
                .accessibilityHidden(true)
            BroopCaps(section.title, size: 13)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if trailing == .add {
                Button {
                    withAnimation(.snappy) { draft.show(section) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: String(localized: "Show") + " " + section.title))
            }
        }
        .frame(minHeight: 66)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(
            RoundedRectangle(cornerRadius: BroopMetrics.tileRadius, style: .continuous)
                .fill(BroopFinalAPalette.rowFill)
                .padding(.vertical, 5)
        )
    }

    /// Reorders the offered cards among themselves; the fixed cards keep their index in the saved order.
    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = shown
        reordered.move(fromOffsets: offsets, toOffset: destination)
        var slots = reordered.makeIterator()
        draft.visible = draft.visible.map { Self.fixed.contains($0) ? $0 : (slots.next() ?? $0) }
    }

    private func save() {
        // Full order (shown then hidden) plus the hidden set, exactly as the classic sheet stores it.
        sectionOrderRaw = SleepLayoutPrefs.encode(draft.visible + draft.hidden)
        hiddenSectionsRaw = SleepLayoutPrefs.encodeHidden(draft.hidden)
        dismiss()
    }
}
#endif
