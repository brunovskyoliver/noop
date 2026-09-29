#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// One finished gym session, WHOOP's strength summary over the classic `LiftSessionDetailSheet`: the
/// session figures, every exercise with every set as performed and how it compares with last time, sets
/// per muscle and the RPE profile. Every figure is arithmetic from `LiftMetrics` over the sets listed on
/// the same page. Effort sits beside them and is never derived from weights: it is what was measured from
/// heart rate over the session's window.
struct BroopFinalBLiftSessionDetail: View {
    let session: LiftSessionRow
    var onChanged: () async -> Void = {}

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var sets: [LiftSetRow] = []
    @State private var workout: WorkoutRow?
    @State private var previousVolume: [String: Double] = [:]
    @State private var loaded = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var editing = false
    @State private var sessionRpe: Double?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private var durationSec: Int {
        guard let end = session.endTs else { return 0 }
        return max(0, end - session.startTs)
    }

    /// Sets actually performed; a 0-rep set was discarded or skipped and only Edit sets shows it.
    private var performed: [LiftSetRow] { sets.filter { LiftMetrics.isPerformed(reps: $0.reps) } }
    private var workingSetCount: Int { performed.filter { !$0.isWarmup }.count }

    private var storedSession: LiftSessionRow {
        var row = session
        row.sessionRpe = sessionRpe
        return row
    }

    private var title: String {
        if let name = session.programName, !name.isEmpty { return name }
        return String(localized: "Session")
    }

