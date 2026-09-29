#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

/// The optional monthly check-in: PSS-4, GAD-2 and PHQ-2 with their published wording and answer scales,
/// scored by `MindCheckIn` and stored locally. The result screen reports totals without
/// labels like "anxious" or "depressed"; at or above the two-item screening cutoff it shows one neutral
/// suggestion to talk to a professional.
struct BroopMindCheckInSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    private struct Question: Identifiable {
        let form: MindCheckIn.Form
        let index: Int
        let text: String
        var id: String { "\(form.rawValue)\(index)" }
    }

    private static let pssOptions = [String(localized: "Never"), String(localized: "Almost never"),
                                     String(localized: "Sometimes"), String(localized: "Fairly often"),
                                     String(localized: "Very often")]
    private static let twoWeekOptions = [String(localized: "Not at all"), String(localized: "Several days"),
                                         String(localized: "More than half the days"),
                                         String(localized: "Nearly every day")]

    private let questions: [Question] = [
        .init(form: .pss4, index: 0, text: String(localized: "In the last month, how often have you felt that you were unable to control the important things in your life?")),
        .init(form: .pss4, index: 1, text: String(localized: "In the last month, how often have you felt confident about your ability to handle your personal problems?")),
        .init(form: .pss4, index: 2, text: String(localized: "In the last month, how often have you felt that things were going your way?")),
        .init(form: .pss4, index: 3, text: String(localized: "In the last month, how often have you felt difficulties were piling up so high that you could not overcome them?")),
        .init(form: .gad2, index: 0, text: String(localized: "Over the last 2 weeks, how often have you been bothered by feeling nervous, anxious or on edge?")),
        .init(form: .gad2, index: 1, text: String(localized: "Over the last 2 weeks, how often have you been bothered by not being able to stop or control worrying?")),
        .init(form: .phq2, index: 0, text: String(localized: "Over the last 2 weeks, how often have you been bothered by little interest or pleasure in doing things?")),
        .init(form: .phq2, index: 1, text: String(localized: "Over the last 2 weeks, how often have you been bothered by feeling down, depressed or hopeless?")),
    ]

    @State private var saving = false
    @State private var saveFailed = false
    @State private var answers: [String: Int] = [:]
    @State private var saved: [MindCheckIn.Form: Int]?

    private func totals() -> [MindCheckIn.Form: Int]? {
        var out: [MindCheckIn.Form: Int] = [:]
        for form in MindCheckIn.Form.allCases {
            let a = questions.filter { $0.form == form }.sorted { $0.index < $1.index }.compactMap { answers[$0.id] }
            guard let score = MindCheckIn.score(form, answers: a) else { return nil }
            out[form] = score
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let saved { result(saved) } else { form }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(BroopBackground())
            .broopSheetBar(String(localized: "Monthly Check-in")) { dismiss() }
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled(saving)
            .alert("Check-in was not saved", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: { Text("Your answers are still here. Please try again.") }
        }
    }

    @ViewBuilder private var form: some View {
        Text("Eight short questions. There are no right answers, and your scores are stored locally.")
            .font(BroopType.regular(15))
            .foregroundStyle(BroopPalette.textBody)
        ForEach(questions) { q in
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: q.text)
                    .font(BroopType.demi(16))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                let options = q.form == .pss4 ? Self.pssOptions : Self.twoWeekOptions
                VStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.element) { value, label in
                        let selected = answers[q.id] == value
                        Button { answers[q.id] = value } label: {
                            HStack {
                                Text(verbatim: label).font(BroopType.medium(15))
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17))
                            }
                            .foregroundStyle(selected ? BroopPalette.textPrimary : BroopPalette.textBody)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous)
                                .fill(selected ? BroopPalette.row : BroopPalette.card))
                        }
                        .buttonStyle(BroopPressableStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        BroopHealthButton(title: String(localized: "Save check-in"), symbol: "checkmark") {
            guard let t = totals() else { return }
            saving = true
            Task {
                defer { saving = false }
                do {
                    try await repo.saveMindCheckIn(day: Repository.dayString(Date()), totals: t)
                    withAnimation(.snappy) { saved = t }
                } catch { saveFailed = true }
            }
        }
        .disabled(totals() == nil || saving)
        BroopFootnote(text: String(localized: "PSS-4 (Cohen, 1983), GAD-2 and PHQ-2 (Kroenke, 2003 and 2007). Self-reflection, not a diagnosis."))
    }

    @ViewBuilder private func result(_ t: [MindCheckIn.Form: Int]) -> some View {
        BroopHealthCard {
            VStack(alignment: .leading, spacing: 14) {
                BroopCaps(String(localized: "Saved"), size: 11, color: BroopPalette.textSecondary)
                resultRow(String(localized: "Perceived stress"), "PSS-4", t[.pss4], MindCheckIn.Form.pss4.maxScore)
                resultRow(String(localized: "Worry"), "GAD-2", t[.gad2], MindCheckIn.Form.gad2.maxScore)
                resultRow(String(localized: "Mood"), "PHQ-2", t[.phq2], MindCheckIn.Form.phq2.maxScore)
            }
        }
        let flagged = MindCheckIn.atOrAboveCutoff(.gad2, score: t[.gad2] ?? 0)
            || MindCheckIn.atOrAboveCutoff(.phq2, score: t[.phq2] ?? 0)
        if flagged {
            BroopHealthInfoBanner(symbol: "person.2", text: String(localized: "Some of your answers were in the range where talking things through with a doctor or counsellor can help. That's a common step, and this check-in can't tell you more than that."))
        }
        Text("Higher numbers mean more of that feeling over the period asked about. Broop compares them only with your own past check-ins, Charge and HRV.")
            .font(BroopType.regular(14))
            .foregroundStyle(BroopPalette.textSecondary)
        BroopHealthButton(title: String(localized: "Done")) { dismiss() }
    }

    private func resultRow(_ title: String, _ form: String, _ score: Int?, _ max: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(title, size: 11.5)
                Text(verbatim: form).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
            }
            Spacer()
            Text(verbatim: score.map(String.init) ?? "--").font(BroopType.number(24)).foregroundStyle(BroopPalette.textPrimary)
            Text(verbatim: "/\(max)").font(BroopType.medium(12)).foregroundStyle(BroopPalette.textSecondary)
        }
    }
}
#endif
