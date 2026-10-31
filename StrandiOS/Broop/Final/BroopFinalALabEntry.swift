#if os(iOS)
import SwiftUI
import StrandImport
import StrandAnalytics
import WhoopStore

/// "ADD A READING": the Lab Book entry sheet in Broop form. Step one picks a marker from `MarkerCatalog`
/// (searchable, as the list) or starts a custom one; step two takes the value (with the mmol/L ↔ mg/dL
/// switcher where the offers it), blood pressure as a systolic/diastolic pair, the date taken, a note
/// and the user's own reference range. The draft rows are built exactly as `MarkerEditorView` builds them
/// (`MarkerUnits` conversion to the canonical unit, `LabBookProjection` BP keys, `lab-book` manual source) and
/// handed to the same `onSave`.
struct BroopFinalALabEntrySheet: View {
    let onSave: (_ drafts: [LabMarkerRow]) async -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var selection: MarkerDefinition?
    @State private var addingCustom = false
    @State private var customName = ""
    @State private var customUnit = ""
    @State private var search = ""
    @State private var valueText = ""
    @State private var diastolicText = ""
    @State private var unit = ""
    @State private var unitChoice = 0
    @State private var takenAt = Date()
    @State private var note = ""
    @State private var referenceText = ""
    @State private var saving = false

    private enum Field: Hashable { case search, value, diastolic, note, reference, customName, customUnit }
    @FocusState private var focused: Field?

