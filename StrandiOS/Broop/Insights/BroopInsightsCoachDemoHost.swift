#if os(iOS) && DEBUG
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// DEBUG verification harness: the Broop Coach screen, optionally sending `--coach-questions "a|b|c"` one
/// after another and printing each question, reply and turn report (route, tools called, number check) as a
/// `COACH_QA` JSON line. Stripped from Release.
struct BroopInsightsCoachDemoHost: View {
    @EnvironmentObject private var coach: AICoachEngine

    var body: some View {
        BroopInsightsCoachView()
            .task {
                let args = CommandLine.arguments
                if args.contains("--coach-clear") { coach.clearConversation() }
                #if canImport(FoundationModels)
                if args.contains("--coach-ping"), #available(iOS 26.0, *) {
                    let m = SystemLanguageModel.default
                    print("COACH_PING availability=\(m.availability) context=\(m.contextSize) en=\(m.supportsLocale(Locale(identifier: "en_US")))")
                    let probe = await AppleCoachProbe.inputs(fallbackAllowed: true, locale: AppLanguage.activeLocale)
                    print("COACH_PING routing=\(probe)")
                    if #available(iOS 27.0, *) {
                        let pcc = PrivateCloudComputeLanguageModel()
                        print("COACH_PING pcc=\(pcc.availability) quota=\(pcc.quotaUsage)")
                        do { print("COACH_PING pccReply=" + (try await LanguageModelSession(model: pcc).respond(to: "Say hello.").content)) }
                        catch { print("COACH_PING pcc error=\(error)") }
                    }
                    do { print("COACH_PING bare=" + (try await LanguageModelSession().respond(to: "Say hello.").content)) }
                    catch { print("COACH_PING bare error=\(error)") }
                    do { print("COACH_PING instr=" + (try await LanguageModelSession(instructions: "Answer in one sentence.").respond(to: "Say hello.").content)) }
                    catch { print("COACH_PING instr error=\(error)") }
                }
                #endif
                guard let i = args.firstIndex(of: "--coach-questions"), i + 1 < args.count else { return }
                await coach.refreshAppleAvailability()
                try? await Task.sleep(for: .seconds(2))
                for question in args[i + 1].components(separatedBy: "|") where !question.isEmpty {
                    await coach.send(question)
                    let r = coach.apple.lastReport
                    let reply = coach.messages.last(where: { $0.role == .assistant && !$0.isNotice })
                    let row: [String: Any] = [
                        "question": question,
                        "reply": coach.errorText == nil ? (reply?.text ?? "") : "",
                        "provider": reply?.provider ?? "",
                        "error": coach.errorText ?? "",
                        "route": "\(r.route)",
                        "tools": r.toolCalls,
                        "firstOffending": r.firstOffending,
                        "retried": r.retried,
                        "retryOffending": r.retryOffending,
                        "factsOnly": r.factsOnly,
                        "failure": r.failure.map { "\($0)" } ?? "",
                        "condensed": r.condensed,
                        "errorDetail": r.errorDetail ?? "",
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
                       let line = String(data: data, encoding: .utf8) {
                        print("COACH_QA " + line)
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
                print("COACH_DONE")
            }
    }
}
#endif
