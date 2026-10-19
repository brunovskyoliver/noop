#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// The evening flow: the Home card's evening review (from 17:00) and journal by voice. The person says how the
// day went, the on-device model picks the journal items they mentioned, and a review list shows what would be
// saved. Nothing is written until SAVE TO JOURNAL; the writes are the Journal screen's own Repository calls.

/// Journal by voice for one journal day: tomorrow's from the evening review (see
/// `AppleCoachEveningPolicy.journalDay`), the day on screen from the Journal. Voice only: listening starts as
/// the sheet opens, a circle follows the voice, one button finishes. A text field appears only when voice
/// can't be used on this iPhone.
struct BroopInsightsVoiceJournalSheet: View {
    var day: Date = AppleCoachEveningPolicy.journalDay(for: Date())
    var onSaved: () -> Void = {}

    private var dayKey: String { Repository.localDayKey(day) }

    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = JournalCatalogStore()
    @StateObject private var voice = CoachVoiceInput()

    private enum Phase: Equatable {
        case input
        case reading
        case review
        case failed(String)
    }

    @State private var phase: Phase = .input
    @State private var transcript = ""
    @State private var proposals: [CoachJournalProposal] = []
    @State private var choices: [CoachJournalParse.Choice] = []
    @State private var saving = false
    @FocusState private var fieldFocused: Bool

