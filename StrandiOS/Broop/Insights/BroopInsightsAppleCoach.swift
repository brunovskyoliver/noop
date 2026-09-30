#if os(iOS)
import SwiftUI
import UIKit

// The Apple Intelligence Coach's own surfaces: what the Coach screen shows when the model cannot run (one
// view per `AppleCoachAvailability` case, never an error dump) and the Coach settings sheet with the backend
// choice and the "Use Apple servers when needed" toggle. Fork change.

/// The Coach screen when Apple Intelligence cannot answer: a title and the one thing that helps.
struct BroopInsightsCoachUnavailable: View {
    @EnvironmentObject private var coach: AICoachEngine
    let state: AppleCoachAvailability

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BroopBadge(size: 44, gradientRing: true)
                Text(verbatim: title)
                    .font(BroopType.demi(25))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                switch state {
                case .appleIntelligenceOff:
                    BroopInsightsPrimaryButton(title: String(localized: "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                case .modelDownloading:
                    ProgressView().tint(BroopPalette.textSecondary)
                default:
                    BroopInsightsOutlineButton(title: String(localized: "Use a cloud provider")) { coach.backend = .cloud }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private var title: String {
        switch state {
        case .appleIntelligenceOff: return String(localized: "Turn on Apple Intelligence")
        case .deviceNotEligible: return String(localized: "This iPhone can't run Apple Intelligence")
        case .modelDownloading: return String(localized: "Apple Intelligence is downloading")
        case .languageNotSupported: return String(localized: "Not available in this language yet")
        case .osTooOld: return String(localized: "Needs iOS 26 or later")
        case .onDeviceReady, .appleServersOnly: return String(localized: "Coach")
        }
    }
}

/// The reply being streamed. Observes only `CoachStreamState`, so each token re-renders this bubble alone.
/// Plain text while streaming (Markdown is laid out once, when the reply lands in the transcript).
struct BroopInsightsCoachStreamingReply: View {
    @ObservedObject var stream: CoachStreamState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stream.text.isEmpty {
                ProgressView().tint(BroopPalette.textSecondary)
                    .accessibilityLabel(Text("Coach is thinking"))
            } else {
                Text(verbatim: stream.text)
                    .font(BroopType.regular(17))
                    .foregroundStyle(BroopPalette.textBody)
                    // The Markdown theme's 0.42 em at 17 pt, so the text does not jump when the reply lands.
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if stream.offDevice { BroopInsightsAppleServersLabel() }
        }
    }
}

/// "via Apple servers": on every reply produced on Apple's Private Cloud Compute.
struct BroopInsightsAppleServersLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "icloud").font(.system(size: 11, weight: .semibold))
            BroopCaps(String(localized: "via Apple servers"), size: 9.5, color: BroopPalette.textSecondary)
        }
        .foregroundStyle(BroopPalette.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Answered on Apple's servers"))
    }
}

