#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The running gym session in WHOOP's Strength Trainer style: LIVE SESSION (the ring timer for warm-up,
/// the active set or the rest, heart rate with the zone bar, the current exercise) and EXERCISES (every
/// set of every exercise, editable, startable in any order). All state lives in `LiftSessionController`,
/// so swiping the sheet away minimises the session to the bar and the clock, the strap gesture and the
/// buzzes keep running. Finishing and saving follow the classic `LiftSessionView` exactly.
struct BroopActivityLiftSessionView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss

    enum Tab: Hashable { case live, exercises }
    @State private var tab: Tab = .live
    @State private var showingFinish = false
    @State private var addingExercise = false
    @State private var scrollTarget: Int?
    @State private var draft: [FocusTarget: String] = [:]
    @FocusState private var focused: FocusTarget?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    enum FocusTarget: Hashable { case weight(LiftSlot), reps(LiftSlot), rpe(LiftSlot) }

    var body: some View {
        Group {
            if let engine = session.engine {
                VStack(spacing: 0) {
                    header(engine)
                    BroopUnderlineTabs(options: [Tab.live, Tab.exercises], selection: $tab) {
                        $0 == .live ? String(localized: "Live session") : String(localized: "Exercises")
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 8)
                    if tab == .live { liveTab(engine) } else { exercisesTab(engine) }
                    controlBar(engine)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell").font(.system(size: 30)).foregroundStyle(BroopPalette.textSecondary)
                    BroopCaps(String(localized: "No session running"), size: 12, color: BroopPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BroopBackground())
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .task(id: session.engine?.plan.map(\.exercise)) { await loadLastTime() }
        .onChange(of: focused) { _, now in draft = draft.filter { $0.key == now } }
        .sheet(isPresented: $showingFinish) {
            BroopActivityLiftFinishSheet { session.isPresented = false }
        }
        .sheet(isPresented: $addingExercise) {
            LiftSessionExerciseSheet { name, primary, secondaries in
                guard session.addExercise(name, primaryMuscle: primary, secondaryMuscles: secondaries) else { return }
                tab = .exercises
                scrollTarget = (session.engine?.plan.count ?? 1) - 1
            }
        }
    }

    // MARK: Header

    private func header(_ engine: LiftSessionEngine) -> some View {
        HStack(alignment: .top) {
            Menu {
                Button { session.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!engine.canUndo)
                Button { showingFinish = true } label: { Label("Finish session", systemImage: "flag.checkered") }
                Button { dismiss() } label: { Label("Minimise", systemImage: "chevron.down") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 3) {
                BroopCaps(session.programName ?? String(localized: "Session"), size: 13)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                LiftRunningClock { $0 - engine.startTs }
                    .font(BroopType.number(16))
                    .foregroundStyle(BroopPalette.textSecondary)
                Text(verbatim: String(localized: "\(engine.completedWorkingSets) of \(engine.plannedWorkingSets) sets done"))
                    .font(BroopType.demi(11.5))
                    .foregroundStyle(BroopPalette.textTertiary)
            }
            Spacer()
            Button { addingExercise = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 44, height: 44)
            }
            .disabled(engine.plan.count >= LiftSessionEngine.maxExercises)
            .accessibilityLabel(Text("Add exercise"))
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .padding(.horizontal, 12)
        .padding(.top, 14)
    }

    // MARK: Live tab

    private func liveTab(_ engine: LiftSessionEngine) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                BroopActivityLiftRing(engine: engine).padding(.top, 26)
                BroopActivityLiftHeart().padding(.top, 30)
                currentCard(engine).padding(.top, 22)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func currentCard(_ engine: LiftSessionEngine) -> some View {
        let isWorking: Bool = { if case .working = engine.stage { return true }; return false }()
        let slot = isWorking ? engine.currentSlot : (engine.upcomingSlot ?? engine.currentSlot)
        let item = slot.flatMap { engine.planItem(for: $0) }
        let shown = slot.map { s -> (reps: Int?, weight: Double?) in
            let typed = session.enteredValues(for: s)
            let grey = session.carry(for: s)
            return (typed.reps ?? grey.reps, typed.weightKg ?? grey.weightKg)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black)
                    BroopMark().fill(style: FillStyle(eoFill: true)).foregroundStyle(BroopPalette.textSecondary).frame(width: 24, height: 24)
                }
                .frame(width: 72, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    if !isWorking && item != nil {
                        BroopCaps(String(localized: "Next"), size: 10.5, color: BroopActivityPalette.mint)
                    }
                    Text(verbatim: item?.exercise ?? String(localized: "All sets done"))
                        .font(BroopType.demi(16))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .lineLimit(2)
                    if let item {
                        Text(verbatim: LiftMuscleSummary.line(primary: item.primaryMuscle, secondaries: item.secondaryMuscles))
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(BroopPalette.card)
            if let slot, let item {
                HStack(spacing: 0) {
                    stat(Text(verbatim: "\(slot.setIndex)").foregroundColor(BroopActivityPalette.mint) + Text(verbatim: "/\(item.targetSets)"),
                         String(localized: "Set"))
                    Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 40)
                    stat(Text(verbatim: shown?.reps.map(String.init) ?? "–"), String(localized: "Reps"))
                    Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 40)
                    stat(Text(verbatim: shown?.weight.map { LiftFormat.trim(LiftFormat.display(fromKilograms: $0, system: unitSystem)) } ?? "–"),
                         unitSystem == .imperial ? "lb" : "kg")
                }
                .padding(.vertical, 12)
                .background(Color(broopHex: 0x1E2226))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ value: Text, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(BroopType.number(24))
            BroopCaps(label, size: 10, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 18)
    }

    // MARK: Exercises tab

    private func exercisesTab(_ engine: LiftSessionEngine) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(engine.plan.enumerated()), id: \.offset) { index, item in
                        exerciseCard(engine, index: index, item: item).id(index)
                    }
                    Button { addingExercise = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            BroopCaps(String(localized: "Add exercise"), size: 11.5)
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(BroopPalette.textTertiary))
                    }
                    .buttonStyle(BroopPressableStyle())
                    .disabled(engine.plan.count >= LiftSessionEngine.maxExercises)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.currentSlot) { _, slot in
                guard let slot else { return }
                withAnimation { proxy.scrollTo(slot.exerciseIndex, anchor: .top) }
            }
            .onChange(of: scrollTarget) { _, t in
                guard let t else { return }
                withAnimation { proxy.scrollTo(t, anchor: .top) }
                scrollTarget = nil
            }
        }
    }

    private func exerciseCard(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        let slots = engine.slots(forExercise: index)
        let done = !slots.isEmpty && slots.allSatisfy { engine.isCompleted($0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black)
                    BroopMark().fill(style: FillStyle(eoFill: true)).foregroundStyle(BroopPalette.textSecondary).frame(width: 22, height: 22)
                }
                .frame(width: 64, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.exercise).font(BroopType.demi(15.5)).foregroundStyle(BroopPalette.textPrimary).lineLimit(2)
                    Text(verbatim: String(localized: "\(item.targetSets) Sets") + " · " +
                         LiftMuscleSummary.line(primary: item.primaryMuscle, secondaries: item.secondaryMuscles))
                        .font(BroopType.demi(12.5)).foregroundStyle(BroopPalette.textSecondary).lineLimit(1)
                }
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(BroopActivityPalette.mint)
                }
            }
            .padding(8)
            .background(BroopPalette.card)

            VStack(alignment: .leading, spacing: 8) {
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textBody)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
                HStack(spacing: 8) {
                    Color.clear.frame(width: 30)
                    BroopCaps(unitSystem == .imperial ? String(localized: "Weight (lb)") : String(localized: "Weight (kg)"), size: 9.5,
                              color: BroopPalette.textBody).frame(maxWidth: .infinity, alignment: .leading)
                    BroopCaps(String(localized: "Reps"), size: 9.5, color: BroopPalette.textBody).frame(maxWidth: .infinity, alignment: .leading)
                    BroopCaps(String(localized: "RPE"), size: 9.5, color: BroopPalette.textBody).frame(width: 52, alignment: .leading)
                    Color.clear.frame(width: 34)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                ForEach(slots, id: \.self) { slot in
                    setRow(engine, slot: slot)
                    if case .resting(let s, _) = engine.stage, s == slot { restBand(engine) }
                }
                HStack(spacing: 10) {
                    square("minus", enabled: engine.canRemoveSet(fromExercise: index)) { session.removeSet(fromExercise: index) }
                        .accessibilityLabel(Text("Remove the last set from \(item.exercise)"))
                    square("plus", enabled: item.targetSets < LiftSessionEngine.maxSetsPerExercise) { session.addSet(toExercise: index) }
                        .accessibilityLabel(Text("Add a set to \(item.exercise)"))
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(Color(broopHex: 0x1E2226))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func square(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? BroopPalette.textPrimary : BroopPalette.textTertiary)
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(BroopActivityPalette.inputBorder))
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!enabled)
    }

    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let recorded = engine.recordedSet(for: slot)
        let isWorking = engine.stage == .working(slot)
        let warm = session.isWarmup(slot)
        return HStack(spacing: 8) {
            Button { session.setWarmup(slot, !warm) } label: {
                Text(verbatim: warm ? String(localized: "W") : "\(slot.setIndex)")
                    .font(BroopType.number(20))
                    .foregroundStyle(warm ? BroopPalette.warning : (isWorking ? BroopPalette.textPrimary : BroopPalette.textSecondary))
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(warm ? String(localized: "Warm-up set — tap to make it a working set")
                                          : String(localized: "Set \(slot.setIndex) — tap to mark it a warm-up")))
            field(.weight(slot), text: weightBinding(slot), ghost: session.carry(for: slot).weightKg.map(display) ?? "—")
            field(.reps(slot), text: repsBinding(slot), ghost: session.carry(for: slot).reps.map(String.init) ?? "—")
            field(.rpe(slot), text: rpeBinding(slot), ghost: ghostRpe(engine, slot)).frame(width: 52)
            Button { session.start(slot) } label: {
                Image(systemName: recorded == nil ? "play.fill" : "checkmark.circle.fill")
                    .font(.system(size: recorded == nil ? 17 : 22, weight: .semibold))
                    .foregroundStyle(recorded == nil ? BroopPalette.textPrimary : BroopActivityPalette.mint)
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(recorded == nil ? "Start this set" : "Redo this set"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isWorking ? BroopActivityPalette.mintTint : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isWorking ? BroopActivityPalette.mint : .clear, lineWidth: 1.5)
        )
    }

    private func restBand(_ engine: LiftSessionEngine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill").font(.system(size: 11))
            BroopCaps(String(localized: "Rest period"), size: 10.5, color: BroopPalette.textBody)
            Spacer()
            LiftRunningClock { engine.restRemaining(now: $0) ?? 0 }
                .font(BroopType.number(16))
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(broopHex: 0x3A4556)))
    }

    private func field(_ target: FocusTarget, text: Binding<String>, ghost: String) -> some View {
        TextField(ghost, text: text)
            .keyboardType(.decimalPad)
            .font(BroopType.number(18))
            .foregroundStyle(BroopPalette.textPrimary)
            .focused($focused, equals: target)
            .padding(.horizontal, 10)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(BroopActivityPalette.input))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BroopActivityPalette.inputBorder, lineWidth: 1))
    }

    // MARK: Values (the classic sheet's bindings: typed text is held while a field is focused, and
    // every keystroke still lands in the controller and on disk)

    private func display(_ kg: Double) -> String { LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: unitSystem)) }

    private func ghostRpe(_ engine: LiftSessionEngine, _ slot: LiftSlot) -> String {
        if let planned = engine.planItem(for: slot)?.targetRpe { return LiftFormat.trim(planned) }
        return engine.previousSetInSession(for: slot)?.rpe.map { LiftFormat.trim($0) } ?? "—"
    }

    private func binding(_ f: FocusTarget, formatted: @escaping () -> String, store: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { draft[f] ?? formatted() }, set: { typed in
            let text = typed.replacingOccurrences(of: ",", with: ".")
            draft[f] = text
            store(text)
        })
    }

    private func weightBinding(_ slot: LiftSlot) -> Binding<String> {
        binding(.weight(slot), formatted: { session.enteredValues(for: slot).weightKg.map(display) ?? "" }) { text in
            let kg = LiftFormat.number(text).map { LiftFormat.kilograms(fromDisplay: $0, system: unitSystem) }
            write(slot) { $0.weightKg = kg }
        }
    }

    private func repsBinding(_ slot: LiftSlot) -> Binding<String> {
        binding(.reps(slot), formatted: { session.enteredValues(for: slot).reps.map(String.init) ?? "" }) { text in
            write(slot) { $0.reps = Int(text.trimmingCharacters(in: .whitespaces)) }
        }
    }

    private func rpeBinding(_ slot: LiftSlot) -> Binding<String> {
        binding(.rpe(slot), formatted: { session.enteredValues(for: slot).rpe.map { LiftFormat.trim($0) } ?? "" }) { text in
            write(slot) { $0.rpe = LiftFormat.number(text) }
        }
    }

    private func write(_ slot: LiftSlot, _ mutate: (inout LiftRecordedSet) -> Void) {
        let entered = session.enteredValues(for: slot)
        var row = LiftRecordedSet(exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex,
                                  weightKg: entered.weightKg, reps: entered.reps, rpe: entered.rpe,
                                  isWarmup: session.isWarmup(slot), startTs: 0, endTs: 0, restSec: nil)
        mutate(&row)
        session.updateSet(slot, weightKg: row.weightKg, reps: row.reps, rpe: row.rpe, isWarmup: row.isWarmup)
    }

    // MARK: Control bar

    private func controlBar(_ engine: LiftSessionEngine) -> some View {
        let working: Bool = { if case .working = engine.stage { return true }; return false }()
        return HStack(spacing: 10) {
            BroopActivityButton(title: actionLabel(engine), kind: working ? .outline : .mint, height: 58) { session.advance() }
            Button { showingFinish = true } label: {
                BroopCaps(String(localized: "Finish"), size: 11)
                    .frame(width: 78, height: 58)
                    .background(Capsule().fill(BroopActivityPalette.chip))
            }
            .buttonStyle(BroopPressableStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func actionLabel(_ engine: LiftSessionEngine) -> String {
        switch engine.stage {
        case .warmup: return String(localized: "Start first set")
        case .working: return String(localized: "End set")
        case .resting: return engine.allCompleted ? String(localized: "All sets done") : String(localized: "Start set")
        case .finished: return String(localized: "Saving…")
        }
    }

    /// What was lifted for each exercise LAST time, the middle layer of the grey numbers.
    private func loadLastTime() async {
        guard let engine = session.engine, let store = await repo.storeHandle() else { return }
        var out: [String: [Int: LiftSetCarry]] = [:]
        for exercise in NSOrderedSet(array: engine.plan.map(\.exercise)).compactMap({ $0 as? String }) {
            let rows = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: exercise, before: engine.startTs)) ?? []
            var bySet: [Int: LiftSetCarry] = [:]
            for r in rows where !r.isWarmup { bySet[r.setIndex] = LiftSetCarry(weightKg: r.weightKg, reps: r.reps) }
            out[exercise] = bySet
        }
        session.setLastSession(out)
    }
}

