import XCTest
import GRDB
@testable import WhoopStore

final class AnalysisCheckpointTests: XCTestCase {
    func testCorrectionWithSameCountAndTimestampInvalidatesCheckpoint() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',86410,60)")
        }
        let first = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        try await store.saveAnalysisCheckpoint(day: "night", deviceId: "strap", key: first, payload: Data([1,2,3]))
        try await store.registryWriter.write { db in
            try db.execute(sql: "UPDATE hrSample SET bpm = 70 WHERE deviceId = 'strap'")
        }
        let second = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        XCTAssertNotEqual(first, second)
        let stale = try await store.analysisCheckpoint(day: "night", key: second)
        XCTAssertNil(stale)
    }

    func testRevisionTracksDeleteAndTimestampMoveWithoutInvalidatingOtherOwner() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',86410,60)")
        }
        let before = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        try await store.registryWriter.write { db in
            try db.execute(sql: "UPDATE hrSample SET ts = 172810 WHERE deviceId = 'strap'")
        }
        let oldDay = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        let newDay = try await store.analysisWindowRevision(deviceId: "strap", from: 172800, to: 259199)
        let other = try await store.analysisWindowRevision(deviceId: "other", from: 0, to: 300000)
        XCTAssertNotEqual(before, oldDay)
        XCTAssertFalse(newDay.isEmpty)
        XCTAssertEqual(other, "")
        try await store.registryWriter.write { db in try db.execute(sql: "DELETE FROM hrSample") }
        let deleted = try await store.analysisWindowRevision(deviceId: "strap", from: 172800, to: 259199)
        XCTAssertNotEqual(newDay, deleted)
    }

    func testRollbackDoesNotAdvanceRevision() async throws {
        let store = try await WhoopStore.inMemory()
        enum Rollback: Error { case requested }
        do {
            try await store.registryWriter.write { db in
                try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',86410,60)")
                throw Rollback.requested
            }
        } catch Rollback.requested {}
        let revision = try await store.analysisWindowRevision(deviceId: "strap", from: 0, to: 200000)
        XCTAssertEqual(revision, "")
    }

    func testCompletedCheckpointSurvivesReopeningDatabase() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let store = try await WhoopStore(path: url.path)
        try await store.saveAnalysisCheckpoint(day: "2026-09-10", deviceId: "strap", key: "version|owner|config|revision", payload: Data([9,8,7]))
        let reopened = try await WhoopStore(path: url.path)
        let result = try await reopened.analysisCheckpoint(day: "2026-09-10", key: "version|owner|config|revision")
        XCTAssertEqual(result, Data([9,8,7]))
        let changedConfig = try await reopened.analysisCheckpoint(day: "2026-09-10", key: "new-config")
        XCTAssertNil(changedConfig)
    }
}
