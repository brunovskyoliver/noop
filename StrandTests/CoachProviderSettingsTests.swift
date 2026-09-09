import XCTest
@testable import Strand

@MainActor
final class CoachProviderSettingsTests: XCTestCase {
    func testCustomProviderAcceptsHTTPOnPublicAndVPNHosts() {
        for url in ["http://example.com:8080/v1", "http://100.64.0.2:11434/v1",
                    "http://192.168.1.20/v1", "https://example.com/v1"] {
            XCTAssertNoThrow(try AIProvider.guardCustomBaseURL(url), url)
        }
    }

    func testCustomProviderStillRejectsInvalidURLsAndOtherSchemes() {
        for url in ["", "example.com/v1", "http://", "ftp://example.com/v1", "file:///tmp/model"] {
            XCTAssertThrowsError(try AIProvider.guardCustomBaseURL(url), url)
        }
    }

    func testSavingConnectionPreservesConversationAndPersistsEdits() {
        withRestoredPreferences {
            let coach = makeCoach()
            let messages = [ChatMessage(role: .user, text: "Keep this conversation")]
            coach.messages = messages
            coach.availableModels = ["old-server-model"]
            XCTAssertTrue(coach.saveProviderSettings(baseURL: " http://example.com:8080/v1/chat/completions/ ",
                                                     authHeader: .xAPIKey, model: " new-model ", replacementKey: ""))
            XCTAssertEqual(coach.customBaseURL, "http://example.com:8080/v1")
            XCTAssertEqual(coach.customAuthHeader, .xAPIKey)
            XCTAssertEqual(coach.model, "new-model")
            XCTAssertEqual(coach.messages, messages)
            XCTAssertTrue(coach.isConfigured)
            XCTAssertEqual(coach.availableModels, ["new-model"])
            XCTAssertEqual(UserDefaults.standard.string(forKey: AIProvider.customBaseURLKey), coach.customBaseURL)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "ai.model"), "new-model")
        }
    }

    func testInvalidSettingsLeaveTheActiveConnectionUntouched() {
        withRestoredPreferences {
            let coach = makeCoach()
            XCTAssertFalse(coach.saveProviderSettings(baseURL: "ftp://example.com", authHeader: .xAPIKey,
                                                      model: "new-model", replacementKey: ""))
            XCTAssertEqual(coach.customBaseURL, "http://localhost:11434/v1")
            XCTAssertEqual(coach.customAuthHeader, .bearer)
            XCTAssertEqual(coach.model, "old-model")
            XCTAssertTrue(coach.isConfigured)
        }
    }

    private func makeCoach() -> AICoachEngine {
        let coach = AICoachEngine(repo: Repository(deviceId: "test-coach-provider-settings"))
        coach.provider = .custom
        coach.customBaseURL = "http://localhost:11434/v1"
        coach.customAuthHeader = .bearer
        coach.model = "old-model"
        coach.customConnected = true
        return coach
    }

    private func withRestoredPreferences(_ test: () -> Void) {
        let defaults = UserDefaults.standard
        let keys = ["ai.provider", "ai.model", "ai.customConnected", AIProvider.customBaseURLKey,
                    AIProvider.customAuthHeaderKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        test()
    }
}
