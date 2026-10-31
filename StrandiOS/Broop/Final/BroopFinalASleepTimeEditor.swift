#if os(iOS)
import SwiftUI
import StrandAnalytics

/// The sleep-time editor in Broop form: correct a night's (or nap's) start and end, add a nap, or delete the
/// session. Two big time tiles (ASLEEP / WOKE) with a wheel under the one being edited, the time in bed
/// between them, a white SAVE capsule and a quiet red delete.
///
/// Behaviour is the `SleepTimeEditor`'s, through the same pure `SleepEditGuard` rules:
/// - the start is bounded to the past, and a start seeded in the future is clamped to now (#940);
/// - a time-only roll of the start that lands in the future, or at/after the night's wake, snaps back a day
///   (`autoCorrectedBed`, guard 1);
/// - Save runs `clampedEditWindow` (future cap, inverted, longer than a day) and stays disabled when it
///   refuses the window;
/// - a corrected window that no longer touches the recorded coverage asks "Move this sleep?" first
///   (`isDisjoint`, guard 2), and both paths commit through one funnel;
/// - delete is confirmation-gated, and its copy only promises re-detection suppression for a detected night.
struct BroopFinalASleepTimeEditor: View {
    let onSave: (Int, Int) async -> Void
    let onDelete: (() async -> Void)?
    private let title: String
    private let blurb: String
    private let bedLabel: String
    private let wakeLabel: String
    private let deleteLabel: String
    private let coverage: ClosedRange<Int>?
    private let suppressesReDetection: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var bed: Date
    @State private var wake: Date
    @State private var previousBed: Date
    @State private var editing: Endpoint = .bed
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var confirmingDisjoint = false

    private enum Endpoint { case bed, wake }

    init(bedTs: Int, wakeTs: Int,
         title: String = String(localized: "Edit sleep times"),
         blurb: String = String(localized: "Correct when you went to bed and woke. Stages are re-derived from your data; the edit is kept through the next strap sync."),
         bedLabel: String = String(localized: "Asleep"),
         wakeLabel: String = String(localized: "Woke"),
         deleteLabel: String = String(localized: "Delete this sleep"),
         coverage: ClosedRange<Int>? = nil,
         suppressesReDetection: Bool = true,
         onSave: @escaping (Int, Int) async -> Void,
         onDelete: (() async -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.title = title
        self.blurb = blurb
        self.bedLabel = bedLabel
        self.wakeLabel = wakeLabel
        self.deleteLabel = deleteLabel
        self.coverage = coverage
        self.suppressesReDetection = suppressesReDetection
        // Never seed the start in the future (#940): the Add Nap anchor can sit ahead of the clock.
        let seedBed = Date(timeIntervalSince1970: TimeInterval(min(bedTs, Int(Date().timeIntervalSince1970))))
        _bed = State(initialValue: seedBed)
        _previousBed = State(initialValue: seedBed)
        _wake = State(initialValue: Date(timeIntervalSince1970: TimeInterval(wakeTs)))
    }

    /// The window after the persistence guards; nil when Save must stay off.
    private var validatedWindow: (start: Int, end: Int)? {
        SleepEditGuard.clampedEditWindow(start: Int(bed.timeIntervalSince1970),
                                         end: Int(wake.timeIntervalSince1970),
                                         now: Int(Date().timeIntervalSince1970))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: blurb)
                        .font(BroopType.regular(14))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        tile(.bed, label: bedLabel, date: bed)
                        tile(.wake, label: wakeLabel, date: wake)
                    }

                    durationLine

                    DatePicker("", selection: editing == .bed ? $bed : $wake, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipped()
                        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                        .accessibilityLabel(Text(verbatim: editing == .bed ? bedLabel : wakeLabel))

                    BroopFinalAPill(title: saving ? String(localized: "Saving…") : String(localized: "Save"),
                                    busy: saving, enabled: validatedWindow != nil) { requestSave() }
                        .padding(.top, 4)

                    if onDelete != nil {
                        Button { confirmingDelete = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                                BroopCaps(deleteLabel, size: 11.5, color: BroopFinalAPalette.danger)
                            }
                            .foregroundStyle(BroopFinalAPalette.danger)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BroopPressableStyle())
                        .disabled(saving)
                        .accessibilityLabel(Text(verbatim: deleteLabel))
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(BroopBackground())
            .broopFinalASheetBar(title, onClose: { dismiss() })
        }
        .preferredColorScheme(.dark)
        // Guard 1: a time-only roll into the future or past the wake means the previous evening.
        .onChange(of: bed) { _, newBed in
            let corrected = SleepEditGuard.autoCorrectedBed(
                previousBed: previousBed, candidateBed: newBed,
                originalWake: coverage.map { Date(timeIntervalSince1970: TimeInterval($0.upperBound)) },
                now: Date())
            previousBed = corrected
            if corrected != newBed { bed = corrected }
        }
        .alert("Move this sleep?", isPresented: $confirmingDisjoint) {
            Button("Cancel", role: .cancel) { }
            Button("Move anyway") {
                guard let window = validatedWindow else { return }
                commit(start: window.start, end: window.end)
            }
        } message: {
            Text("This moves the night to a time with no recorded data. Stages can't be derived there, so it may show as empty until data covers it.")
        }
        .alert("Delete this sleep session?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                saving = true
                Task {
                    await onDelete?()
                    dismiss()
                }
            }
        } message: {
            Text(suppressesReDetection
                 ? "Removes this recorded sleep and recomputes the day without it. NOOP won't re-detect sleep in this window. You can undo for a few seconds after."
                 : "Removes this sleep and recomputes the day without it. You can undo for a few seconds after.")
        }
    }

    // MARK: Pieces

    private func tile(_ endpoint: Endpoint, label: String, date: Date) -> some View {
        let on = editing == endpoint
        return Button {
            withAnimation(.snappy) { editing = endpoint }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                BroopCaps(label, size: 10.5, color: on ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                Text(verbatim: AppClock.hourMinute(date))
                    .font(BroopType.number(34))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                BroopCaps(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.activeLocale)),
                          size: 10, color: BroopPalette.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
            .overlay(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous)
                .strokeBorder(on ? Color.white.opacity(0.85) : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(verbatim: "\(label), \(date.formatted(date: .abbreviated, time: .shortened))"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var durationLine: some View {
        HStack(spacing: 10) {
            BroopCaps(String(localized: "Time in bed"), size: 10.5, color: BroopPalette.textSecondary)
            Rectangle().fill(BroopPalette.hairline).frame(height: 1)
            if let w = validatedWindow {
                Text(verbatim: BroopFormat.duration(Double(w.end - w.start) / 60))
                    .font(BroopType.number(18))
                    .foregroundStyle(BroopPalette.textPrimary)
            } else {
                Text(verbatim: "–").font(BroopType.number(18)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
        if validatedWindow == nil {
            Text("The end has to come after the start, and one sleep can't run longer than a day.")
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Save

    private func requestSave() {
        guard let window = validatedWindow else { return }
        if let coverage, SleepEditGuard.isDisjoint(newStart: window.start, newEnd: window.end,
                                                   coverageStart: coverage.lowerBound,
                                                   coverageEnd: coverage.upperBound) {
            confirmingDisjoint = true
        } else {
            commit(start: window.start, end: window.end)
        }
    }

    /// The single save funnel: Save and the "Move anyway" consent both land here.
    private func commit(start: Int, end: Int) {
        saving = true
        Task {
            await onSave(start, end)
            dismiss()
        }
    }
}
#endif
