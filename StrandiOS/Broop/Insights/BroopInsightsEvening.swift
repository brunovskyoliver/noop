#if os(iOS)
import SwiftUI
import WhoopStore

// The evening flow: the Home card's evening review (from 17:00) and journal by voice. The person says how the
// day went, the on-device model picks the journal items they mentioned, and a review list shows what would be
// saved. Nothing is written until SAVE TO JOURNAL; the writes are the Journal screen's own Repository calls.

/// Journal by voice for one journal day. From the evening review that is tomorrow's (see
/// `AppleCoachEveningPolicy.journalDay`); from the Journal screen, the day it shows.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch phase {
                    case .input, .failed:
                        inputStep
                    case .reading:
                        HStack(spacing: 12) {
                            ProgressView().tint(BroopPalette.textSecondary)
                            BroopInsightsBody(text: String(localized: "Matching what you said to your journal…"))
                        }
                        .padding(.top, 30)
                    case .review:
                        reviewStep
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomButtons }
            .safeAreaInset(edge: .top, spacing: 0) {
                BroopNavHeader(inline: true, onBack: { close() }, leadingSymbol: "xmark",
                               center: { BroopNavTitle(title: String(localized: "Log your day")) },
                               trailing: { EmptyView() })
            }
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await loadChoices() }
    }

    // MARK: Steps

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            BroopInsightsHeadline(text: String(localized: "How was your day?"))
            BroopInsightsBody(text: String(localized: "Say what you ate, drank and did, like \"two coffees, the last one after lunch, a beer with dinner, phone in bed\". Coach matches it to your journal questions on this iPhone, and you check the answers before anything is saved."))
            BroopInsightsBody(text: String(localized: "Saves to your journal for \(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.activeLocale))), the morning these habits affect."),
                              size: 13, color: BroopPalette.textSecondary)
            TextField(String(localized: "Tap the microphone or type here"), text: $transcript, axis: .vertical)
                .font(BroopType.regular(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(4...10)
                .focused($fieldFocused)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(voice.isRecording ? BroopInsightsPalette.coachPurple : Color.white.opacity(0.10), lineWidth: 1.3))
            HStack {
                Spacer()
                micButton
                Spacer()
            }
            .padding(.top, 4)
            if let status = voice.statusMessage {
                BroopInsightsBody(text: status, size: 13, color: BroopPalette.textSecondary)
            }
            if case .failed(let message) = phase {
                BroopInsightsNote(symbol: "exclamationmark.bubble", title: nil, text: message)
            }
        }
    }

    private var micButton: some View {
        Button { toggleVoice() } label: {
            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(voice.isRecording ? Color.white : Color.black)
                .frame(width: 76, height: 76)
                .background(Circle().fill(voice.isRecording ? BroopInsightsPalette.hurts : Color.white))
                .contentShape(Circle())
        }
        .buttonStyle(BroopPressableStyle())
        .disabled(!(voice.canUseVoice || voice.authorization == .notDetermined))
        .accessibilityLabel(Text(voice.isRecording ? "Stop voice input" : "Voice input"))
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopInsightsHeadline(text: proposals.isEmpty ? String(localized: "Nothing to log") : String(localized: "Check your answers"))
            if proposals.isEmpty {
                BroopInsightsBody(text: String(localized: "Coach couldn't match what you said to a journal question. Try naming the behaviour, like \"alcohol\", \"late caffeine\" or \"screen in bed\"."))
            } else {
                BroopInsightsBody(text: String(localized: "Coach filled in these answers from what you said. Change or remove any before saving."))
                VStack(spacing: 0) {
                    ForEach($proposals) { $p in
                        row($p)
                        if p.id != proposals.last?.id { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
            }
            Text(verbatim: "\u{201C}" + transcript.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{201D}")
                .font(BroopType.regular(13.5))
                .foregroundStyle(BroopPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
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

    @ViewBuilder private var bottomButtons: some View {
        VStack(spacing: 10) {
            switch phase {
            case .input, .failed:
                BroopInsightsPrimaryButton(title: String(localized: "Fill in my journal"), symbol: "sparkles") { read() }
                    .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            case .reading:
                EmptyView()
            case .review:
                if !proposals.isEmpty {
                    BroopInsightsPrimaryButton(title: String(localized: "Save to journal")) { save() }
                        .disabled(saving || !proposals.contains(where: Self.isComplete))
                }
                BroopInsightsOutlineButton(title: String(localized: "Start over")) { phase = .input }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.4))
                .ignoresSafeArea()
        )
    }

    // MARK: Actions

    private func loadChoices() async {
        let imported = await repo.importedJournalEntries()
        let importedQuestions = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        choices = catalog.resolvedItems(imported: importedQuestions, includeHidden: false).map {
            CoachJournalParse.Choice(canonical: $0.canonical, display: $0.display, unit: $0.kind.unitLabel, isNumeric: $0.kind.isNumeric)
        }
        #if DEBUG
        // Verification only: `--voice-journal-text "…"` reads that text as if dictated.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--voice-journal-text"), i + 1 < args.count {
            transcript = args[i + 1]
            read()
        }
        #endif
    }

    private func toggleVoice() {
        if voice.isRecording {
            voice.stopTranscribing { final in
                let t = final.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { transcript = t }
            }
        } else if voice.authorization == .notDetermined {
            voice.requestAuthorization { state in
                if state == .authorized { startDictation() }
            }
        } else {
            startDictation()
        }
    }

    /// Dictation continues after what is already in the field.
    private func startDictation() {
        fieldFocused = false
        let prefix = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        voice.startTranscribing { partial in
            transcript = prefix.isEmpty ? partial : prefix + " " + partial
        }
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
                                ? String(localized: "Coach couldn't read that just now. Try again, or fill in the journal by hand.")
                                : String(localized: "This needs Apple Intelligence on this iPhone, and it isn't ready for your language yet. You can still fill in the journal by hand."))
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
                            Image(systemName: "mic.fill").font(.system(size: 14, weight: .semibold))
                            BroopCaps(String(localized: "Log your day by voice"), size: 11)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                                .foregroundStyle(BroopPalette.textSecondary)
                        }
                        .foregroundStyle(BroopPalette.textPrimary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                Text(verbatim: review.factsOnly
                     ? String(localized: "Coach's wording didn't pass the number check, so this shows the values only.")
                     : String(localized: "Written by Apple Intelligence. The values come from the app."))
                    .font(BroopType.regular(11.5))
                    .foregroundStyle(BroopPalette.textTertiary)
                    .multilineTextAlignment(.leading)
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.fill").font(.system(size: 10, weight: .semibold))
                        BroopCaps(String(localized: "Tonight"), size: 9.5, color: BroopPalette.textSecondary)
                    }
                    .foregroundStyle(BroopPalette.textSecondary)
                    .frame(width: 92, alignment: .leading)
                    Text(verbatim: tonight)
                        .font(BroopType.medium(13.5))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
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