    private var subtitle: String {
        Date(timeIntervalSince1970: TimeInterval(session.startTs)).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !loaded {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 80)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        figures
                        exercises.padding(.top, 30)
                        if !performed.isEmpty {
                            muscles.padding(.top, 30)
                            rpe.padding(.top, 30)
                        }
                        BroopFinalBNote(text: String(localized: "Lifting figures are worked out from the sets above. Effort stays measured from heart rate and is never derived from weights and reps."))
                            .padding(.top, 24)
                        BroopActivityButton(title: String(localized: "Edit sets"), symbol: "pencil", kind: .outline, height: 52) {
                            editing = true
                        }
                        .padding(.top, 24)
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                BroopCaps(String(localized: "Delete session"), size: 11.5, color: BroopPalette.bandLow)
                            }
                            .foregroundStyle(BroopPalette.bandLow)
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(BroopPressableStyle())
                        .disabled(deleting)
                        // On the button, so the iOS 26 popover points at what was tapped.
                        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { Task { await deleteSession() } }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("\(performed.count) recorded sets will be removed, and so will the workout this session created. This cannot be undone.")
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, BroopMetrics.page)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .scrollIndicators(.hidden)
            .broopFinalBSheetChrome(title, subtitle: subtitle, onClose: { dismiss() })
            .navigationDestination(isPresented: $editing) {
                BroopFinalBLiftSessionEditor(session: storedSession, sets: sets) {
                    await load()
                    await onChanged()
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    // MARK: Figures

    private var figures: some View {
        let load = LiftMetrics.sessionLoad(sessionRpe: sessionRpe, durationSec: durationSec)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                tile(String(localized: "Volume"),
                     LiftFormat.weight(LiftMetrics.volumeLoadKg(performed), system: unitSystem),
                     String(localized: "\(workingSetCount) working sets"))
                tile(String(localized: "Effort"),
                     workout?.strain.map { LiftFormat.trim($0) } ?? "–",
                     String(localized: "measured from heart rate"), tint: BroopPalette.effort)
            }
            HStack(spacing: 10) {
                // The caption shows the SAME minutes the load was computed from, so it can be redone by hand.
                tile(String(localized: "Session load"),
                     load.map { String(Int($0.rounded())) } ?? "–",
                     sessionRpe.map { String(localized: "RPE \(LiftFormat.trim($0)) × \(LiftFormat.trim(Double(durationSec) / 60.0)) min") }
                        ?? String(localized: "not rated"))
                tile(String(localized: "Duration"), BroopActivityFormat.hms(Double(durationSec)),
                     BroopActivityFormat.span(session.startTs, session.endTs ?? session.startTs))
            }
            BroopFinalBNote(text: String(localized: "Volume compares only against this workout run again: 100 kg of leg press is not 100 kg of squat. The per-exercise figures below answer \"am I progressing\"."))
                .padding(.top, 4)
        }
    }

    private func tile(_ label: String, _ value: String, _ caption: String, tint: Color = BroopPalette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BroopCaps(label, size: 10.5, color: BroopPalette.textBody)
            Text(verbatim: value)
                .font(BroopType.number(26))
                .broopNumeral(26, color: value == "–" ? BroopPalette.textSecondary : tint)
                .foregroundStyle(value == "–" ? BroopPalette.textSecondary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: caption)
                .font(BroopType.medium(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercises

    @ViewBuilder private var exercises: some View {
        let summaries = LiftMetrics.perExercise(performed)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopFinalBHeading(text: String(localized: "Exercises"))
                if !summaries.isEmpty {
                    BroopCaps(String(localized: "As performed"), size: 10, color: BroopPalette.textSecondary).fixedSize()
                }
            }
            if performed.isEmpty {
                BroopFinalBNote(text: String(localized: "No sets were performed. Discarded sets stay under Edit sets as zeros you can fill in."))
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
            }
            ForEach(summaries, id: \.exercise) { exerciseCard($0) }
        }
    }

    private func exerciseCard(_ summary: LiftMetrics.ExerciseSummary) -> some View {
        let rows = performed.filter { $0.exercise == summary.exercise }.sorted { $0.ord < $1.ord }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BroopFinalBThumb(width: 64, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: summary.exercise).font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary).lineLimit(2)
                    Text(verbatim: rows.count == 1 ? String(localized: "1 Set") : String(localized: "\(rows.count) Sets"))
                        .font(BroopType.medium(13)).foregroundStyle(BroopActivityPalette.mint)
                    if let first = rows.first {
                        Text(verbatim: LiftMuscleSummary.line(primary: first.primaryMuscle, secondaries: first.secondaryMuscles))
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(broopHex: 0x353A3F))

            VStack(spacing: 0) {
                ForEach(rows, id: \.id) { setLine($0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            BroopHairline().padding(.horizontal, 16).padding(.top, 6)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    BroopCaps(String(localized: "Best set"), size: 10, color: BroopPalette.textSecondary)
                    Text(verbatim: bestSetText(summary)).font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary)
                    if let e1rm = summary.bestEstimatedOneRepMaxKg {
                        // "Estimated" travels with the number: a formula off one set, not a measured maximum.
                        Text(verbatim: String(localized: "≈ \(LiftFormat.weight(e1rm, system: unitSystem)) estimated 1RM"))
                            .font(BroopType.medium(12)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    BroopCaps(String(localized: "Volume"), size: 10, color: BroopPalette.textSecondary)
                    Text(verbatim: LiftFormat.weight(summary.volumeKg, system: unitSystem))
                        .font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary)
                    if let delta = volumeDeltaText(summary) {
                        Text(verbatim: delta).font(BroopType.demi(12)).foregroundStyle(deltaColor(summary))
                    }
                }
            }
            .padding(16)
        }
        .background(BroopPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setLine(_ row: LiftSetRow) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: row.isWarmup ? String(localized: "W") : "\(row.setIndex)")
                .font(BroopType.number(16))
                .foregroundStyle(row.isWarmup ? BroopPalette.warning : BroopPalette.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text(verbatim: setValueText(row))
                .font(BroopType.number(17))
                .foregroundStyle(row.isWarmup ? BroopPalette.textBody : BroopPalette.textPrimary)
            Spacer(minLength: 0)
            if let rpe = row.rpe {
                Text(verbatim: String(localized: "RPE \(LiftFormat.trim(rpe))"))
                    .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textBody)
            }
            if let rest = row.restSec {
                Text(verbatim: LiftFormat.duration(rest)).font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(minHeight: 34)
    }

    private func setValueText(_ row: LiftSetRow) -> String {
        let reps = row.reps.map(String.init) ?? "—"
        guard let kg = row.weightKg else { return String(localized: "\(reps) reps") }
        return "\(LiftFormat.weight(kg, system: unitSystem)) × \(reps)"
    }

    private func bestSetText(_ summary: LiftMetrics.ExerciseSummary) -> String {
        guard let reps = summary.bestReps else { return "—" }
        guard let kg = summary.bestWeightKg else { return String(localized: "\(reps) reps") }
        return "\(LiftFormat.weight(kg, system: unitSystem)) × \(reps)"
    }

    private func volumeDeltaText(_ summary: LiftMetrics.ExerciseSummary) -> String? {
        guard let now = summary.volumeKg, let before = previousVolume[summary.exercise], before > 0 else { return nil }
        let delta = now - before
        guard abs(delta) >= 0.5 else { return String(localized: "same as last time") }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(LiftFormat.weight(abs(delta), system: unitSystem)) vs last time"
    }

    private func deltaColor(_ summary: LiftMetrics.ExerciseSummary) -> Color {
        guard let now = summary.volumeKg, let before = previousVolume[summary.exercise], before > 0 else { return BroopPalette.textSecondary }
        return now > before ? BroopPalette.bandHigh : BroopPalette.textSecondary
    }

    // MARK: Sets per muscle

    @ViewBuilder private var muscles: some View {
        let counts = LiftMetrics.muscleCounts(performed)
        let ordered = LiftMuscle.ordered.filter { (counts.fractional[$0] ?? 0) > 0 }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                BroopFinalBHeading(text: String(localized: "Sets per muscle"))
                BroopCaps(String(localized: "Estimated"), size: 10, color: BroopPalette.textSecondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                if ordered.isEmpty {
                    BroopFinalBNote(text: String(localized: "None of these exercises has a muscle group yet. Add one on the exercise and every future session counts toward it."))
                } else {
                    ForEach(Array(ordered.enumerated()), id: \.element) { index, muscle in
                        if index > 0 { BroopHairline() }
                        HStack(spacing: 10) {
                            Text(verbatim: muscle.displayName).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                            Spacer(minLength: 0)
                            Text(verbatim: componentText(counts, muscle)).font(BroopType.medium(12)).foregroundStyle(BroopPalette.textSecondary)
                            Text(verbatim: LiftFormat.trim(counts.fractional[muscle] ?? 0))
                                .font(BroopType.number(18)).foregroundStyle(BroopPalette.effort)
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                        .frame(minHeight: 44)
                    }
                    BroopFinalBNote(text: String(localized: "Counted from the muscles you assigned each exercise: direct sets count once, indirect ones count as a half, the method the reference figures were derived under. An estimate from your own labels, not something measured off your body."))
                        .padding(.top, 10)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
    }

    private func componentText(_ counts: LiftMetrics.MuscleCounts, _ muscle: LiftMuscle) -> String {
        let d = counts.direct[muscle] ?? 0
        let i = counts.indirect[muscle] ?? 0
        if d > 0 && i > 0 { return String(localized: "\(d) direct · \(i) indirect") }
        if d > 0 { return String(localized: "\(d) direct") }
        return String(localized: "\(i) indirect")
    }

    // MARK: RPE

    private var rpe: some View {
        let p = LiftMetrics.rpeProfile(performed)
        return VStack(alignment: .leading, spacing: 12) {
            BroopFinalBHeading(text: String(localized: "How hard it felt"))
            VStack(alignment: .leading, spacing: 0) {
                BroopStatRowLite(label: String(localized: "Mean RPE"), value: p.mean.map { LiftFormat.trim($0) } ?? "–")
                BroopHairline()
                BroopStatRowLite(label: String(localized: "Sets at RPE \(LiftFormat.trim(p.threshold)) or above"),
                                 value: "\(p.setsAtOrAboveThreshold)")
                if p.unratedSets > 0 {
                    BroopFinalBNote(text: String(localized: "\(p.unratedSets) working sets weren't rated, so the mean is drawn from \(p.ratedSets)."))
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
    }

    // MARK: Load / delete (as the classic sheet)

    private func load() async {
        guard let store = await repo.storeHandle() else { sessionRpe = session.sessionRpe; loaded = true; return }
        sets = (try? await store.liftSets(sessionId: session.id)) ?? []
        let stored = try? await store.liftSessions(deviceId: session.deviceId, fromTs: session.startTs, toTs: session.startTs)
        // Re-read rather than trusting the row this sheet opened with: Edit sets can change it.
        if let row = stored?.first(where: { $0.id == session.id }) {
            sessionRpe = row.sessionRpe
        } else {
            sessionRpe = session.sessionRpe
        }
        let rows = (try? await store.workouts(deviceId: repo.deviceId, from: session.startTs - 1, to: session.startTs + 1, limit: 10)) ?? []
        workout = rows.first { $0.startTs == session.startTs && $0.sport == session.sport }
        var previous: [String: Double] = [:]
        for name in Set(performed.map(\.exercise)) {
            let before = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: name, before: session.startTs)) ?? []
            if let v = LiftMetrics.volumeLoadKg(before) { previous[name] = v }
        }
        previousVolume = previous
        loaded = true
    }

    /// Deletes the paired workout row too, so the day's Effort does not keep a session the user says
    /// never happened.
    private func deleteSession() async {
        guard !deleting, let store = await repo.storeHandle() else { return }
        deleting = true
        defer { deleting = false }
        _ = try? await store.deleteLiftSession(id: session.id)
        if let workout { await repo.deleteWorkout(workout) }
        await onChanged()
        dismiss()
    }
}

/// Label left, DIN value right.
private struct BroopStatRowLite: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(verbatim: label).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textBody)
            Spacer(minLength: 8)
            Text(verbatim: value).font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// Correct a finished session (WHOOP's set table): fix a number, add or drop a set, mark a warm-up, or
/// change the session RPE. The classic `LiftSessionEditSheet` rules apply unchanged: text is parsed once
/// on save, only edited fields are written back, a 0 empties on focus and returns if left empty, and only
/// this session changes, never the program.
struct BroopFinalBLiftSessionEditor: View {
    typealias Rows = LiftSessionEditSheet.ExerciseRows
    typealias Entry = LiftSessionEditSheet.Entry
    typealias SetForm = LiftSessionEditSheet.SetForm

    let session: LiftSessionRow
    let sets: [LiftSetRow]
    let onSaved: () async -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var exercises: [Rows] = []
    @State private var original: [Rows] = []
    @State private var sessionRpeText = ""
    @State private var originalSessionRpe = ""
    @State private var saving = false
    @State private var clearedZero: Field?
    @FocusState private var focused: Field?

    enum Field: Hashable { case weight(String), reps(String), rpe(String), sessionRpe }

    private var hasChanges: Bool { exercises != original || sessionRpeText != originalSessionRpe }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopFinalBNote(text: String(localized: "Fix numbers, or add and remove sets. Sets left at 0 reps stay out of the figures, and only this session changes, not the program."))
                BroopFinalBFieldLabel(text: String(localized: "How hard was the whole session? (1–10)")).padding(.top, 20)
                TextField("", text: Binding(get: { sessionRpeText },
                                            set: { sessionRpeText = $0.replacingOccurrences(of: ",", with: ".") }),
                          prompt: Text(verbatim: "—").foregroundColor(BroopPalette.textTertiary))
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: .sessionRpe)
                    .broopFinalBInputBox(number: true)
                    .frame(maxWidth: 140)
                    .padding(.top, 8)
                    .accessibilityLabel(Text("Session RPE"))

                VStack(spacing: 12) {
                    ForEach(exercises.indices, id: \.self) { exerciseCard($0) }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .broopFinalBBottomCTA {
            BroopActivityButton(title: String(localized: "Save changes"), kind: .mint, height: 56) { Task { await save() } }
                .disabled(saving || !hasChanges)
        }
        .broopNavPage(String(localized: "Edit sets"))
        .broopFinalBKeyboardDone()
        // A field holding 0 (a discarded set) empties when focused so typing replaces it; left empty it
        // goes back to 0 (an empty reps field would save as nil, which counts as performed).
        .onChange(of: focused) { _, now in
            restoreClearedZero()
            if swapText(now, "0", "") { clearedZero = now }
        }
        .onAppear(perform: fill)
    }

    private func exerciseCard(_ index: Int) -> some View {
        let group = exercises[index]
        let canAdd = group.entries.count < LiftSessionEngine.maxSetsPerExercise
        let canRemove = group.entries.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BroopFinalBThumb(width: 64, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: group.name).font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary).lineLimit(2)
                    Text(verbatim: group.entries.count == 1 ? String(localized: "1 Set") : String(localized: "\(group.entries.count) Sets"))
                        .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color(broopHex: 0x353A3F))

            VStack(alignment: .leading, spacing: 10) {
                BroopFinalBNote(text: String(localized: "Tap a set number to mark it a warm-up."))
                HStack(spacing: 8) {
                    Color.clear.frame(width: 26, height: 1)
                    BroopFinalBFieldLabel(text: unitSystem == .imperial ? String(localized: "Weight (lb)") : String(localized: "Weight (kg)"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BroopFinalBFieldLabel(text: String(localized: "Reps")).frame(maxWidth: .infinity, alignment: .leading)
                    BroopFinalBFieldLabel(text: String(localized: "RPE")).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                    setRow(exercise: index, position: position, entry: entry)
                }
                HStack(spacing: 8) {
                    Button { addSet(index) } label: {
                        HStack(spacing: 8) {
                            BroopCaps(String(localized: "Add set"), size: 12, color: canAdd ? BroopPalette.textPrimary : BroopPalette.textTertiary)
                            Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                                .foregroundStyle(canAdd ? BroopPalette.textPrimary : BroopPalette.textTertiary)
                        }
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BroopPressableStyle())
                    .disabled(!canAdd)
                    .accessibilityLabel(Text(verbatim: String(localized: "Add a set to \(group.name)")))
                    Spacer()
                    BroopFinalBSquareButton(symbol: "minus", label: String(localized: "Remove the last set from \(group.name)"),
                                            enabled: canRemove) { removeSet(index) }
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(BroopPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func setRow(exercise: Int, position: Int, entry: Entry) -> some View {
        let warmup = entry.form.isWarmup
        return HStack(spacing: 8) {
            Button { update(exercise, entry.id) { $0.form.isWarmup.toggle() } } label: {
                Text(verbatim: warmup ? String(localized: "W") : "\(position + 1)")
                    .font(BroopType.number(18))
                    .foregroundStyle(warmup ? BroopPalette.warning : BroopPalette.textSecondary)
                    .frame(width: 26, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(warmup ? Text("Warm-up set — tap to make it a working set")
                                       : Text(verbatim: String(localized: "Set \(position + 1) — tap to mark it a warm-up")))
            input(.weight(entry.id), binding(exercise, entry.id, \.weight))
            input(.reps(entry.id), binding(exercise, entry.id, \.reps))
            input(.rpe(entry.id), binding(exercise, entry.id, \.rpe))
        }
    }

    private func input(_ target: Field, _ text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(verbatim: "—").foregroundColor(BroopPalette.textTertiary))
            .keyboardType(.decimalPad)
            .focused($focused, equals: target)
            .broopFinalBInputBox(height: 44, number: true)
            .frame(maxWidth: .infinity)
    }

    private func binding(_ exercise: Int, _ id: String, _ key: WritableKeyPath<SetForm, String>) -> Binding<String> {
        Binding(get: { entry(exercise, id)?.form[keyPath: key] ?? "" },
                set: { text in update(exercise, id) { $0.form[keyPath: key] = text.replacingOccurrences(of: ",", with: ".") } })
    }

    private func entry(_ exercise: Int, _ id: String) -> Entry? {
        guard exercises.indices.contains(exercise) else { return nil }
        return exercises[exercise].entries.first { $0.id == id }
    }

    private func update(_ exercise: Int, _ id: String, _ change: (inout Entry) -> Void) {
        guard exercises.indices.contains(exercise),
              let i = exercises[exercise].entries.firstIndex(where: { $0.id == id }) else { return }
        change(&exercises[exercise].entries[i])
    }

    @discardableResult
    private func swapText(_ field: Field?, _ old: String, _ new: String) -> Bool {
        let target: (id: String, key: WritableKeyPath<SetForm, String>)
        switch field {
        case .weight(let id)?: target = (id, \.weight)
        case .reps(let id)?: target = (id, \.reps)
        default: return false
        }
        guard let exercise = exercises.firstIndex(where: { $0.entries.contains { $0.id == target.id } }),
              entry(exercise, target.id)?.form[keyPath: target.key] == old else { return false }
        update(exercise, target.id) { $0.form[keyPath: target.key] = new }
        return true
    }

    private func restoreClearedZero() {
        swapText(clearedZero, "", "0")
        clearedZero = nil
    }

    /// A new set starts from the exercise's last one, without its RPE (as the classic editor).
    private func addSet(_ exercise: Int) {
        restoreClearedZero()
        guard let last = exercises[exercise].entries.last,
              exercises[exercise].entries.count < LiftSessionEngine.maxSetsPerExercise else { return }
        exercises[exercise].entries.append(Entry(
            id: UUID().uuidString,
            form: SetForm(weight: last.form.weight, reps: last.form.reps, rpe: "", isWarmup: false)))
    }

    private func removeSet(_ exercise: Int) {
        guard exercises[exercise].entries.count > 1 else { return }
        exercises[exercise].entries.removeLast()
    }

    private func fill() {
        guard exercises.isEmpty else { return }
        var order: [String] = []
        for row in sets.sorted(by: { $0.ord < $1.ord }) where !order.contains(row.exercise) { order.append(row.exercise) }
        exercises = order.map { name in
            Rows(name: name, entries: sets
                .filter { $0.exercise == name }
                .sorted { ($0.setIndex, $0.ord) < ($1.setIndex, $1.ord) }
                .map { Entry(id: $0.id, form: LiftSessionEditSheet.form(for: $0, system: unitSystem)) })
        }
        original = exercises
        sessionRpeText = session.sessionRpe.map { LiftFormat.trim($0) } ?? ""
        originalSessionRpe = sessionRpeText
    }

    private func save() async {
        guard !saving, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }
        restoreClearedZero()
        let change = LiftSessionEditSheet.changes(from: sets, to: exercises, system: unitSystem)
        if !change.upserts.isEmpty { _ = try? await store.upsertLiftSets(change.upserts) }
        if !change.deletedIds.isEmpty { _ = try? await store.deleteLiftSets(ids: change.deletedIds) }
        if sessionRpeText != originalSessionRpe {
            var row = session
            row.sessionRpe = LiftFormat.number(sessionRpeText)
            _ = try? await store.upsertLiftSessions([row])
        }
        await onSaved()
        dismiss()
    }
}
#endif