    private var picking: Bool { selection == nil && !addingCustom }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if picking { picker } else { reading }
                    BroopFootnote(text: String(localized: "Lab Book keeps your own numbers. It doesn't test, read, or judge them, and it's not medical advice. Everything stays on \(Platform.deviceNounPhrase)."))
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !picking {
                    BroopFinalAPill(title: saving ? String(localized: "Saving…") : String(localized: "Save"),
                                    busy: saving, enabled: !drafts.isEmpty) { save() }
                        .accessibilityLabel(Text("Save reading"))
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                                                   startPoint: .top, endPoint: .center).ignoresSafeArea())
                }
            }
            .background(BroopBackground())
            .broopFinalASheetBar(String(localized: "Add a reading"), onClose: { dismiss() })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    // MARK: Step 1: marker

    private var filtered: [MarkerDefinition] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return MarkerCatalog.builtIn }
        return MarkerCatalog.builtIn.filter { $0.displayName.lowercased().contains(q) || $0.key.contains(q) }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type in a number from your own report. It stays on \(Platform.deviceNounPhrase).")
                .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            BroopFinalAField {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BroopPalette.textSecondary)
                    TextField("Search markers (e.g. LDL, ferritin)", text: $search)
                        .focused($focused, equals: .search)
                        .autocorrectionDisabled()
                        .accessibilityLabel(Text("Search markers"))
                }
            }
            Button {
                addingCustom = true
                focused = .customName
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .regular)).frame(width: 24)
                    BroopCaps(String(localized: "Add a custom marker"), size: 11.5)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(BroopPalette.textSecondary)
                }
                .foregroundStyle(BroopPalette.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(RoundedRectangle(cornerRadius: BroopMetrics.tileRadius, style: .continuous).fill(BroopFinalAPalette.rowFill))
            }
            .buttonStyle(BroopPressableStyle())

            ForEach(LabMarkerCategory.allCases, id: \.self) { category in
                let defs = filtered.filter { $0.category == category }
                if !defs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        BroopFinalARule(title: category.displayName)
                        VStack(spacing: 0) {
                            ForEach(Array(defs.enumerated()), id: \.element.key) { i, def in
                                if i > 0 { BroopHairline().padding(.leading, 16) }
                                Button { choose(def) } label: {
                                    HStack(spacing: 10) {
                                        Text(verbatim: def.displayName)
                                            .font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Text(verbatim: def.canonicalUnit)
                                            .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 50)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(BroopPressableStyle())
                                .accessibilityLabel(Text(verbatim: "\(def.displayName), \(def.canonicalUnit)"))
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                    }
                }
            }
            if filtered.isEmpty {
                Text("No match. Add it as a custom marker below.")
                    .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }

    // MARK: Step 2: reading

    private var reading: some View {
        VStack(alignment: .leading, spacing: 22) {
            markerHeader
            if isBloodPressure { bloodPressure } else { valueBlock }
            labelled(String(localized: "Date taken")) {
                DatePicker("", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .accessibilityLabel(Text("Date and time taken"))
            }
            labelled(String(localized: "Note (optional)")) {
                BroopFinalAField {
                    TextField("e.g. fasting, morning draw", text: $note)
                        .focused($focused, equals: .note)
                        .accessibilityLabel(Text("Optional note"))
                }
            }
            labelled(String(localized: "Reference range from my report (optional)")) {
                VStack(alignment: .leading, spacing: 8) {
                    BroopFinalAField {
                        TextField("e.g. 2.0-5.0 (your report's own range)", text: $referenceText)
                            .focused($focused, equals: .reference)
                            .accessibilityLabel(Text("Reference range from your own report, optional"))
                    }
                    Text("NOOP never fills this in. It only shows back exactly what you type from your own report.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var markerHeader: some View {
        if addingCustom {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BroopCaps(String(localized: "Custom marker"), size: 11, color: BroopPalette.textSecondary)
                    Spacer()
                    changeButton(String(localized: "Back to the marker list")) { addingCustom = false }
                }
                labelled(String(localized: "Name")) {
                    BroopFinalAField {
                        TextField("e.g. Magnesium", text: $customName)
                            .focused($focused, equals: .customName)
                            .accessibilityLabel(Text("Custom marker name"))
                    }
                }
                labelled(String(localized: "Unit")) {
                    BroopFinalAField {
                        TextField("e.g. mmol/L", text: $customUnit)
                            .focused($focused, equals: .customUnit)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel(Text("Custom marker unit"))
                    }
                }
            }
        } else if let selection {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(selection.category.displayName, size: 10, color: BroopPalette.textSecondary)
                    Text(verbatim: selection.displayName).font(BroopType.demi(24)).foregroundStyle(BroopPalette.textPrimary)
                }
                Spacer()
                changeButton(String(localized: "Change")) { reset() }
                    .accessibilityLabel(Text("Change marker"))
            }
        }
    }

    private func changeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopCaps(title, size: 10.5, color: BroopFinalAPalette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(BroopFinalAPalette.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(BroopPressableStyle())
    }

    private var valueBlock: some View {
        labelled(String(localized: "Value")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("e.g. 3.1", text: $valueText)
                        .font(BroopType.number(40))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused($focused, equals: .value)
                    Text(verbatim: activeUnit).font(BroopType.demi(16)).foregroundStyle(BroopPalette.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopFinalAPalette.field))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BroopFinalAPalette.fieldBorder, lineWidth: 1))
                if unitOptions.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(unitOptions.indices, id: \.self) { i in
                            let on = unitChoice == i
                            Button { unitChoice = i } label: {
                                Text(verbatim: unitOptions[i])
                                    .font(BroopType.demi(13.5))
                                    .foregroundStyle(on ? Color.black : BroopPalette.textPrimary)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(Capsule().fill(on ? Color.white : BroopPalette.row))
                            }
                            .buttonStyle(BroopPressableStyle())
                        }
                        Spacer()
                    }
                    .accessibilityLabel(Text("Unit"))
                    Text("Stored as \(MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)). \(conversionNote)")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
    }

    private var bloodPressure: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labelled(String(localized: "Systolic")) {
                    numberBox("e.g. 120", $valueText, .value).accessibilityLabel(Text("Systolic blood pressure in mmHg"))
                }
                labelled(String(localized: "Diastolic")) {
                    numberBox("e.g. 80", $diastolicText, .diastolic).accessibilityLabel(Text("Diastolic blood pressure in mmHg"))
                }
            }
            Text("Entered together; stored as two markers so each lines up cleanly against your signals.")
                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberBox(_ placeholder: LocalizedStringKey, _ text: Binding<String>, _ field: Field) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(placeholder, text: text)
                .font(BroopType.number(32))
                .foregroundStyle(BroopPalette.textPrimary)
                .keyboardType(.decimalPad)
                .focused($focused, equals: field)
            Text(verbatim: "mmHg").font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopFinalAPalette.field))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BroopFinalAPalette.fieldBorder, lineWidth: 1))
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(label, size: 10, color: BroopPalette.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Logic (as MarkerEditorView)

    private func choose(_ def: MarkerDefinition) {
        selection = def
        unit = def.canonicalUnit
        unitChoice = 0
        focused = .value
    }

    private func reset() {
        selection = nil
        valueText = ""
        diastolicText = ""
        unitChoice = 0
        search = ""
    }

    private var markerKey: String { selection?.key ?? MarkerUnits.slug(customName) }
    private var category: LabMarkerCategory { selection?.category ?? .other }
    private var isBloodPressure: Bool { markerKey == LabBookProjection.bpSystolicKey }

    private var unitOptions: [String] {
        if addingCustom { return [customUnit.isEmpty ? "" : customUnit] }
        return MarkerUnits.options(for: markerKey, canonical: unit)
    }

    private var activeUnit: String {
        guard unitOptions.indices.contains(unitChoice) else { return unit }
        return unitOptions[unitChoice]
    }

    private var conversionNote: String {
        guard unitOptions.count > 1, activeUnit != MarkerUnits.canonicalUnit(for: markerKey, fallback: unit),
              let factor = MarkerUnits.factorToCanonical(markerKey: markerKey, from: activeUnit) else { return "" }
        return String(localized: "× \(MarkerUnits.factorLabel(factor)) on save.")
    }

    private var drafts: [LabMarkerRow] {
        if addingCustom {
            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !customUnit.trimmingCharacters(in: .whitespaces).isEmpty,
                  let v = parsed(valueText) else { return [] }
            return [row(key: markerKey, category: .other, value: v, unit: customUnit)]
        }
        guard selection != nil else { return [] }
        if isBloodPressure {
            guard let sys = parsed(valueText), let dia = parsed(diastolicText) else { return [] }
            return [
                row(key: LabBookProjection.bpSystolicKey, category: .bloodPressure, value: sys, unit: "mmHg"),
                row(key: LabBookProjection.bpDiastolicKey, category: .bloodPressure, value: dia, unit: "mmHg"),
            ]
        }
        guard let raw = parsed(valueText) else { return [] }
        let canonical = MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)
        let stored = MarkerUnits.toCanonical(markerKey: markerKey, value: raw, from: activeUnit)
        return [row(key: markerKey, category: category, value: stored, unit: canonical)]
    }

    private func row(key: String, category: LabMarkerCategory, value: Double, unit: String) -> LabMarkerRow {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let trimmedRef = referenceText.trimmingCharacters(in: .whitespaces)
        let epoch = Int(takenAt.timeIntervalSince1970)
        return LabMarkerRow(
            id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))",
            deviceId: repo.deviceId,
            markerKey: key,
            category: category.rawValue,
            day: LabBookFormat.dayKey(takenAt),
            takenAt: epoch,
            value: value,
            valueText: nil,
            unit: unit,
            source: "manual",
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            referenceText: trimmedRef.isEmpty ? nil : trimmedRef
        )
    }

    private func parsed(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) }

    private func save() {
        let rows = drafts
        guard !rows.isEmpty else { return }
        saving = true
        Task {
            await onSave(rows)
            dismiss()
        }
    }
}
#endif
