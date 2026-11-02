import XCTest
import GRDB
@testable import WhoopStore
@testable import WhoopProtocol

final class StorageMaintenanceTests: XCTestCase {
    private let now = 100 * 86_400
    private var floor: Int { (now - RawRetention.fullDetailDays * 86_400) }

    private func seeded() async throws -> WhoopStore {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        // Two minutes per side of the floor at 1 Hz, in both heart rate and gravity.
        let old = (floor - 120)..<floor, recent = floor..<(floor + 120)
        let hr = (Array(old) + Array(recent)).map { HRSample(ts: $0, bpm: $0 < floor ? 60 + ($0 % 2) * 2 : 70) }
        let grav = (Array(old) + Array(recent)).map { GravitySample(ts: $0, x: 0, y: 0, z: 1) }
        _ = try await store.insert(Streams(hr: hr, gravity: grav), deviceId: "d")
        return store
    }

    func testFloorClampsRescoringAwayFromStrippedDays() {
        let today = 100 * 86_400, lookback = 30 * 3600
        XCTAssertEqual(RawRetention.scorableDayCount(maxDays: 21, todayStart: today, lookbackSeconds: lookback, floorTs: nil), 21)
        XCTAssertEqual(RawRetention.scorableDayCount(maxDays: 21, todayStart: today, lookbackSeconds: lookback,
                                                     floorTs: today - 30 * 86_400), 21,
                       "the normal window must fit inside the retained days")
        let clamped = RawRetention.scorableDayCount(maxDays: 3650, todayStart: today, lookbackSeconds: lookback,
                                                    floorTs: today - 30 * 86_400)
        XCTAssertEqual(clamped, 29, "the oldest scorable day's lookback stays at or above the floor")
        XCTAssertGreaterThanOrEqual(today - (clamped - 1) * 86_400 - lookback, today - 30 * 86_400)
        XCTAssertEqual(RawRetention.scorableDayCount(maxDays: 21, todayStart: today, lookbackSeconds: lookback, floorTs: today), 1)
    }

    /// Rebuild and daily trim must leave the same data, so both paths run against the same seed.
    func testOldHeartRateIsThinnedAndOtherOldStreamsGo() async throws {
        for compact in [true, false] {
            let store = try await seeded()
            try await store.runStorageMaintenance(now: now, compact: compact)
            let hr = try await store.hrSamples(deviceId: "d", from: 0, to: now, limit: 10_000)
            XCTAssertEqual(hr.filter { $0.ts < floor }.count, 120 / RawRetention.thinnedHRBucketSeconds)
            XCTAssertEqual(hr.filter { $0.ts < floor }.first?.bpm, 61, "a bucket holds the average of its seconds")
            XCTAssertEqual(hr.filter { $0.ts >= floor }.count, 120, "recent detail is untouched")
            let grav = try await store.gravitySamples(deviceId: "d", from: 0, to: now, limit: 10_000)
            XCTAssertEqual(grav.count, 120)
            XCTAssertTrue(grav.allSatisfy { $0.ts >= floor })
            let stored = try await store.rawDataFloor()
            XCTAssertEqual(stored, floor)
        }
    }

    func testCompactionKeepsTriggersIndexesAndWritesWork() async throws {
        let store = try await seeded()
        let before = try await store.dbWriter.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('index','trigger') AND sql IS NOT NULL")
        }
        let needed = try await store.storageNeedsCompaction()
        XCTAssertTrue(needed)
        try await store.runStorageMaintenance(now: now, compact: true)
        let after = try await store.dbWriter.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('index','trigger') AND sql IS NOT NULL")
        }
        XCTAssertEqual(before, after)
        let stillNeeded = try await store.storageNeedsCompaction()
        XCTAssertFalse(stillNeeded)

        let revision: () async throws -> Int = {
            try await store.dbWriter.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(revision),0) FROM analysisRevision") ?? 0 }
        }
        let r0 = try await revision()
        _ = try await store.insert(Streams(hr: [HRSample(ts: floor + 500, bpm: 80)]), deviceId: "d")
        let r1 = try await revision()
        XCTAssertGreaterThan(r1, r0, "the revision trigger must survive the rebuild or caches go stale")
    }

    func testFloorNeverMovesBackward() async throws {
        let store = try await seeded()
        try await store.runStorageMaintenance(now: now, compact: false)
        try await store.runStorageMaintenance(now: now - 40 * 86_400, compact: false)
        let stored = try await store.rawDataFloor()
        XCTAssertEqual(stored, floor)
    }

    /// Runs the real thing over a copy of a real database. Skipped unless pointed at one.
    func testRealDatabaseCopy() async throws {
        guard let path = ProcessInfo.processInfo.environment["NOOP_MAINT_DB"] else { throw XCTSkip("NOOP_MAINT_DB unset") }
        let store = try await WhoopStore(path: path)
        let start = Date()
        try await store.runStorageMaintenance(now: Int(Date().timeIntervalSince1970), compact: true)
        print("maintenance took \(Date().timeIntervalSince(start)) s")
    }
}
