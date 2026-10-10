import XCTest
import WhoopProtocol
import WhoopStore
@testable import Strand

@MainActor
final class IntelligenceCheckpointIntegrationTests: XCTestCase {
    func testCorrectingFamilyForReaddedStrapInvalidatesSavedScan() async throws {
        let store = try await WhoopStore.inMemory()
        let now = Int(Date().timeIntervalSince1970)
        let owner = "re-added-strap"
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        try registry.add(PairedDevice(id: owner, brand: "WHOOP", model: "4.0",
                                     sourceKind: .historyBLE, capabilities: [.hr, .hrv, .sleep],
                                     status: .paired, addedAt: now, lastSeenAt: now))
        try registry.setActive(owner)
        _ = try await store.insert(Streams(hr: (0..<250).map {
            HRSample(ts: now - 300 + $0, bpm: 60)
        }), deviceId: owner)
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
        try registry.setModel(owner, model: "5.0")
        let corrected = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop")
        lines.removeAll()
        corrected.diagnosticSink = { line, _ in lines.append(line) }
        await corrected.analyzeRecent(maxDays: 1)
        XCTAssertTrue(lines.contains { $0.contains("dayCache reused=0/") }, lines.joined(separator: "\n"))
    }

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
        let originalMetrics = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000", to: "9999")
        XCTAssertFalse(originalMetrics.isEmpty)
        let second = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop")
        var lines: [String] = []
        second.diagnosticSink = { line, _ in lines.append(line) }
        await second.analyzeRecent(maxDays: 1)
        XCTAssertTrue(lines.contains { $0.contains("dayCache reused=1/") }, lines.joined(separator: "\n"))
        XCTAssertEqual(first.results.first?.day, second.results.first?.day)
        let reusedMetrics = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000", to: "9999")
        XCTAssertEqual(originalMetrics, reusedMetrics, "Checkpoint reuse must preserve every stored metric")
        _ = try await store.insert(Streams(hr: [HRSample(ts: now - 20, bpm: 75)]), deviceId: "my-whoop")
        lines.removeAll()
        await second.analyzeRecent(maxDays: 1)
        XCTAssertTrue(lines.contains { $0.contains("dayCache reused=0/") }, lines.joined(separator: "\n"))
        let correctedMetrics = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000", to: "9999")
        for metric in correctedMetrics {
            try await store.saveAnalysisCheckpoint(day: metric.day, deviceId: "my-whoop",
                                                   key: "test-force-miss", payload: Data())
        }
        let corrected = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop")
        await corrected.analyzeRecent(maxDays: 1)
        let correctedReuse = try await store.dailyMetrics(deviceId: "my-whoop-noop", from: "0000", to: "9999")
        XCTAssertEqual(correctedMetrics, correctedReuse, "Cached and freshly scanned metrics must match after a correction")
    }
}
