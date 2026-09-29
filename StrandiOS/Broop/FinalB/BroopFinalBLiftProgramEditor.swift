#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// WHOOP's workout builder over the classic `LiftProgramEditorSheet` rules: a name, an optional note and
/// an ordered list of exercise lines with their targets. Lines are drafts until SAVE WORKOUT writes the
/// program and swaps its whole list through `replaceLiftProgramItems`. A session snapshots the program's
/// name, so renaming or deleting a workout never rewrites history.
struct BroopFinalBLiftProgramEditor: View {
    /// The program being edited, or nil to create one.
    let program: LiftProgramRow?
    let onSaved: () async -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var items: [LiftProgramItemRow] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var editingItem: BroopFinalBLiftItemTarget?
    @State private var confirmingDelete = false

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var isNew: Bool { program == nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !saving }
    private var title: String {
        if !trimmedName.isEmpty { return trimmedName }
        return isNew ? String(localized: "New workout") : String(localized: "Edit workout")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BroopFinalBFieldLabel(text: String(localized: "Workout name"))
                    TextField("", text: $name, prompt: Text("Upper A").foregroundColor(BroopPalette.textTertiary))
                        .broopFinalBInputBox()
                        .padding(.top, 8)
                        .accessibilityLabel(Text("Workout name"))
                    BroopFinalBFieldLabel(text: String(localized: "Note (optional)")).padding(.top, 20)
                    TextField("", text: $note, prompt: Text("Anything you want to remember").foregroundColor(BroopPalette.textTertiary))
                        // Capped at what the Strength Trainer list can show (two lines).
                        .onChange(of: note) { _, new in
                            if new.count > WhoopStore.maxProgramNoteLength { note = String(new.prefix(WhoopStore.maxProgramNoteLength)) }
                        }
                        .broopFinalBInputBox()
                        .padding(.top, 8)
                        .accessibilityLabel(Text("Note"))

                    HStack(alignment: .firstTextBaseline) {
                        BroopFinalBHeading(text: String(localized: "Exercises"))
                        if !items.isEmpty {
                            BroopCaps(String(localized: "\(items.count) in order"), size: 10, color: BroopPalette.textSecondary)
                                .fixedSize()
                        }
                    }
                    .padding(.top, 30)
                    BroopFinalBNote(text: String(localized: "Your targets for each exercise. What you actually lift is recorded when you run it."))
                        .padding(.top, 6)

                    VStack(spacing: 10) {
                        if items.isEmpty {
                            BroopFinalBNote(text: String(localized: "No exercises yet. Add the first one: type any name you like and Broop remembers it for next time."))
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemCard(item, index: index)
                        }
                        Button { editingItem = BroopFinalBLiftItemTarget(id: "new", item: nil) } label: {
                            HStack(spacing: 10) {
                                BroopCaps(String(localized: "Add exercise"), size: 12)
                                Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                            }
                            .foregroundStyle(BroopPalette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .foregroundStyle(BroopPalette.textTertiary))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BroopPressableStyle())
                    }
                    .padding(.top, 14)

                    if !isNew {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                BroopCaps(String(localized: "Delete workout"), size: 11.5, color: BroopPalette.bandLow)
                            }
                            .foregroundStyle(BroopPalette.bandLow)
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(BroopPressableStyle())
                        .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { Task { await deleteProgram() } }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Sessions you already logged from it are kept.")
                        }
                        .padding(.top, 26)
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .broopFinalBBottomCTA {
                BroopActivityButton(title: String(localized: "Save workout"), kind: .mint, height: 56) {
                    Task { await save() }
                }
                .disabled(!canSave)
                .accessibilityLabel(Text("Save workout"))
            }
            .broopFinalBSheetChrome(title, onClose: { dismiss() }) {
                Button { editingItem = BroopFinalBLiftItemTarget(id: "new", item: nil) } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                }
                .accessibilityLabel(Text("Add exercise"))
            }
            .broopFinalBKeyboardDone()
            .navigationDestination(item: $editingItem) { target in
                BroopFinalBLiftItemEditor(item: target.item) { saved in apply(saved, replacing: target.item) }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await loadIfNeeded() }
    }

    // MARK: Exercise card

    private func itemCard(_ item: LiftProgramItemRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { editingItem = BroopFinalBLiftItemTarget(id: item.id, item: item) } label: {
                HStack(spacing: 14) {
                    BroopFinalBThumb(width: 64, height: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.exercise)
                            .font(BroopType.demi(16))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .lineLimit(2)
                        Text(verbatim: setsLabel(item))
                            .font(BroopType.medium(13))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                .padding(8)
                .padding(.trailing, 8)
                .background(Color(broopHex: 0x353A3F))
                .contentShape(Rectangle())
            }
            .buttonStyle(BroopPressableStyle())
            .accessibilityLabel(Text(verbatim: "\(item.exercise), \(targetSummary(item))"))
            .accessibilityHint(Text("Edit exercise"))

            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: targetSummary(item))
                    .font(BroopType.number(15))
                    .foregroundStyle(BroopPalette.textBody)
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(BroopType.regular(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    BroopFinalBSquareButton(symbol: "arrow.up", label: String(localized: "Move up"), enabled: index > 0) {
                        move(from: index, by: -1)
                    }
                    BroopFinalBSquareButton(symbol: "arrow.down", label: String(localized: "Move down"),
                                            enabled: index < items.count - 1) {
                        move(from: index, by: 1)
                    }
                    Spacer()
                    Button { items.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .frame(width: 40, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove exercise"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(BroopPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setsLabel(_ item: LiftProgramItemRow) -> String {
        guard let sets = item.targetSets else { return String(localized: "No set target") }
        return sets == 1 ? String(localized: "1 Set") : String(localized: "\(sets) Sets")
    }

    /// "4 × 8 · 60 kg · max RPE 8 · 2:00 rest": only the parts that were filled in (classic wording).
    private func targetSummary(_ item: LiftProgramItemRow) -> String {
        var parts: [String] = []
        if let sets = item.targetSets {
            if let reps = item.targetRepsLow { parts.append("\(sets) × \(reps)") } else { parts.append(String(localized: "\(sets) sets")) }
        }
        if let kg = item.targetWeightKg { parts.append(LiftFormat.weight(kg, system: unitSystem)) }
        if let rpe = item.targetRpe { parts.append(String(localized: "max RPE \(LiftFormat.trim(rpe))")) }
        if let rest = item.restSec { parts.append(String(localized: "\(LiftFormat.duration(rest)) rest")) }
        return parts.isEmpty ? String(localized: "No targets set") : parts.joined(separator: " · ")
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { items.swapAt(index, target) }
    }

    private func apply(_ saved: LiftProgramItemRow, replacing old: LiftProgramItemRow?) {
        guard let old, let index = items.firstIndex(where: { $0.id == old.id }) else {
            items.append(saved)
            return
        }
        items[index] = saved
    }

    // MARK: Load / save (as the classic editor)

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let program else { return }
        name = program.name
        note = program.note ?? ""
        guard let store = await repo.storeHandle() else { return }
        items = (try? await store.liftProgramItems(programId: program.id)) ?? []
    }

    private func save() async {
        guard canSave, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }
        let now = Int(Date().timeIntervalSince1970)
        let id = program?.id ?? UUID().uuidString
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = LiftProgramRow(id: id, deviceId: repo.deviceId, name: trimmedName,
                                 note: trimmedNote.isEmpty ? nil : trimmedNote,
                                 createdAt: program?.createdAt ?? now, updatedAt: now,
                                 archived: program?.archived ?? false)
        _ = try? await store.upsertLiftPrograms([row])
        // `ord` is the array index: reordering the list is all it takes to reorder the program.
        let ordered = items.enumerated().map { index, item in
            LiftProgramItemRow(id: item.id, deviceId: repo.deviceId, programId: id, ord: index,
                               exercise: item.exercise, targetSets: item.targetSets,
                               targetRepsLow: item.targetRepsLow, targetRepsHigh: item.targetRepsHigh,
                               targetRpe: item.targetRpe, targetWeightKg: item.targetWeightKg,
                               restSec: item.restSec, note: item.note)
        }
        _ = try? await store.replaceLiftProgramItems(programId: id, items: ordered)
        await onSaved()
        dismiss()
    }

    private func deleteProgram() async {
        guard let program, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftProgram(id: program.id)
        await onSaved()
        dismiss()
    }
}

/// What the exercise editor is editing; "new" gives an added line an identity to push on.
struct BroopFinalBLiftItemTarget: Identifiable, Hashable {
    let id: String
    let item: LiftProgramItemRow?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One exercise line, WHOOP's CUSTOM EXERCISE page over the classic `LiftProgramItemSheet` rules. Broop
/// ships no exercise catalogue: the name is the user's own, remembered in `liftExercise` with the
/// muscles given here, and offered back next time. Every target is optional.
struct BroopFinalBLiftItemEditor: View {
    let item: LiftProgramItemRow?
    let onSave: (LiftProgramItemRow) -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []
    @State private var setsText = ""
    @State private var repsText = ""
    @State private var weightText = ""
    @State private var restText = ""
    @State private var maxRpeText = ""
    @State private var note = ""
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var loaded = false
    @State private var forgetting: LiftExerciseRow?
    @State private var vocabularyFullLimit: Int?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var trimmedExercise: String { exercise.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var maxRpe: Double? { LiftFormat.number(maxRpeText).flatMap { (1...10).contains($0) ? $0 : nil } }
    private var maxRpeInvalid: Bool { !maxRpeText.trimmingCharacters(in: .whitespaces).isEmpty && maxRpe == nil }
    private var canSave: Bool { !trimmedExercise.isEmpty && !maxRpeInvalid }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopFinalBFieldLabel(text: String(localized: "Exercise name"))
                TextField("", text: $exercise, prompt: Text("Incline dumbbell press").foregroundColor(BroopPalette.textTertiary))
                    .broopFinalBInputBox()
                    .padding(.top, 8)
                    .accessibilityLabel(Text("Exercise name"))
                BroopFinalBNote(text: String(localized: "Type any name you like. Broop remembers it, with the muscles you give it."))
                    .padding(.top, 8)

                let suggestions = LiftExerciseVocabulary.suggestions(vocabulary, matching: exercise)
                if !suggestions.isEmpty {
                    BroopFinalBFieldLabel(text: String(localized: "Used before")).padding(.top, 20)
                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.id) { row in
                            BroopFinalBExerciseSuggestion(row: row, onAdopt: { adopt(row) }, onForget: { forgetting = row })
                        }
                    }
                    .padding(.top, 8)
                }

                BroopFinalBMusclePicker(primary: $primary, secondaries: $secondaries).padding(.top, 30)

                BroopFinalBHeading(text: String(localized: "Targets")).padding(.top, 30)
                BroopFinalBNote(text: String(localized: "Every target is optional: this is the plan, not the record. What you actually lift is entered set by set during the session."))
                    .padding(.top, 6)
                Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                    GridRow {
                        numberField(String(localized: "Working sets"), "4", $setsText, decimal: false)
                        numberField(String(localized: "Reps"), "8", $repsText, decimal: false)
                    }
                    GridRow {
                        numberField(unitSystem == .imperial ? String(localized: "Weight (lb)") : String(localized: "Weight (kg)"),
                                    "60", $weightText, decimal: true)
                        numberField(String(localized: "Rest (seconds)"), "120", $restText, decimal: false)
                    }
                    GridRow {
                        numberField(String(localized: "Max RPE (1–10)"), "8", $maxRpeText, decimal: true)
                        Color.clear.frame(height: 0)
                    }
                }
                .padding(.top, 16)
                if maxRpeInvalid {
                    BroopActivityNotice(symbol: "exclamationmark.triangle.fill",
                                        text: String(localized: "Max RPE must be between 1 and 10."))
                        .padding(.top, 12)
                }
                // Max RPE is a ceiling, not effort planned in advance: shown grey in the session, and a
                // set left unrated saves it.
                BroopFinalBNote(text: String(localized: "Max RPE is a ceiling: the hardest a set should feel, where 10 means nothing left. It shows grey during the session, and a set you leave unrated saves it as its rating."))
                    .padding(.top, 12)

                BroopFinalBFieldLabel(text: String(localized: "Technique note")).padding(.top, 26)
                TextField("", text: $note, prompt: Text("Slow eccentric, pause at the bottom").foregroundColor(BroopPalette.textTertiary),
                          axis: .vertical)
                    .lineLimit(3...5)
                    .onChange(of: note) { _, new in
                        if new.count > WhoopStore.maxExerciseNoteLength { note = String(new.prefix(WhoopStore.maxExerciseNoteLength)) }
                    }
                    .padding(.vertical, 12)
                    .broopFinalBInputBox(height: 96)
                    .padding(.top, 8)
                    .accessibilityLabel(Text("Technique note"))
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .broopFinalBBottomCTA {
            BroopActivityButton(title: String(localized: "Save exercise"), kind: .mint, height: 56) { Task { await save() } }
                .disabled(!canSave)
        }
        .broopNavPage(item == nil ? String(localized: "Add exercise") : String(localized: "Edit exercise"))
        .broopFinalBKeyboardDone()
        .task { await loadIfNeeded() }
        .confirmationDialog(forgetting.map { Text(String(localized: "Forget \($0.name)?")) } ?? Text(""),
                            isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible) {
            Button("Forget", role: .destructive) { Task { await forget() } }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: {
            Text("It stops being offered here. Sessions you already logged with it are kept exactly as they are.")
        }
        .broopFinalBVocabularyFullAlert($vocabularyFullLimit)
    }

    private func numberField(_ label: String, _ placeholder: String, _ text: Binding<String>, decimal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopFinalBFieldLabel(text: label)
            TextField("", text: text, prompt: Text(verbatim: placeholder).foregroundColor(BroopPalette.textTertiary))
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .broopFinalBInputBox(number: true)
                .accessibilityLabel(Text(verbatim: label))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
    }

    private func forget() async {
        guard let row = forgetting, let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLiftExercise(id: row.id)
        vocabulary.removeAll { $0.id == row.id }
        forgetting = nil
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        if let item {
            exercise = item.exercise
            setsText = item.targetSets.map(String.init) ?? ""
            repsText = item.targetRepsLow.map(String.init) ?? ""
            weightText = item.targetWeightKg.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem)) } ?? ""
            restText = item.restSec.map(String.init) ?? ""
            maxRpeText = item.targetRpe.map { LiftFormat.trim($0) } ?? ""
            note = item.note ?? ""
        }
        guard let store = await repo.storeHandle() else { return }
        vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        if let item, let known = vocabulary.first(where: { $0.name == item.exercise }) {
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
    }

    private func save() async {
        guard canSave else { return }
        let name = trimmedExercise
        if let store = await repo.storeHandle() {
            do {
                try await LiftExerciseVocabulary.remember(
                    name, primary: primary, secondaries: LiftExerciseVocabulary.ordered(secondaries, excluding: primary),
                    known: vocabulary, deviceId: repo.deviceId, in: store)
            } catch let full as WhoopStore.LiftExerciseVocabularyFull {
                vocabularyFullLimit = full.limit
                return
            } catch {
                return
            }
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(LiftProgramItemRow(
            id: item?.id ?? UUID().uuidString, deviceId: repo.deviceId,
            programId: item?.programId ?? "", ord: item?.ord ?? 0, exercise: name,
            targetSets: Int(setsText.trimmingCharacters(in: .whitespaces)),
            targetRepsLow: Int(repsText.trimmingCharacters(in: .whitespaces)), targetRepsHigh: nil,
            targetRpe: maxRpe,
            targetWeightKg: LiftFormat.number(weightText).map { LiftFormat.kilograms(fromDisplay: $0, system: unitSystem) },
            restSec: Int(restText.trimmingCharacters(in: .whitespaces)),
            note: trimmedNote.isEmpty ? nil : trimmedNote))
        dismiss()
    }
}
#endif
