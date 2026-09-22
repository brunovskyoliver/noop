import XCTest
import WhoopStore
import WhoopProtocol
@testable import Strand

@MainActor
final class RepositorySyncPerformanceTests: XCTestCase {
    private func workout(start: Int, source: String = "manual", rich: Bool = false) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: start + 3600, sport: "Running", source: source,
                   durationS: 3600, energyKcal: rich ? 400 : nil,
                   avgHr: rich ? 130 : nil, maxHr: rich ? 160 : nil,
                   strain: rich ? 12 : nil, distanceM: rich ? 5000 : nil,
                   zonesJSON: nil, notes: nil, steps: nil,
                   suggestedClass: nil, suggestedClassConfidence: nil)
    }

    private func repository(_ store: WhoopStore) -> Repository {
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        return repo
    }

    func testDayWindowReconcilesOneWorkoutInsteadOfThreeHundred() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "Strap")
        let start = Int(Date().timeIntervalSince1970) - 7200
        let rows = (0..<301).map { workout(start: start - $0 * 86_400) }
        _ = try await store.upsertWorkouts(rows, deviceId: "my-whoop")
        try await store.insert(Streams(hr: (0..<120).map { HRSample(ts: start + $0, bpm: 120) }),
                               deviceId: "my-whoop")
        let repo = repository(store)

        let full = await repo.workoutRows()
        let fullReads = repo.loadFireCounts["workoutHrWindows", default: 0]
        let scoped = await repo.workoutRows(from: start, to: start + 7200)
        let scopedReads = repo.loadFireCounts["workoutHrWindows", default: 0] - fullReads

        XCTAssertEqual(scoped, full.filter { $0.startTs >= start && $0.startTs < start + 7200 })
        XCTAssertEqual(scoped.first?.avgHr, 120, "The displayed row still receives real HR reconciliation")
        XCTAssertEqual(fullReads, 300)
        XCTAssertEqual(scopedReads, 1, "Historical workouts must not issue HR queries for a day view")
        print("Workout HR window reads: full-history=\(fullReads), selected-day=\(scopedReads)")
    }

    func testWindowDeduplicatesAgainstTwinStartingOutsideLowerBoundary() async throws {
        let store = try await WhoopStore.inMemory()
        for id in ["my-whoop", "apple-health"] {
            try await store.upsertDevice(id: id, mac: nil, name: id)
        }
        let boundary = Int(Date().timeIntervalSince1970) - 7200
        let winner = workout(start: boundary - 30, rich: true)
        let twin = workout(start: boundary + 30, source: "apple-health")
        _ = try await store.upsertWorkouts([winner], deviceId: "my-whoop")
        _ = try await store.upsertWorkouts([twin], deviceId: "apple-health")
        let repo = repository(store)
        let full = await repo.workoutRows()
        let scoped = await repo.workoutRows(from: boundary, to: boundary + 7200)
        XCTAssertEqual(full.count, 1)
        XCTAssertEqual(full.first?.startTs, winner.startTs)
        XCTAssertTrue(scoped.isEmpty, "Do not resurrect an in-window twin whose winner starts outside")
    }

    func testWindowExcludesStartAtUpperBoundaryAndKeepsStartAtLowerBoundary() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "Strap")
        let start = Int(Date().timeIntervalSince1970) - 10_000
        _ = try await store.upsertWorkouts([workout(start: start), workout(start: start + 7200)],
                                           deviceId: "my-whoop")
        let repo = repository(store)
        let scoped = await repo.workoutRows(from: start, to: start + 7200)
        XCTAssertEqual(scoped.map(\.startTs), [start])
        let empty = await repo.workoutRows(from: start, to: start)
        XCTAssertTrue(empty.isEmpty)
    }

    func testHRUnionPreservesFirstSourceAndAscendingTimestamps() async throws {
        let store = try await WhoopStore.inMemory()
        for id in ["my-whoop", "secondary"] {
            try await store.upsertDevice(id: id, mac: nil, name: id)
        }
        try await store.insert(Streams(hr: [HRSample(ts: 102, bpm: 72), HRSample(ts: 100, bpm: 70)]),
                               deviceId: "my-whoop")
        try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 99), HRSample(ts: 101, bpm: 71)]),
                               deviceId: "secondary")
        let repo = repository(store)
        let merged = await repo.hrSamples(deviceIds: ["my-whoop", "secondary"], from: 100, to: 102)
        XCTAssertEqual(merged.map(\.ts), [100, 101, 102])
        XCTAssertEqual(merged.map(\.bpm), [70, 71, 72])
        let reversed = await repo.hrSamples(deviceIds: ["secondary", "my-whoop"], from: 100, to: 102)
        XCTAssertEqual(reversed.map(\.bpm), [99, 71, 72])
    }
}