    /// Voice can be used, or can be once the person grants permission.
    private var voiceAvailable: Bool { voice.canUseVoice || voice.authorization == .notDetermined }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .review {
                    reviewStep
                } else if voiceAvailable {
                    voiceStage
                } else {
                    typingStage
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                BroopNavHeader(inline: true, onBack: { close() }, leadingSymbol: "xmark",
                               center: { BroopNavTitle(title: day.formatted(.dateTime.weekday(.wide).day().month(.wide)
                                   .locale(AppLanguage.activeLocale))) },
                               trailing: { EmptyView() })
            }
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await loadChoices() }
        // Swiping the sheet away skips `close()`; the microphone must not outlive the sheet.
        .onDisappear { voice.cancel() }
    }

    private var failure: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    // MARK: Steps

    /// The circle, and one button: talk, finish, or wait while Coach reads it.
    private var voiceStage: some View {
        VStack(spacing: 0) {
            Spacer()
            BroopVoiceOrbLive(meter: voice.meter, mode: phase == .reading ? .thinking : (voice.isRecording ? .listening : .idle))
                .frame(width: 190, height: 190)
            Text(verbatim: failure ?? " ")
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Spacer()
            Button { orbTapped() } label: {
                Group {
                    if phase == .reading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 72, height: 72)
                .background(Circle().fill(BroopPalette.textPrimary))
                .contentShape(Circle())
            }
            .buttonStyle(BroopPressableStyle())
            .disabled(phase == .reading)
            .sensoryFeedback(.start, trigger: voice.isRecording)
            .accessibilityLabel(Text(voice.isRecording ? "Done" : "Talk"))
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BroopMetrics.page)
    }

    /// Voice can't be used on this iPhone: type instead.
    private var typingStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(String(localized: "How was your day?"), text: $transcript, axis: .vertical)
                    .font(BroopType.regular(17))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .lineLimit(4...10)
                    .focused($fieldFocused)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
                if let failure {
                    Text(verbatim: failure).font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if phase == .reading {
                    ProgressView().tint(BroopPalette.textSecondary).frame(height: 48)
                } else {
                    BroopInsightsPrimaryButton(title: String(localized: "Continue")) { read() }
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var reviewStep: some View {
        ScrollView {
            if proposals.isEmpty {
                Text("Nothing matched.")
                    .font(BroopType.regular(15))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                VStack(spacing: 0) {
                    ForEach($proposals) { $p in
                        row($p)
                        if p.id != proposals.last?.id { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) {
                if !proposals.isEmpty {
                    BroopInsightsPrimaryButton(title: String(localized: "Save")) { save() }
                        .disabled(saving || !proposals.contains(where: Self.isComplete))
                }
                Button { startOver() } label: {
                    Text("Redo").font(BroopType.medium(15)).foregroundStyle(BroopPalette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func row(_ p: Binding<CoachJournalProposal>) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: p.wrappedValue.display)
                .font(BroopType.medium(16))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if p.wrappedValue.isNumeric {
                amountControl(p)
            } else {
                answerSquare(p, yes: false)
                answerSquare(p, yes: true)
            }
            Button {
                proposals.removeAll { $0.id == p.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BroopPalette.textTertiary)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(p.wrappedValue.display)"))
        }
        .padding(.vertical, 13)
    }

    private func answerSquare(_ p: Binding<CoachJournalProposal>, yes: Bool) -> some View {
        let selected = p.wrappedValue.answeredYes == yes
        return Button { p.wrappedValue.answeredYes = yes } label: {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : BroopPalette.textPrimary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? (yes ? BroopInsightsPalette.answerBlue : Color.white) : BroopInsightsPalette.answerIdle))
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(yes ? "Yes" : "No"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func amountControl(_ p: Binding<CoachJournalProposal>) -> some View {
        let amount = p.wrappedValue.amount
        let unit = p.wrappedValue.unit ?? ""
        return HStack(spacing: 4) {
            stepButton("minus") { p.wrappedValue.amount = max(0, (amount ?? 0) - 1) }
            Text(verbatim: amount.map { BroopInsightsJournalView.format($0) + (unit.isEmpty ? "" : " \(unit)") } ?? "?")
                .font(BroopType.demi(15))
                .foregroundStyle(amount == nil ? BroopPalette.textPrimary : Color.black.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 50, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(amount == nil ? BroopInsightsPalette.answerIdle : BroopInsightsPalette.answerBlue))
            stepButton("plus") { p.wrappedValue.amount = (amount ?? 0) + 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(p.wrappedValue.display), \(amount.map(BroopInsightsJournalView.format) ?? "no amount")"))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 26, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(symbol == "plus" ? "Increase" : "Decrease"))
    }

    // MARK: Actions

    private func loadChoices() async {
        let imported = await repo.importedJournalEntries()
        let importedQuestions = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        choices = catalog.resolvedItems(imported: importedQuestions, includeHidden: false).map {
            CoachJournalParse.Choice(canonical: $0.canonical, display: $0.display, unit: $0.kind.unitLabel, isNumeric: $0.kind.isNumeric)
        }
        #if DEBUG
        // Verification only: `--voice-journal-text "…"` reads that text as if dictated; seeded runs don't
        // open the microphone.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--voice-journal-text"), i + 1 < args.count {
            transcript = args[i + 1]
            read()
            return
        }
        if args.contains("--demo-seed") { return }
        #endif
        // Voice mode: listening starts as the sheet opens.
        if voiceAvailable, phase == .input { startListening() }
    }

    private func orbTapped() {
        if voice.isRecording { finishListening() } else { startListening() }
    }

    /// Start listening, asking for permission the first time. The transcript is kept, never shown.
    private func startListening() {
        if case .failed = phase { phase = .input }
        if voice.authorization == .notDetermined {
            voice.requestAuthorization { state in
                if state == .authorized { startListening() }
            }
            return
        }
        transcript = ""
        voice.meter.isEnabled = true
        // A session the system ends (a call, Siri, an error) is read like one the person stopped.
        voice.startTranscribing(partial: { _ in }, ended: { heard($0) })
    }

    /// Stop listening and fill in the journal from everything said.
    private func finishListening() {
        // The recognizer finishes the last words before the text arrives; show that as reading.
        phase = .reading
        voice.stopTranscribing { heard($0) }
    }

    private func heard(_ final: String) {
        let said = final.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = said.isEmpty ? transcript : said
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .failed(String(localized: "Didn't catch that."))
        } else {
            read()
        }
    }

    private func startOver() {
        transcript = ""
        proposals = []
        phase = .input
        if voiceAvailable { startListening() }
    }

    private func read() {
        if voice.isRecording { voice.stopTranscribing { _ in } }
        fieldFocused = false
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        phase = .reading
        Task {
            if let result = await coach.journalProposals(transcript: text, choices: choices) {
                proposals = result
                phase = .review
                #if DEBUG
                print("VOICE_JOURNAL " + result.map { "\($0.display)=\($0.answeredYes.map { $0 ? "yes" : "no" } ?? $0.amount.map { "\($0)" } ?? "?")" }.joined(separator: "; "))
                #endif
            } else {
                #if DEBUG
                print("VOICE_JOURNAL_FAILED")
                #endif
                phase = .failed(coach.canUseJournalByVoice
                                ? String(localized: "Couldn't read that. Try again.")
                                : String(localized: "Apple Intelligence isn't ready."))
            }
        }
    }

    private static func isComplete(_ p: CoachJournalProposal) -> Bool {
        p.isNumeric ? p.amount != nil : p.answeredYes != nil
    }

    private func save() {
        saving = true
        let rows = proposals.filter(Self.isComplete)
        Task {
            for p in rows {
                if p.isNumeric, let amount = p.amount {
                    await repo.saveJournalNumeric(day: dayKey, question: p.canonical, value: amount)
                } else if let yes = p.answeredYes {
                    await repo.saveJournalAnswer(day: dayKey, question: p.canonical, answeredYes: yes)
                }
            }
            saving = false
            onSaved()
            dismiss()
        }
    }

    private func close() {
        if voice.isRecording { voice.stopTranscribing { _ in } }
        dismiss()
    }
}

/// The circle fed by the live meter: only this view observes the loudness, so the sheet around it does not
/// re-render with every reading.
struct BroopVoiceOrbLive: View {
    @ObservedObject var meter: CoachVoiceMeter
    let mode: BroopVoiceOrb.Mode

    var body: some View { BroopVoiceOrb(level: meter.level, mode: mode) }
}

/// The voice-mode circle: a plain white disc, still when idle, swelling with the voice while listening, and
/// breathing slowly while Coach reads what was said.
struct BroopVoiceOrb: View {
    enum Mode: Equatable { case idle, listening, thinking }
    let level: Double
    let mode: Mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    private var poseStill: Bool { motion.poseStill(reduceMotion) }

    var body: some View {
        if mode == .thinking && !poseStill {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                orb(at: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            orb(at: 0)
        }
    }

    private func orb(at time: TimeInterval) -> some View {
        let scale: Double = switch mode {
        case .idle: 0.86
        case .listening: poseStill ? 0.88 : 0.88 + level * 0.14
        case .thinking: 0.84 + 0.04 * sin(time * 2.4)
        }
        return Circle()
            .fill(BroopPalette.textPrimary)
            .opacity(mode == .idle ? 0.9 : 1)
            .scaleEffect(scale)
            .animation(poseStill ? nil : .easeOut(duration: 0.15), value: level)
    }
}

/// The evening review on Home (see `AppleCoachEveningPolicy`): how today went for two or three metrics, with
/// the app's values beside the model's sentences, one thing to do tonight, and journal by voice.
struct BroopInsightsCoachEveningCard: View {
    let review: AppleCoachBrief
    let onOpenCoach: () -> Void
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @State private var values: [String: String] = [:]
    @State private var showVoiceJournal = false

    var body: some View {
        BroopCard {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onOpenCoach) { summary }
                    .buttonStyle(BroopPressableStyle())
                if coach.canUseJournalByVoice {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    Button { showVoiceJournal = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mic").font(.system(size: 14, weight: .regular))
                            BroopCaps(String(localized: "Log your day"), size: 11)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                                .foregroundStyle(BroopPalette.textSecondary)
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BroopPressableStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(review.day)|\(review.dataKey)|\(repo.refreshSeq)") { values = await load() }
        .sheet(isPresented: $showVoiceJournal) {
            BroopInsightsVoiceJournalSheet { Task { await coach.refreshAppleEveningIfNeeded() } }
                .environmentObject(coach)
                .environmentObject(repo)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                BroopBadge(size: 22, gradientRing: true)
                BroopCaps(String(localized: "Evening review"), size: 11)
                Spacer()
                if review.offDevice { BroopInsightsAppleServersLabel() }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            Text(verbatim: review.headline)
                .font(BroopType.demi(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(review.points, id: \.metric) { point in
                if let metric = CoachMetric(rawValue: point.metric) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            BroopCaps(metric.label, size: 9.5, color: BroopPalette.textSecondary)
                            Text(verbatim: values[point.metric] ?? "--")
                                .font(BroopType.number(19))
                                .foregroundStyle(BroopPalette.textPrimary)
                        }
                        .frame(width: 92, alignment: .leading)
                        if !point.sentence.isEmpty {
                            Text(verbatim: point.sentence)
                                .font(BroopType.regular(13.5))
                                .foregroundStyle(BroopPalette.textBody)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            if let tonight = review.tonight, !tonight.isEmpty {
                Text(verbatim: tonight)
                    .font(BroopType.medium(13.5))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func load() async -> [String: String] {
        guard let source = coach.apple.source else { return [:] }
        var out: [String: String] = [:]
        for p in review.points {
            if let m = CoachMetric(rawValue: p.metric), let v = await source.briefValue(m) { out[p.metric] = v }
        }
        return out
    }
}
#endif
