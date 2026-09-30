#if os(iOS)
import SwiftUI
import MarkdownUI
import UIKit

// Coach, as WHOOP Coach v6: a dark indigo canvas, coach replies as plain Markdown text with an action row
// (copy / share / save to journal), user turns in right-aligned violet bubbles, white suggestion chips and a
// "+" / gradient-bordered field / mic composer. Behaviour is the classic `CoachView`'s: the same
// `AICoachEngine` calls, the same first-open task order, the pending-prompt handoff, draft persistence,
// on-device voice, key repair and provider setup. Coach settings and provider settings stay the classic
// sheets (under the Broop skin), reached from the header menu.

struct BroopInsightsCoachView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    /// Set when Coach is shown in the shell's sheet (Home, notifications); nil when pushed from More.
    @Environment(\.broopCloseHostSheet) private var closeHostSheet

    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    @State private var keyFix = ""
    @State private var showClearConfirm = false
    @State private var showProviderSettings = false
    @State private var showSettings = false
    @State private var showInfo = false
    @State private var savedNote: String?
    @FocusState private var composerFocused: Bool
    @StateObject private var voice = CoachVoiceInput()

    var body: some View {
        Group {
            if coach.usesApple {
                // Apple Intelligence: the model's state, never a failed send.
                switch coach.appleAvailability {
                case .none:
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .some(let state) where state.canChat:
                    chat
                case .some(let state):
                    BroopInsightsCoachUnavailable(state: state)
                }
            } else if coach.isConfigured {
                chat
            } else {
                BroopInsightsCoachSetup()
            }
        }
        .background(BroopInsightsCoachBackground())
        // One plain header row, as WHOOP's Coach: no system bar, so no Liquid Glass bubbles around the
        // pill and the menu, and the sheet's own "Done" is replaced by the close button in this row.
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showProviderSettings) { CoachProviderSettingsView(coach: coach) }
        .sheet(isPresented: $showSettings) {
            BroopInsightsCoachSettingsSheet().environmentObject(coach).environmentObject(repo)
        }
        .sheet(isPresented: $showInfo) { BroopInsightsCoachInfoSheet().environmentObject(coach) }
        #if DEBUG
        // Verification: open a sheet straight away (`--coach-open settings|info`).
        .task {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--coach-open"), i + 1 < args.count else { return }
            try? await Task.sleep(for: .seconds(1))
            if args[i + 1] == "settings" { showSettings = true } else if args[i + 1] == "info" { showInfo = true }
        }
        #endif
        .task(id: scenePhase) {
            // The model can finish downloading, or Apple Intelligence be switched on, while the app is open.
            if scenePhase == .active {
                await coach.refreshAppleAvailability()
                coach.prewarmApple()
            }
        }
        .confirmationDialog(String(localized: "Clear conversation?"), isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(String(localized: "Clear"), role: .destructive) { coach.clearConversation() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This deletes the saved conversation from this device. Coach history is your own notes, not medical advice.")
        }
        // Same single sequential task as the classic screen: restore, surface a stored brief, then the
        // first-open brief only if the transcript is still empty.
        .task {
            await coach.loadPersistedMessagesIfNeeded()
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
            await coach.startBriefIfNeeded()
        }
        // #1862: a question handed over by a launcher. Cleared before sending so a rebuild cannot resend.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { coach.pendingPromptDay = nil; return }
            await coach.send(prompt)
        }
        // Leaving the screen mid-dictation must release the microphone.
        .onDisappear { voice.cancel() }
        .onChange(of: draft) { _, v in UserDefaults.standard.set(v, forKey: Self.draftKey) }
        .onChange(of: coach.sending) { _, sending in
            if !sending && !coach.messages.isEmpty { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .onChange(of: coach.dataConsent) { _, _ in Task { await coach.startBriefIfNeeded() } }
    }

    // MARK: Header

    /// The model when one is set, else the provider's short name ("Custom", not "Custom (OpenAI-compatible)").
    private var pillTitle: String {
        if coach.usesApple { return String(localized: "Apple Intelligence") }
        guard coach.isConfigured else { return String(localized: "Coach") }
        if !coach.model.isEmpty { return coach.model }
        let name = coach.provider.displayName
        return name.components(separatedBy: " (").first ?? name
    }

    private var header: some View {
        HStack(spacing: 6) {
            if closeHostSheet == nil {
                headerButton("chevron.left", label: String(localized: "Back")) { dismiss() }
                    .padding(.leading, -8)
            }
            versionPill
            Spacer(minLength: 8)
            menu
            if let closeHostSheet {
                headerButton("xmark", label: String(localized: "Close")) { closeHostSheet() }
                    .padding(.trailing, -8)
            }
        }
        .padding(.horizontal, BroopMetrics.page)
        .frame(height: BroopMetrics.navHeight)
        .background(BroopInsightsCoachBackground.topColor.ignoresSafeArea(edges: .top))
    }

    /// A header glyph centred in a 44 pt hit area: the same box for back, menu and close, so they line up.
    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerGlyph(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: label))
    }

    private func headerGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(BroopPalette.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var versionPill: some View {
        HStack(spacing: 8) {
            BroopBadge(size: 26, gradientRing: true)
            Text(verbatim: pillTitle)
                .font(BroopType.demi(14))
                .foregroundStyle(BroopPalette.textBody)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color.white.opacity(0.09)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: coach.usesApple ? pillTitle : "\(coach.provider.displayName), \(coach.model)"))
    }

    private var menu: some View {
        Menu {
            Button { showSettings = true } label: { Label(String(localized: "Coach settings"), systemImage: "slider.horizontal.3") }
            Button { showInfo = true } label: { Label(String(localized: "About Coach"), systemImage: "info.circle") }
            if !coach.usesApple && coach.isConfigured {
                Button { showProviderSettings = true } label: { Label(String(localized: "Provider settings"), systemImage: "gearshape") }
                    .disabled(coach.sending)
            }
            Button { showClearConfirm = true } label: { Label(String(localized: "Clear conversation"), systemImage: "trash") }
                .disabled(coach.messages.isEmpty)
            if !coach.usesApple && coach.isConfigured {
                Button(role: .destructive) { coach.disconnect() } label: {
                    Label(String(localized: "Disconnect"), systemImage: "xmark.circle")
                }
            }
        } label: {
            headerGlyph("ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Coach menu"))
    }

    // MARK: Chat

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if coach.messages.isEmpty { welcome }
                    ForEach(coach.messages) { message in
                        messageView(message).id(message.id)
                    }
                    if coach.sending {
                        if coach.usesApple {
                            // The streamed reply lives in its own observed leaf: a token re-renders the
                            // bubble, not this transcript.
                            BroopInsightsCoachStreamingReply(stream: coach.stream).id("typing")
                        } else {
                            thinking.id("typing")
                        }
                    }
                    if let error = coach.errorText, !error.isEmpty {
                        errorRow(error)
                        if coach.keyRejected { keyRepair }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: coach.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: coach.sending) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            BroopBadge(size: 44, gradientRing: true)
            Text("How can Broop help?")
                .font(BroopType.demi(27))
                .foregroundStyle(BroopPalette.textPrimary)
            // Only a cloud provider sends data off the phone, so only then is there something to say.
            if let privacyText {
                Text(verbatim: privacyText)
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(BroopPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 30)
    }

    private var privacyText: String? {
        if coach.usesApple { return nil }
        return coach.provider == .custom
            ? String(localized: "Sent only to the server you set.")
            : String(localized: "Sent to \(coach.provider.displayName) with your key.")
    }

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .font(BroopType.regular(16.5))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BroopInsightsPalette.userBubble))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("You said: \(message.text)"))
        case .assistant where message.isNotice:
            Text(verbatim: message.text)
                .font(BroopType.regular(12.5))
                .foregroundStyle(BroopPalette.textTertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        case .assistant:
            VStack(alignment: .leading, spacing: 14) {
                Markdown(message.text)
                    .markdownTheme(.broopInsightsCoach)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if message.isFromAppleServers { BroopInsightsAppleServersLabel() }
                HStack(spacing: 22) {
                    Button { UIPasteboard.general.string = message.text } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .accessibilityLabel(Text("Copy"))
                    ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Share"))
                    Button { saveAdvice(message) } label: {
                        Image(systemName: savedNote == message.id.uuidString ? "checkmark" : "square.and.pencil")
                    }
                    .accessibilityLabel(Text("Save to Journal"))
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(BroopPalette.textSecondary)
                .buttonStyle(.plain)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var thinking: some View {
        HStack(spacing: 10) {
            ProgressView().tint(BroopPalette.textSecondary)
            Text("Coach is thinking…").font(BroopType.regular(15)).foregroundStyle(BroopPalette.textSecondary)
        }
        .accessibilityLabel(Text("Coach is thinking"))
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(BroopInsightsPalette.hurts))
            Text(verbatim: message)
                .font(BroopType.medium(15))
                .foregroundStyle(BroopInsightsPalette.hurts)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Error: \(message)"))
    }

    private var keyRepair: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste the corrected key. Your conversation is kept.")
                .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
            SecureField(String(localized: "Paste your \(coach.provider.displayName) API key"), text: $keyFix)
                .broopInsightsField()
                .onSubmit(saveRepairedKey)
            BroopInsightsOutlineButton(title: String(localized: "Update key"), symbol: "key.fill",
                                       color: BroopInsightsPalette.answerBlue) { saveRepairedKey() }
                .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func saveRepairedKey() {
        let t = keyFix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        coach.setKey(t)
        keyFix = ""
    }

    // MARK: Composer

    /// After a reply: the follow-ups (written by Apple Intelligence when it can, else the fixed set; hidden
    /// while being written, keeping their space). Otherwise today's opening suggestions.
    private var chips: (prompts: [String], pending: Bool) {
        if let last = coach.messages.last, !coach.sending, last.role == .assistant {
            let f = coach.followUps(after: last)
            return (f.chips, f.pending)
        }
        return (coach.suggestions, false)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(chips.prompts, id: \.self) { prompt in
                        Button { send(prompt) } label: {
                            Text(prompt)
                                .font(BroopType.medium(15))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(Capsule().fill(Color.white))
                        }
                        .buttonStyle(BroopPressableStyle())
                        .disabled(coach.sending || chips.pending)
                        .accessibilityLabel(Text("Suggested prompt: \(prompt)"))
                    }
                }
                .padding(.horizontal, 20)
                .opacity(chips.pending ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: chips.prompts)
            }
            .accessibilityHidden(chips.pending)
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button { showClearConfirm = true } label: { Label(String(localized: "New conversation"), systemImage: "square.and.pencil") }
                        .disabled(coach.messages.isEmpty)
                    Button { showSettings = true } label: { Label(String(localized: "Coach settings"), systemImage: "slider.horizontal.3") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: Self.composerHeight, height: Self.composerHeight)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .accessibilityLabel(Text("More"))
                field
            }
            .padding(.horizontal, 16)
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let tokens = coach.estimatedTokens(forDraft: draft) {
                Text(tokens > 8000 ? "~\(tokens) tokens · may exceed small context windows" : "~\(tokens) tokens")
                    .font(BroopType.number(11)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom.opacity(0.95), BroopPalette.bgBottom],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                .ignoresSafeArea()
        )
    }

    /// One row height for the "+" button, a single-line field, the mic and send, so every control is
    /// centred on the first line and stays on the last line as the field grows.
    private static let composerHeight: CGFloat = 52

    private var field: some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 2) {
            TextField(voice.isRecording ? String(localized: "Listening…")
                                        : String(localized: "Ask Broop anything"), text: $draft, axis: .vertical)
                .font(BroopType.regular(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit { send(draft) }
                .padding(.vertical, 14)
                .frame(minHeight: Self.composerHeight)
                .accessibilityLabel(Text("Question"))
            micButton
            if hasText || coach.sending || voice.isRecording {
                Button { send(draft) } label: {
                    Group {
                        if coach.sending { ProgressView().tint(.black) } else {
                            Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white))
                    .frame(width: 42, height: Self.composerHeight)
                }
                .disabled(coach.sending || !(hasText || voice.isRecording))
                .accessibilityLabel(Text("Send"))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(broopHex: 0x10151C)))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [BroopInsightsPalette.coachPurple.opacity(0.9), BroopInsightsPalette.coachCyan.opacity(0.45)],
                                             startPoint: .leading, endPoint: .trailing), lineWidth: 1.3)
        )
    }

    private var micEnabled: Bool { !coach.sending && (voice.canUseVoice || voice.authorization == .notDetermined) }

    private var micButton: some View {
        Button { toggleVoice() } label: {
            Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(voice.isRecording ? BroopInsightsPalette.hurts
                                 : (voice.canUseVoice ? BroopPalette.textPrimary : BroopPalette.textTertiary))
                .frame(width: 42, height: Self.composerHeight)
                .contentShape(Rectangle())
        }
        .disabled(!micEnabled)
        .accessibilityLabel(Text(voice.isRecording ? "Stop voice input" : "Voice input"))
        .accessibilityHint(Text(voice.statusMessage ?? String(localized: "Transcribes your question on-device")))
        .task {
            #if DEBUG
            // Seeded verification runs: no permission alert over the screenshots.
            if CommandLine.arguments.contains("--demo-seed") { return }
            #endif
            if voice.authorization == .notDetermined { voice.requestAuthorization { _ in } }
        }
    }

    private func toggleVoice() {
        if voice.isRecording {
            voice.stopTranscribing { appendDictation($0) }
        } else if voice.authorization == .notDetermined {
            voice.requestAuthorization { state in
                if state == .authorized { startDictation() }
            }
        } else {
            startDictation()
        }
    }

    /// Dictation fills the field once, when it stops: nothing is drawn while the person talks.
    private func startDictation() {
        voice.startTranscribing(partial: { _ in }, ended: { appendDictation($0) })
    }

    /// What was said, after whatever is already in the field.
    private func appendDictation(_ spoken: String) {
        let said = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = typed.isEmpty ? said : typed + " " + said
    }

    // MARK: Actions

    private func send(_ text: String) {
        // Sending while dictating: stop, add what was said, then send the whole field.
        if voice.isRecording {
            voice.stopTranscribing { spoken in
                appendDictation(spoken)
                send(draft)
            }
            return
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        Task { await coach.send(t) }
    }

    /// K8: the reply saved as a journal note under "Coach advice", as the classic screen does.
    private func saveAdvice(_ message: ChatMessage) {
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(day: day, question: "Coach advice", answeredYes: true, notes: message.text)
            savedNote = message.id.uuidString
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let go = { proxy.scrollTo(coach.sending ? "typing" : "bottom", anchor: .bottom) }
        if animated { withAnimation(.easeOut(duration: 0.25)) { go() } } else { go() }
    }
}

