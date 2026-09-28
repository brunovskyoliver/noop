#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// WHOOP's ADD ACTIVITY / EDIT ACTIVITY sheet over the classic `ManualWorkoutSheet` rules: the same
/// inputs (sport, start, end, duration, distance, average HR, calories), validated by the same
/// `WorkoutSource.buildManualRowFromSpan`, and carrying captured fields over with
/// `WorkoutSource.preservingCaptured`, so an edit here and an edit on the classic sheet store the same row.
struct BroopActivityEditSheet: View {
    let editing: WorkoutRow?
    /// True for "Duplicate as manual": the form is pre-filled from `editing` but saving is a pure add.
    var isCopy = false
    let onSave: (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sport: String
    @State private var start: Date
    @State private var end: Date
    @State private var avgHrText: String
    @State private var kcalText: String
    @State private var distanceText: String
    @State private var picking = false
    @State private var openChip: Chip?
    @FocusState private var focused: Field?

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }

    private enum Chip { case start, end }
    private enum Field: Hashable { case distance, avgHr, kcal }

    init(editing: WorkoutRow?, isCopy: Bool = false, onSave: @escaping (_ row: WorkoutRow, _ replacing: WorkoutRow?) -> Void) {
        self.editing = editing
        self.isCopy = isCopy
        self.onSave = onSave
        let e = editing
        _sport = State(initialValue: e.map { WorkoutSource.editableSport($0.sport) } ?? "")
        // A fresh add opens on a valid 45-minute session ending now, as the classic sheet does.
        let now = Date()
        _start = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.startTs)) } ?? now.addingTimeInterval(-45 * 60))
        _end = State(initialValue: e.map { Date(timeIntervalSince1970: TimeInterval($0.endTs)) } ?? now)
        _avgHrText = State(initialValue: e?.avgHr.map(String.init) ?? "")
        _kcalText = State(initialValue: e?.energyKcal.map { String(Int($0.rounded())) } ?? "")
        let bodySystem = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
        let sys = UnitPrefs.resolveDistance(system: bodySystem,
                                            override: UserDefaults.standard.string(forKey: UnitPrefs.distanceSystemKey) ?? "")
        _distanceText = State(initialValue: e?.distanceM.map { Self.entry($0, system: sys) } ?? "")
    }

    private static func entry(_ meters: Double, system: UnitSystem) -> String {
        let km = meters / 1000
        var s = String(format: "%.2f", system == .imperial ? km * UnitFormatter.milesPerKilometer : km)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private var isAdd: Bool { editing == nil || isCopy }

    var body: some View {
        VStack(spacing: 0) {
            BroopActivityHeader(title: isAdd ? String(localized: "Add activity") : String(localized: "Edit activity"),
                                leadingSymbol: "xmark", onBack: { dismiss() })
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isAdd {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill").foregroundStyle(Color(broopHex: 0x5BA4E6))
                            Text("Log an activity you tracked somewhere else. Broop fills Effort, heart rate and calories from your strap when it has data for that time.")
                                .font(BroopType.medium(13))
                                .foregroundStyle(BroopPalette.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(broopHex: 0x1D2A36)))
                        .padding(.bottom, 14)
                    }

                    Button { picking = true } label: {
                        HStack(spacing: 14) {
                            WorkoutTypeIcon(workoutType: sport.isEmpty ? "Other" : sport, size: 22, weight: .semibold,
                                            color: BroopPalette.textSecondary)
                            BroopCaps(sport.isEmpty ? String(localized: "Choose activity") : sport, size: 12,
                                      color: sport.isEmpty ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(height: 60)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BroopActivityPalette.chip))
                    }
                    .buttonStyle(BroopPressableStyle())

                    BroopActivityDivider(title: String(localized: "Time")).padding(.top, 26).padding(.bottom, 6)
                    chipRow(String(localized: "Start Time"), date: start, chip: .start)
                    if openChip == .start {
                        DatePicker("", selection: startBinding, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel).labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                    chipRow(String(localized: "End Time"), date: end, chip: .end)
                    if openChip == .end {
                        DatePicker("", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel).labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Text("Duration").font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                        Spacer()
                        Stepper(value: durationBinding, in: 1...(24 * 60), step: 5) {
                            Text(verbatim: durationLabel)
                                .font(BroopType.number(17))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .fixedSize()
                        .accessibilityLabel(Text("Duration in minutes"))
                    }
                    .frame(minHeight: 50)

                    BroopActivityDivider(title: String(localized: "Details")).padding(.top, 22).padding(.bottom, 8)
                    field(String(localized: "Distance"), text: $distanceText, unit: UnitFormatter.distanceUnit(distanceSystem), which: .distance)
                    field(String(localized: "Avg HR"), text: $avgHrText, unit: "bpm", which: .avgHr)
                    field(String(localized: "Calories"), text: $kcalText, unit: "kcal", which: .kcal)

                    if let note = validationNote {
                        BroopActivityNotice(symbol: "exclamationmark.triangle.fill", text: note).padding(.top, 16)
                    }
                    if avgHrEditedNote {
                        BroopActivityNotice(symbol: "info.circle.fill",
                                            text: String(localized: "Avg HR is shown as typed. The HR graph, zones and Effort stay from the recorded session."),
                                            tint: BroopPalette.textSecondary)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            BroopActivityButton(title: String(localized: "Save"), kind: .filled) { save() }
                .disabled(builtRow == nil)
                .padding(.horizontal, BroopMetrics.page)
                .padding(.bottom, 12)
        }
        .background(Color(broopHex: 0x1E2327).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $picking) {
            BroopActivityTypePicker(title: String(localized: "Activity type"), current: sport, allowsCustom: true,
                                    recordsRecent: false) { sport = $0 }
        }
    }

    private func chipRow(_ title: String, date: Date, chip: Chip) -> some View {
        HStack {
            Text(verbatim: title).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
            Spacer()
            Button {
                withAnimation(.snappy) { openChip = openChip == chip ? nil : chip }
            } label: {
                Text(verbatim: date.formatted(.dateTime.month(.abbreviated).day()) + " " + String(localized: "at") + " " +
                     AppClock.hourMinuteFormatter().string(from: date))
                    .font(BroopType.number(15))
                    .foregroundStyle(openChip == chip ? Color.black : BroopPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(openChip == chip ? BroopActivityPalette.mint : BroopActivityPalette.chip))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 50)
    }

    private func field(_ title: String, text: Binding<String>, unit: String, which: Field) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: title).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
            Spacer()
            TextField(String(localized: "optional"), text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(BroopType.number(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .focused($focused, equals: which)
                .frame(width: 110)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(BroopActivityPalette.input))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BroopActivityPalette.inputBorder, lineWidth: 1))
            Text(verbatim: unit).font(BroopType.demi(13)).foregroundStyle(BroopPalette.textSecondary).frame(width: 34, alignment: .leading)
        }
        .frame(minHeight: 52)
    }

    // MARK: Rules (the classic ManualWorkoutSheet's, verbatim)

    private var startBinding: Binding<Date> {
        Binding(get: { start }, set: { picked in
            let span = end.timeIntervalSince(start)
            let newStart = min(picked, Date().addingTimeInterval(-span))
            end = WorkoutSource.endAfterStartMove(oldStart: start, oldEnd: end, newStart: newStart)
            start = newStart
        })
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { min(24 * 60, max(1, WorkoutSource.spanDurationMin(start: start, end: end))) },
                set: { end = WorkoutSource.endForDuration(start: start, durationMin: $0) })
    }

    private var durationLabel: String {
        let d = durationBinding.wrappedValue
        let h = d / 60, m = d % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private var avgHr: Int? { Int(avgHrText.trimmingCharacters(in: .whitespaces)) }
    private var kcal: Double? { Double(kcalText.trimmingCharacters(in: .whitespaces)) }
    private var distanceMeters: Double? {
        let t = distanceText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let v = Double(t), v >= 0 else { return nil }
        let km = distanceSystem == .imperial ? v / UnitFormatter.milesPerKilometer : v
        return km * 1000
    }

    private var builtRow: WorkoutRow? {
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty && avgHr == nil { return nil }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty && kcal == nil { return nil }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty && distanceMeters == nil { return nil }
        guard let base = WorkoutSource.buildManualRowFromSpan(start: start, end: end, sport: sport, avgHr: avgHr,
                                                              energyKcal: kcal, distanceM: distanceMeters) else { return nil }
        return WorkoutSource.preservingCaptured(base, from: editing)
    }

    private var avgHrEditedNote: Bool {
        guard !isAdd, let editing, let built = builtRow else { return false }
        return (editing.strain != nil || editing.zonesJSON != nil) && built.avgHr != editing.avgHr
    }

    private var validationNote: String? {
        guard builtRow == nil else { return nil }
        if sport.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Enter a sport.") }
        if start > Date() { return String(localized: "Start can't be in the future.") }
        if end <= start { return String(localized: "End must be after the start.") }
        if end > Date() { return String(localized: "End can't be in the future.") }
        if Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970) < WorkoutSource.minManualSpanSeconds {
            return String(localized: "A workout must be at least 1 minute.")
        }
        if !avgHrText.trimmingCharacters(in: .whitespaces).isEmpty, avgHr == nil || !(25...250).contains(avgHr ?? -1) {
            return String(localized: "Average HR must be 25-250 bpm.")
        }
        if !kcalText.trimmingCharacters(in: .whitespaces).isEmpty, kcal == nil || (kcal ?? -1) < 0 || (kcal ?? 0) > 20_000 {
            return String(localized: "Calories must be 0-20,000.")
        }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty,
           distanceMeters == nil || (distanceMeters ?? -1) < 0 || (distanceMeters ?? 0) > 1_000_000 {
            return distanceSystem == .imperial ? String(localized: "Distance must be 0–621 mi.")
                                               : String(localized: "Distance must be 0–1,000 km.")
        }
        return String(localized: "Check the values and try again.")
    }

    private func save() {
        guard let row = builtRow else { return }
        RecentSportsPrefs.recordSelection(row.sport)
        onSave(row, isCopy ? nil : editing)
        dismiss()
    }
}
#endif