/// Coach settings: which backend answers, the Apple servers fallback, and the cloud provider's own settings.
struct BroopInsightsCoachSettingsSheet: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @State private var eveningReminder = EveningReviewReminder.storedEnabled
    @State private var eveningDenied = false
    @State private var wakeBrief = UserDefaults.standard.bool(forKey: CoachBriefScheduler.wakeKey)
    @State private var wakeDenied = false
    @Environment(\.dismiss) private var dismiss
    @State private var showProvider = false
    @State private var showCloudSettings = false
    @State private var showInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        BroopCaps(String(localized: "Coach answers with"), size: 10.5, color: BroopPalette.textSecondary)
                        BroopAccountGroup {
                            ForEach(CoachBackend.allCases) { backend in
                                backendRow(backend)
                            }
                        }
                    }
                    if coach.backend == .appleIntelligence {
                        BroopAccountGroup {
                            BroopAccountToggle(title: String(localized: "Use Apple servers when needed"),
                                               detail: AppleCoachProbe.privateCloudInBuild ? nil : String(localized: "Not available in this build"),
                                               isOn: $coach.allowAppleServers,
                                               enabled: AppleCoachProbe.privateCloudInBuild)
                        }
                        BroopAccountGroup {
                            BroopAccountToggle(title: String(localized: "Evening reminder"),
                                               detail: eveningDenied ? String(localized: "Notifications are off") : nil,
                                               isOn: eveningReminderBinding)
                            BroopAccountToggle(title: String(localized: "Morning brief when I wake"),
                                               detail: wakeDenied ? String(localized: "Notifications are off")
                                                   : String(localized: "Once last night is scored, a notification sums up your sleep and today, and the strap buzzes."),
                                               isOn: wakeBriefBinding)
                        }
                    } else {
                        BroopAccountGroup {
                            navRow(String(localized: "Provider, model and key")) { showProvider = true }
                            navRow(String(localized: "Data sharing and brief")) { showCloudSettings = true }
                        }
                    }
                    BroopAccountGroup {
                        navRow(String(localized: "About Coach")) { showInfo = true }
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            // WHOOP's AI settings chrome: a close glyph on the left and a caps title, one plain row.
            .safeAreaInset(edge: .top, spacing: 0) {
                BroopNavHeader(inline: true, onBack: { dismiss() }, leadingSymbol: "xmark",
                               center: { BroopNavTitle(title: String(localized: "Coach settings")) },
                               trailing: { EmptyView() })
            }
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showProvider) { CoachProviderSettingsView(coach: coach) }
        .sheet(isPresented: $showCloudSettings) { CoachSettingsView().environmentObject(coach).environmentObject(repo) }
        .sheet(isPresented: $showInfo) { BroopInsightsCoachInfoSheet().environmentObject(coach) }
    }

    private var eveningReminderBinding: Binding<Bool> {
        Binding(get: { eveningReminder }, set: { on in
            eveningReminder = on
            EveningReviewReminder.setEnabled(on, windDownFires: model.windDownFiresAhead(days: EveningReviewReminder.eveningsAhead),
                                             skipTonight: false) { granted in
                eveningReminder = granted
                eveningDenied = on && !granted
            }
        })
    }

    private var wakeBriefBinding: Binding<Bool> {
        Binding(get: { wakeBrief }, set: { on in
            wakeBrief = on
            CoachBriefScheduler.setWakeEnabled(on) { granted in
                wakeBrief = granted
                wakeDenied = on && !granted
            }
        })
    }

    private func backendRow(_ backend: CoachBackend) -> some View {
        Button { coach.backend = backend } label: {
            BroopAccountRow(title: backend.displayName) {
                Image(systemName: coach.backend == backend ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(coach.backend == backend ? BroopPalette.teal : BroopPalette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(coach.backend == backend ? .isSelected : [])
    }

    private func navRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BroopAccountRow(title: title) {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BroopPalette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif

#if os(iOS)
/// Home's Coach brief: the model's headline and a sentence per metric, each beside the metric's value from
/// the app's resolvers (`CoachFactsSource.briefValue`), so the numbers on the card never come from the model.
/// Written when the app comes to the foreground, at most once a day and again after new data. The only view
/// on Home that observes the Coach engine.
struct BroopInsightsCoachBriefCard: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let onOpenCoach: () -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        Group {
            if coach.usesApple, let evening = eveningReview {
                BroopInsightsCoachEveningCard(review: evening, onOpenCoach: onOpenCoach)
            } else if coach.usesApple, let brief = coach.appleBrief, brief.day == Repository.dayString(Date()) {
                Button(action: onOpenCoach) { card(brief) }
                    .buttonStyle(BroopPressableStyle())
                    // Reloaded on new data too: values read before the store finished loading would stay empty.
                    .task(id: "\(brief.day)|\(brief.dataKey)|\(repo.refreshSeq)") { values = await load(brief) }
            }
        }
        .task(id: "\(scenePhase)|\(repo.refreshSeq)") {
            guard scenePhase == .active else { return }
            await coach.refreshAppleBriefIfNeeded()
            await coach.refreshAppleEveningIfNeeded()
            await armEveningReminder()
        }
    }

    /// From 17:00, today's evening review replaces the morning brief.
    private var eveningReview: AppleCoachBrief? {
        guard AppleCoachEveningPolicy.isEvening(Date()), let review = coach.appleEvening,
              review.day == Repository.dayString(Date()) else { return nil }
        return review
    }

    /// Re-arm the evening-review reminders from the current wind-down times, skipping tonight's once tonight's
    /// journal day (tomorrow's key) has answers.
    private func armEveningReminder() async {
        guard EveningReviewReminder.isEnabled else { return }
        let day = Repository.localDayKey(AppleCoachEveningPolicy.journalDay(for: Date()))
        let answers = await repo.nativeJournalAnswers(day: day)
        let amounts = await repo.nativeJournalNumeric(day: day)
        let logged = !answers.isEmpty || !amounts.isEmpty
        EveningReviewReminder.schedule(windDownFires: model.windDownFiresAhead(days: EveningReviewReminder.eveningsAhead),
                                       skipTonight: logged)
    }

    private func card(_ brief: AppleCoachBrief) -> some View {
        BroopCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    BroopBadge(size: 22, gradientRing: true)
                    BroopCaps(String(localized: "Coach brief"), size: 11)
                    Spacer()
                    if brief.offDevice { BroopInsightsAppleServersLabel() }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .light))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
                Text(verbatim: brief.headline)
                    .font(BroopType.demi(17))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(brief.points, id: \.metric) { point in
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load(_ brief: AppleCoachBrief) async -> [String: String] {
        guard let source = coach.apple.source else { return [:] }
        var out: [String: String] = [:]
        for p in brief.points {
            if let m = CoachMetric(rawValue: p.metric), let v = await source.briefValue(m) { out[p.metric] = v }
        }
        return out
    }
}
#endif

#if os(iOS)
/// About Coach: where it runs, what leaves the phone and when, what it can and can't do, and that it is not
/// medical advice. Reached from Coach settings and the Coach menu.
struct BroopInsightsCoachInfoSheet: View {
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(String(localized: "Privacy"),
                            coach.allowAppleServers && AppleCoachProbe.privateCloudInBuild
                            ? String(localized: "Runs on this iPhone. Replies from Apple's servers are labelled.")
                            : String(localized: "Runs on this iPhone. Nothing leaves it."))
                    section(String(localized: "Numbers"),
                            String(localized: "Every number comes from the app, not the model."))
                    section(String(localized: "Not medical advice"),
                            String(localized: "For your health, talk to a doctor. In an emergency, call your local emergency number."))
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            // WHOOP's AI settings chrome: a close glyph on the left and a caps title, one plain row.
            .safeAreaInset(edge: .top, spacing: 0) {
                BroopNavHeader(inline: true, onBack: { dismiss() }, leadingSymbol: "xmark",
                               center: { BroopNavTitle(title: String(localized: "About Coach")) },
                               trailing: { EmptyView() })
            }
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BroopCaps(title, size: 11)
            BroopInsightsBody(text: body, size: 15)
        }
    }
}
#endif