/// The big ring timer: WARM-UP counting up in grey, ACTIVE counting up on the blue-to-mint ring, REST
/// counting down on a silver ring with its progress. Redrawn once a second by its own timeline.
private struct BroopActivityLiftRing: View {
    let engine: LiftSessionEngine

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)), by: 1)) { ctx in
            let now = Int(ctx.date.timeIntervalSince1970)
            let d: CGFloat = 250
            ZStack {
                Circle().fill(Color(broopHex: 0x1A1E22)).frame(width: d - 30, height: d - 30)
                switch engine.stage {
                case .working:
                    Circle()
                        .stroke(AngularGradient(colors: [Color(broopHex: 0x1E7FE0), BroopActivityPalette.mint, Color(broopHex: 0x1E7FE0)],
                                                center: .center, startAngle: .degrees(-135), endAngle: .degrees(225)),
                                lineWidth: 9)
                    label(String(localized: "Active"), ActiveWorkoutClock.clock(now - engine.stageStartedAt), BroopActivityPalette.mint)
                case .resting(let slot, let endsAt):
                    let total = Double(max(1, engine.planItem(for: slot)?.restSec ?? LiftPlanItem.defaultRestSec))
                    let left = Double(max(0, endsAt - now))
                    Circle().stroke(Color(broopHex: 0x3A4556), lineWidth: 9)
                    Circle().trim(from: 0, to: left / total)
                        .stroke(BroopActivityPalette.rest, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    label(String(localized: "Rest"), ActiveWorkoutClock.clock(engine.restRemaining(now: now) ?? 0), .white, bell: true)
                default:
                    Circle().stroke(Color(broopHex: 0x3A4148), lineWidth: 9)
                    label(String(localized: "Warm-up"), ActiveWorkoutClock.clock(now - engine.stageStartedAt), BroopPalette.textPrimary)
                }
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity)
        }
    }

    private func label(_ title: String, _ clock: String, _ color: Color, bell: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if bell { Image(systemName: "bell.fill").font(.system(size: 12)) }
                BroopCaps(title, size: 15, color: color)
            }
            .foregroundStyle(color)
            Text(verbatim: clock).font(BroopType.number(64)).broopNumeral(64, color: color).foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

