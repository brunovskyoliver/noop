import XCTest
import GRDB
import SQLite3
@testable import WhoopStore

final class AnalysisInputFingerprintTests: XCTestCase {
    private final class Progress: @unchecked Sendable {
        var steps = 0
    }

    func testFingerprintWorkDoesNotGrowWithDenseRawHistory() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: """
                WITH RECURSIVE numbers(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<100000)
                INSERT INTO hrSample(deviceId, ts, bpm) SELECT 'strap', n, 60 FROM numbers
                """)
        }
        let progress = Progress()
        let context = Unmanaged.passUnretained(progress).toOpaque()
        try await store.registryWriter.read { db in
            sqlite3_progress_handler(db.sqliteConnection, 100, { context in
                guard let context else { return 0 }
                Unmanaged<Progress>.fromOpaque(context).takeUnretainedValue().steps += 100
                return 0
            }, context)
        }
        _ = try await store.analysisInputFingerprint()
        try await store.registryWriter.read { db in
            sqlite3_progress_handler(db.sqliteConnection, 0, nil, nil)
        }
        XCTAssertLessThan(progress.steps, 1000, "Change detection must read revision metadata, not the 100,000 HR rows")
    }

    func testRawCorrectionDeletionAndRegistryChangesMoveTheInputWitness() async throws {
        let store = try await WhoopStore.inMemory()
        var previous = try await store.analysisInputFingerprint()
        let mutations = [
            "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',100,60)",
            "UPDATE hrSample SET bpm=70 WHERE deviceId='strap'",
            "UPDATE hrSample SET ts=90 WHERE deviceId='strap'",
            "DELETE FROM hrSample WHERE deviceId='strap'",
            "UPDATE pairedDevice SET model='5.0' WHERE id='my-whoop'",
            "UPDATE pairedDevice SET status='archived' WHERE id='my-whoop'",
        ]
        for sql in mutations {
            try await store.registryWriter.write { db in try db.execute(sql: sql) }
            let next = try await store.analysisInputFingerprint()
            XCTAssertNotEqual(previous, next, sql)
            previous = next
        }
    }

    func testCheckpointWritesDoNotInvalidateRawInputs() async throws {
        let store = try await WhoopStore.inMemory()
        let before = try await store.analysisInputFingerprint()
        try await store.saveAnalysisCheckpoint(day: "night", deviceId: "strap", key: "key", payload: Data([1]))
        let after = try await store.analysisInputFingerprint()
        XCTAssertEqual(before, after)
    }

    func testEveryScoringStreamInvalidatesGlobalAndWindowWitnesses() async throws {
        let store = try await WhoopStore.inMemory()
        let streams = [
            ("hrSample", "bpm", "60"), ("ppgHrSample", "bpm,conf", "60,0.9"),
            ("rrInterval", "rrMs", "1000"), ("respSample", "raw", "10"),
            ("spo2Sample", "red,ir", "10,20"), ("gravitySample", "x,y,z", "1,2,3"),
            ("stepSample", "counter", "10"), ("skinTempSample", "raw", "3300"),
            ("sleepStateSample", "state", "1"), ("event", "kind,payloadJSON", "'wrist','{}'"),
            ("v18AuxSample", "fields", "X'00'"),
        ]
        for (table, columns, values) in streams {
            var global = try await store.analysisInputFingerprint()
            var window = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
            let mutations = [
                "INSERT INTO \(table)(deviceId,ts,\(columns)) VALUES ('strap',86410,\(values))",
                "UPDATE \(table) SET ts=ts WHERE deviceId='strap'",
                "DELETE FROM \(table) WHERE deviceId='strap'",
            ]
            for sql in mutations {
                try await store.registryWriter.write { db in try db.execute(sql: sql) }
                let nextGlobal = try await store.analysisInputFingerprint()
                let nextWindow = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
                XCTAssertNotEqual(global, nextGlobal, sql)
                XCTAssertNotEqual(window, nextWindow, sql)
                global = nextGlobal
                window = nextWindow
            }
        }
    }

    func testRolledBackChangesLeaveGlobalWitnessUnchanged() async throws {
        let store = try await WhoopStore.inMemory()
        let before = try await store.analysisInputFingerprint()
        enum Rollback: Error { case requested }
        do {
            try await store.registryWriter.write { db in
                try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',100,60)")
                throw Rollback.requested
            }
        } catch Rollback.requested {}
        let after = try await store.analysisInputFingerprint()
        XCTAssertEqual(before, after)
    }

    func testSourceWipeAndReplacementCannotReuseEqualRevisionCounters() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',86410,60)")
        }
        let before = try await store.analysisInputFingerprint()
        let window = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        try await store.deleteAllData(deviceId: "strap")
        try await store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample(deviceId,ts,bpm) VALUES ('strap',86410,70)")
        }
        let after = try await store.analysisInputFingerprint()
        let replacementWindow = try await store.analysisWindowRevision(deviceId: "strap", from: 86400, to: 172799)
        XCTAssertNotEqual(before, after)
        XCTAssertNotEqual(window, replacementWindow)
        let deletedSourceRevisions = try await store.registryWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM analysisRevision WHERE deviceId='strap'")
        }
        XCTAssertEqual(deletedSourceRevisions, 1, "Only the replacement row may remain after the wipe")
    }
}