/// Coach canvas: an indigo glow at the top fading to near-black.
struct BroopInsightsCoachBackground: View {
    /// The gradient's top colour, which the pinned header fills with.
    static let topColor = Color(broopHex: 0x241E42)

    var body: some View {
        ZStack {
            BroopPalette.bgBottom
            LinearGradient(stops: [
                .init(color: Self.topColor, location: 0),
                .init(color: Color(broopHex: 0x121628), location: 0.38),
                .init(color: BroopPalette.bgBottom, location: 0.7),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(broopHex: 0x1C4A5A).opacity(0.35), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Setup

/// Connect a provider: provider, server URL + key header (custom), model with refresh / custom id, API key.
/// Same engine calls as the classic setup card.
struct BroopInsightsCoachSetup: View {
    @EnvironmentObject private var coach: AICoachEngine
    @State private var keyDraft = ""
    @State private var customModel = false
    @State private var customModelDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    BroopBadge(size: 44, gradientRing: true)
                    Text("Connect a provider").font(BroopType.demi(27)).foregroundStyle(BroopPalette.textPrimary)
                    BroopInsightsBody(text: String(localized: "Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the Keychain and never leaves \(Platform.deviceNounPhrase) except as the request you make."),
                                      size: 15)
                }
                field(String(localized: "Provider")) {
                    Menu {
                        ForEach(AIProvider.allCases) { p in Button(p.displayName) { coach.provider = p } }
                    } label: { menuLabel(coach.provider.displayName) }
                }
                if coach.provider == .custom {
                    field(String(localized: "Server URL")) {
                        TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).broopInsightsField()
                        note(String(localized: "Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. HTTP and HTTPS URLs are supported. Requests go to the server you choose."))
                    }
                    field(String(localized: "Key header")) {
                        BroopUnderlineTabs(options: CustomAIAuthHeader.allCases, selection: $coach.customAuthHeader) { $0.displayName }
                        note(String(localized: "Use Bearer for most local servers; use x-api-key for gateways that require the key in that header."))
                    }
                }
                field(String(localized: "Model")) {
                    HStack {
                        Menu {
                            ForEach(coach.availableModels, id: \.self) { m in
                                Button(m) { customModel = false; coach.model = m }
                            }
                            Divider()
                            Button(String(localized: "Custom…")) {
                                customModel = true
                                if customModelDraft.isEmpty { customModelDraft = coach.model }
                            }
                        } label: { menuLabel(customModel ? String(localized: "Custom…") : coach.model) }
                        Button { Task { await coach.refreshModels() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BroopPalette.textPrimary)
                                .frame(width: 46, height: 46)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                        }
                        .disabled(!coach.hasKey && coach.provider != .custom)
                        .accessibilityLabel(Text("Refresh models from provider"))
                    }
                    if customModel {
                        HStack {
                            TextField(String(localized: "Enter a model id"), text: $customModelDraft)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .broopInsightsField()
                                .onSubmit(applyCustomModel)
                            Button(String(localized: "Use"), action: applyCustomModel)
                                .font(BroopType.demi(15)).foregroundStyle(BroopPalette.textPrimary)
                                .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                field(coach.provider == .custom ? String(localized: "API key (optional)") : String(localized: "API key")) {
                    SecureField(coach.provider == .custom ? String(localized: "Only if your server requires one")
                                                         : String(localized: "Paste your \(coach.provider.displayName) API key"),
                                text: $keyDraft)
                        .broopInsightsField()
                        .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                }
                if coach.provider == .custom {
                    BroopInsightsPrimaryButton(title: String(localized: "Connect"), symbol: "link", action: connectCustom)
                        .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    BroopInsightsPrimaryButton(title: String(localized: "Save key"), symbol: "key.fill", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = coach.errorText, !error.isEmpty {
                    Text(verbatim: error).font(BroopType.medium(14)).foregroundStyle(BroopInsightsPalette.hurts)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: 12))
                    Text(verbatim: coach.provider == .custom
                         ? String(localized: "Coach talks only to the server URL you set. Point it at a local model (Ollama, LM Studio, llama.cpp) to keep everything on your own machine. Nothing is sent until you ask.")
                         : String(localized: "This is the only feature that leaves \(Platform.deviceNounPhrase). It sends a summary of your metrics to \(coach.provider.displayName) using your own key. Nothing is sent until you ask."))
                        .font(BroopType.regular(12.5)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(BroopPalette.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(label, size: 10.5, color: BroopPalette.textSecondary)
            content()
        }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack {
            Text(verbatim: text).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
        }
        .broopInsightsField()
    }

    private func note(_ text: String) -> some View {
        BroopInsightsBody(text: text, size: 12, color: BroopPalette.textTertiary)
    }

    private func applyCustomModel() {
        let t = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        coach.setCustomModel(t)
        customModel = false
    }

    private func saveKey() {
        let t = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        coach.setKey(t)
        keyDraft = ""
    }

    private func connectCustom() {
        let t = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { coach.setKey(t); keyDraft = "" }
        coach.connectCustom()
    }
}

extension Theme {
    /// Coach replies at WHOOP Coach's reading size: Avenir body, generous line height, white bold spans.
    static let broopInsightsCoach = Theme()
        .text {
            FontFamily(.custom("AvenirNext-Regular"))
            ForegroundColor(Color(broopHex: 0xE6E7EA))
            FontSize(17)
        }
        .strong {
            FontFamily(.custom("AvenirNext-DemiBold"))
            ForegroundColor(Color.white)
        }
        .emphasis { FontStyle(.italic) }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Color.white.opacity(0.08))
        }
        .link { ForegroundColor(BroopInsightsPalette.coachCyan) }
        .heading1 { c in
            c.label.markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle { FontFamily(.custom("AvenirNext-DemiBold")); FontSize(19); ForegroundColor(Color.white) }
        }
        .heading2 { c in
            c.label.markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle { FontFamily(.custom("AvenirNext-DemiBold")); FontSize(18); ForegroundColor(Color.white) }
        }
        .heading3 { c in
            c.label.markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle { FontFamily(.custom("AvenirNext-DemiBold")); FontSize(17); ForegroundColor(Color.white) }
        }
        .heading4 { c in
            c.label.markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle { FontFamily(.custom("AvenirNext-DemiBold")); FontSize(16); ForegroundColor(Color.white) }
        }
        .paragraph { c in
            c.label.relativeLineSpacing(.em(0.42)).markdownMargin(top: 0, bottom: 16)
        }
        .listItem { c in c.label.markdownMargin(top: .em(0.35)) }
        .blockquote { c in
            c.label.padding(.leading, 12)
                .markdownTextStyle { ForegroundColor(BroopPalette.textSecondary) }
                .overlay(alignment: .leading) { Rectangle().fill(BroopInsightsPalette.coachPurple).frame(width: 2) }
                .markdownMargin(top: 4, bottom: 10)
        }
        .codeBlock { c in
            ScrollView(.horizontal, showsIndicators: false) {
                c.label.markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.85)) }.padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .markdownMargin(top: 4, bottom: 10)
        }
        .thematicBreak {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).markdownMargin(top: 12, bottom: 12)
        }
        .table { c in
            c.label.fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color.white.opacity(0.12)))
                .markdownMargin(top: 4, bottom: 10)
        }
        .tableCell { c in
            c.label
                .markdownTextStyle {
                    if c.row == 0 { FontFamily(.custom("AvenirNext-DemiBold")) }
                    FontSize(.em(0.88))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 5).padding(.horizontal, 8)
        }
}
#endif