/// HEART RATE and the zone bar, the one view on the sheet that redraws per beat.
private struct BroopActivityLiftHeart: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BroopCaps(String(localized: "Heart rate"), size: 12, color: BroopPalette.textBody)
            Text(verbatim: model.bpm.map(String.init) ?? "–").font(BroopType.number(46)).broopNumeral(46)
            BroopActivityZoneBar(bpm: model.bpm, zoneSet: model.profile.hrZoneSet).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Finish

/// Finishing a session: session RPE, what to do with sets never started, whether the program keeps
/// changed set counts and added exercises, save, or discard. The save path is the classic
/// `LiftSessionView.save` (session row, set rows, program write-back, and the workout through the manual
/// path so Effort comes from measured heart rate only).
struct BroopActivityLiftFinishSheet: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    let onFinished: () -> Void

    private enum Unfinished: Hashable { case complete, discard }
    private enum ProgramChoice: Hashable { case update, keep }
    @State private var rpeText = ""
    @State private var saving = false
    @State private var unfinished: Unfinished?
    @State private var program: ProgramChoice?
    @State private var changes: [LiftSessionController.SetCountChange] = []
    @State private var confirmDiscard = false

    private var added: [LiftPlanItem] { session.engine?.plan.filter(\.addedInSession) ?? [] }

    var body: some View {
        let open = session.unfinishedSlots.count
        let asksProgram = !changes.isEmpty || !added.isEmpty
        let answered = (open == 0 || unfinished != nil) && (!asksProgram || program != nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BroopActivityHeader(title: String(localized: "Finish session"), leadingSymbol: "xmark", onBack: { dismiss() })
                Text("One number for the whole session, so a leg day can be compared with a run.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody)
                card {
                    BroopCaps(String(localized: "How hard was the whole session? (1–10)"), size: 10.5, color: BroopPalette.textBody)
                    TextField("7", text: $rpeText)
                        .keyboardType(.decimalPad)
                        .font(BroopType.number(28))
                        .padding(.horizontal, 12).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 8).fill(BroopActivityPalette.input))
                    Text("This is session RPE. Multiplied by the session's length it gives session load — the one figure that compares across completely different training.")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if open > 0 {
                    card {
                        BroopCaps(String(localized: "Unfinished sets"), size: 10.5, color: BroopPalette.textBody)
                        Text(verbatim: String(localized: "Sets not started: \(open)")).font(BroopType.medium(15))
                        choice([(String(localized: "Complete them"), Unfinished.complete), (String(localized: "Discard them"), .discard)], $unfinished)
                        Text("Completing saves them with the grey numbers shown. Discarding keeps them out of every figure; they stay under Edit sets as zeros you can fill in later.")
                            .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if unfinished == .discard, !LiftSessionController.anyPerformed(session.setsToSave(completingUnfinished: false)) {
                            Text("Every set would be a zero, so discarding saves no session and no workout.")
                                .font(BroopType.regular(12)).foregroundStyle(BroopPalette.warning)
                        }
                    }
                }
                if asksProgram {
                    card {
                        BroopCaps(String(localized: "Program"), size: 10.5, color: BroopPalette.textBody)
                        Text(question).font(BroopType.medium(15)).fixedSize(horizontal: false, vertical: true)
                        ForEach(changes, id: \.itemId) { c in
                            Text(verbatim: "\(c.exercise): \(c.from) → \(c.to) sets").font(BroopType.number(14)).foregroundStyle(BroopPalette.textBody)
                        }
                        ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: String(localized: "New: \(line.exercise) · sets: \(line.targetSets)"))
                                .font(BroopType.number(14)).foregroundStyle(BroopPalette.textBody)
                        }
                        choice([(String(localized: "Update program"), ProgramChoice.update), (String(localized: "Keep as it was"), .keep)], $program)
                    }
                }
                BroopActivityButton(title: String(localized: "Save session"), kind: .mint, height: 56) { Task { await save() } }
                    .disabled(saving || !answered)
                if !answered {
                    Text("Choose an option above to save.").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
                Button(role: .destructive) { confirmDiscard = true } label: {
                    Label("Discard session", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .font(BroopType.demi(15))
                .foregroundStyle(BroopPalette.bandLow)
                .disabled(saving)
                .padding(.top, 4)
            }
            .padding(BroopMetrics.page)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(broopHex: 0x1E2327).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                session.discard()
                onFinished()
            }
            Button("Keep going", role: .cancel) { }
        } message: {
            Text("\(session.engine?.completedWorkingSets ?? 0) recorded sets will be thrown away. Nothing is saved and no workout is created.")
        }
        .task { await loadChanges() }
    }

    private var question: LocalizedStringKey {
        switch (!changes.isEmpty, !added.isEmpty) {
        case (true, true): return "You added exercises and changed the number of sets. Keep these changes in the program for next time?"
        case (false, true): return "You added exercises. Add them to the program for next time?"
        default: return "You changed the number of sets. Keep the new counts in the program for next time?"
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
    }

    private func choice<T: Hashable>(_ options: [(String, T)], _ selection: Binding<T?>) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.1) { title, value in
                Button { selection.wrappedValue = value } label: {
                    BroopCaps(title, size: 10.5, color: selection.wrappedValue == value ? .black : BroopPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(selection.wrappedValue == value ? BroopActivityPalette.mint : BroopActivityPalette.chip))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadChanges() async {
        guard let programId = session.programId, let plan = session.engine?.plan,
              let store = await repo.storeHandle(),
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        changes = LiftSessionController.setCountChanges(plan: plan, program: rows)
    }

    private func save() async {
        guard !saving, let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }
        session.finish()
        guard let engine = session.engine else { return }
        let endTs = Int(Date().timeIntervalSince1970)
        let sessionId = UUID().uuidString
        let finished = session.setsToSave(completingUnfinished: unfinished == .complete)
        guard LiftSessionController.anyPerformed(finished) else {
            await writeProgram(store: store, plan: engine.plan, sets: finished)
            await finishAndDismiss()
            return
        }
        let row = LiftSessionRow(id: sessionId, deviceId: repo.deviceId, startTs: engine.startTs, endTs: endTs,
                                 sport: LiftSessionView.sport, programId: session.programId, programName: session.programName,
                                 sessionRpe: LiftFormat.number(rpeText), note: session.programName)
        _ = try? await store.upsertLiftSessions([row])
        let rows = finished.enumerated().map { ord, s -> LiftSetRow in
            let item = engine.planItem(for: s.slot)
            return LiftSetRow(id: UUID().uuidString, deviceId: repo.deviceId, sessionId: sessionId, ord: ord,
                              exercise: item?.exercise ?? "", primaryMuscle: item?.primaryMuscle,
                              secondaryMuscles: item?.secondaryMuscles ?? [], setIndex: s.slot.setIndex,
                              weightKg: s.weightKg, reps: s.reps, rpe: s.rpe, isWarmup: s.isWarmup,
                              startTs: s.startTs, endTs: s.endTs, restSec: s.restSec, note: nil)
        }
        _ = try? await store.upsertLiftSets(rows)
        await writeProgram(store: store, plan: engine.plan, sets: finished)
        let workout = WorkoutRow(startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport, source: "manual",
                                 durationS: Double(max(0, endTs - engine.startTs)), energyKcal: nil, avgHr: nil, maxHr: nil,
                                 strain: nil, distanceM: nil, zonesJSON: nil, notes: session.programName, steps: nil)
        await repo.saveManualWorkout(workout)
        await finishAndDismiss()
    }

    private func finishAndDismiss() async {
        session.finishedSaving()
        await repo.refresh()
        onFinished()
    }

    private func writeProgram(store: WhoopStore, plan: [LiftPlanItem], sets: [LiftSessionController.FinishedSet]) async {
        guard let programId = session.programId,
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        let edited = LiftSessionController.programAfterSession(sets, plan: plan, program: rows,
                                                                keepingChanges: program == .update,
                                                                programId: programId, deviceId: repo.deviceId)
        guard edited != rows else { return }
        _ = try? await store.replaceLiftProgramItems(programId: programId, items: edited)
    }
}

