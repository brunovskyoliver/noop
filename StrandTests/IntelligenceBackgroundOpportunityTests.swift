import XCTest
import WhoopProtocol
import WhoopStore
@testable import Strand

@MainActor
final class IntelligenceBackgroundOpportunityTests: XCTestCase {
    private let keys = [
        "noop.recentAnalysisAttempt", "noop.analyzeWatermark",
        RescoreBackgroundScheduler.owedKey, RescoreBackgroundScheduler.owedTokenKey,
        RescoreBackgroundScheduler.owedAfterCompletedPassKey,
        RescoreBackgroundScheduler.lastAttemptStartedAtKey,
        RescoreBackgroundScheduler.lastPassSecondsKey,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func engine() async throws -> IntelligenceEngine {
        let store = try await WhoopStore.inMemory()
        let now = Int(Date().timeIntervalSince1970)
        _ = try await store.insert(Streams(hr: (0..<250).map {
            HRSample(ts: now - 300 + $0, bpm: 60)
        }), deviceId: "my-whoop")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        return IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "my-whoop")
    }

    func testShortWakePublishesRecentThenQueuesHistoryWithoutStartingFullPass() async throws {
        let engine = try await engine()
        var lines: [String] = []
        engine.diagnosticSink = { line, _ in lines.append(line) }
        await RescoreBackgroundScheduler.$backgroundStateOverride.withValue(true) {
            await engine.analyzeRecent(maxDays: 21, triggerLabel: "test-short-wake")
        }
        XCTAssertFalse(engine.results.isEmpty, "Recent scores must publish during the short opportunity")
        XCTAssertEqual(lines.filter { $0.contains("re-score: trigger=") }.count, 1, lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains { $0.contains("older history queued") })
        XCTAssertTrue(RescoreBackgroundScheduler.isRescoreOwed)
        XCTAssertNil(UserDefaults.standard.string(forKey: "noop.analyzeWatermark"),
                     "A partial window must not mark all history current")
        lines.removeAll()
        await RescoreBackgroundScheduler.$backgroundStateOverride.withValue(true) {
            await engine.analyzeRecent(maxDays: 21, triggerLabel: "test-throttled-wake")
        }
        XCTAssertFalse(lines.contains { $0.contains("re-score: trigger=") }, "The recent retry cooldown must survive another wake")
        await RescoreBackgroundScheduler.$backgroundStateOverride.withValue(false) {
            await engine.analyzeRecent(maxDays: 21, triggerLabel: "test-foreground")
        }
        XCTAssertFalse(RescoreBackgroundScheduler.isRescoreOwed, "Foreground work must drain older history")
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "noop.analyzeWatermark"))
    }

    func testProcessingGrantCompletesFullHistoryInBackground() async throws {
        let engine = try await engine()
        await RescoreBackgroundScheduler.$backgroundStateOverride.withValue(true) {
            await RescoreBackgroundScheduler.$hasExtendedProcessingTime.withValue(true) {
                await engine.analyzeRecent(maxDays: 21)
            }
        }
        XCTAssertFalse(engine.results.isEmpty)
        XCTAssertFalse(RescoreBackgroundScheduler.isRescoreOwed)
        XCTAssertNotNil(UserDefaults.standard.string(forKey: "noop.analyzeWatermark"))
    }
}
