import XCTest
import WhoopProtocol
import WhoopStore
@testable import Strand

@MainActor
final class IntelligenceCheckpointIntegrationTests: XCTestCase {
    func testColdEngineReusesSavedScanAndCorrectionInvalidatesIt() async throws {
        let store = try await WhoopStore.inMemory()
        let now = Int(Date().timeIntervalSince1970)
        _ = try await store.insert(Streams(hr: (0..<250).map {
            HRSample(ts: now - 300 + $0, bpm: 60)
        }), deviceId: "my-whoop")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let profile = ProfileStore()
        let first = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop")
        await first.analyzeRecent(maxDays: 1)
        let second = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop")
        var lines: [String] = []
        second.diagnosticSink = { line, _ in lines.append(line) }
        await second.analyzeRecent(maxDays: 1)
        XCTAssertTrue(lines.contains { $0.contains("dayCache reused=1/") }, lines.joined(separator: "\n"))
        XCTAssertEqual(first.results.first?.day, second.results.first?.day)
        _ = try await store.insert(Streams(hr: [HRSample(ts: now - 20, bpm: 75)]), deviceId: "my-whoop")
        lines.removeAll()
        await second.analyzeRecent(maxDays: 1)
        XCTAssertTrue(lines.contains { $0.contains("dayCache reused=0/") }, lines.joined(separator: "\n"))
    }
}