// MARK: - Minimised bar

/// The running session condensed above the tab bar: exercise, status and next set on the left, heart
/// rate over the stage clock on the right, and the same advance action the sheet has. Reads the same
/// `LiftSessionController.presentation` the Lock Screen does.
struct BroopActivityLiftBar: View {
    @EnvironmentObject var session: LiftSessionController
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var body: some View {
        if let engine = session.engine, let shown = session.presentation(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric) {
            let tint: Color = { if case .working = engine.stage { return BroopActivityPalette.mint }; return BroopActivityPalette.rest }()
            Button { session.isPresented = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: shown.exercise).font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary).lineLimit(1)
                        Text(verbatim: shown.detail.map { "\(shown.status) — \($0)" } ?? shown.status)
                            .font(BroopType.demi(11.5)).foregroundStyle(BroopPalette.textBody).lineLimit(1)
                        Text(verbatim: shown.next).font(BroopType.regular(11)).foregroundStyle(BroopPalette.textSecondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        LiftHeartRate(style: .compact)
                        LiftRunningClock { now in engine.restRemaining(now: now) ?? now - engine.stageStartedAt }
                            .font(BroopType.number(18))
                            .foregroundStyle(tint)
                            .fixedSize()
                    }
                    Button { session.advance() } label: {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Next"))
                }
                .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
                .background(Capsule().fill(Color(broopHex: 0x1E2327).opacity(0.96)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open the running session"))
        }
    }
}
#endif
