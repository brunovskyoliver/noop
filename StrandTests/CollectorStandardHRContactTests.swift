import XCTest
import WhoopProtocol
import WhoopStore
@testable import Strand

@MainActor
final class CollectorStandardHRContactTests: XCTestCase {
    private final class CaptureStore: StoreWriting {
        enum Failure: Error { case requested }

        var inserted: [Streams] = []
        var failNextInsert = false
        var pauseNextInsert = false
        var resumeInsert: CheckedContinuation<Void, Never>?

        func insert(_ streams: Streams, deviceId: String) async throws
            -> (hr: Int, rr: Int, events: Int, battery: Int,
                spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
            if pauseNextInsert {
                pauseNextInsert = false
                await withCheckedContinuation { resumeInsert = $0 }
            }
            if failNextInsert {
                failNextInsert = false
                throw Failure.requested
            }
            inserted.append(streams)
            return (streams.hr.count, streams.rr.count, streams.events.count,
                    streams.battery.count, streams.spo2.count, streams.skinTemp.count,
                    streams.resp.count, streams.gravity.count)
        }

        func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {}
    }

    /// Repinned for change-only contact recording: only TRANSITIONS record, so thirty identical
    /// readings now produce one event rather than thirty. The invariant is unchanged — contact events
    /// alone can drive the auto-flush threshold, without a single HR or R-R row — but it has to be
    /// measured with readings that actually change, which is what a strap going on and off produces.
    func testContactOnlyBatchAutoFlushesAtThreshold() async {
        let store = CaptureStore()
        let collector = Collector(store: store, deviceId: "whoop-5")

        var contact = StandardHRContact.supportedNotDetected
        for ts in 1_750_000_000..<1_750_000_030 {
            collector.ingestStandardHR(hr: 0, rr: [], contact: contact, at: ts)
            contact = contact == .supportedNotDetected ? .supportedDetected : .supportedNotDetected
        }
        for _ in 0..<10 where store.inserted.isEmpty { await Task.yield() }

        XCTAssertEqual(store.inserted.count, 1)
        guard let inserted = store.inserted.first else { return }
        XCTAssertTrue(inserted.hr.isEmpty)
        XCTAssertTrue(inserted.rr.isEmpty)
        XCTAssertEqual(inserted.events.count, 30)
    }

    /// The other half of the same rule, and the one that made the repin necessary: a run of identical
    /// readings records ONCE. At the ~1 Hz the standard profile actually arrives at, the old
    /// per-reading write was ~86,400 rows a day per device saying the same thing.
    func testARunOfIdenticalReadingsRecordsOnlyTheFirst() async {
        let store = CaptureStore()
        let collector = Collector(store: store, deviceId: "whoop-5")

        for ts in 1_750_000_000..<1_750_000_030 {
            collector.ingestStandardHR(hr: 0, rr: [], contact: .supportedNotDetected, at: ts)
        }
        // One event never reaches the 30-item auto-flush threshold, so nothing has been written yet.
        XCTAssertTrue(store.inserted.isEmpty)

        await collector.flushStandardHR()
        XCTAssertEqual(store.inserted.count, 1)
        XCTAssertEqual(store.inserted.first?.events.count, 1)
        XCTAssertEqual(store.inserted.first?.events.first?.ts, 1_750_000_000)
    }

    func testWhoopStandardHRCollectorPersistsParsedContact() async {
        let store = CaptureStore()
        let collector = Collector(store: store, deviceId: "whoop-5")

        collector.ingestStandardHR(
            hr: 72, rr: [1_000], contact: .supportedNotDetected, at: 1_750_000_000
        )
        await collector.flushStandardHR()

        XCTAssertEqual(store.inserted, [
            StandardHRMapping.samples(
                fromHR: 72,
                rr: [1_000],
                contact: .supportedNotDetected,
                at: 1_750_000_000
            )
        ])
    }

    func testWhoopStandardHRCollectorRebuffersContactAfterInsertFailure() async {
        let store = CaptureStore()
        store.failNextInsert = true
        let collector = Collector(store: store, deviceId: "whoop-5")

        collector.ingestStandardHR(
            hr: 73, rr: [], contact: .supportedDetected, at: 1_750_000_001
        )
        await collector.flushStandardHR()
        XCTAssertTrue(store.inserted.isEmpty)

        await collector.flushStandardHR()
        XCTAssertEqual(store.inserted.first?.events, [
            WhoopEvent(
                ts: 1_750_000_001,
                kind: StandardHRMapping.contactEventKind,
                payload: ["contact": .string("supported_detected")]
            )
        ])
    }

    func testRrFamilyIsCapturedAtIngressAndSurvivesRetry() async {
        let store = CaptureStore()
        let collector = Collector(store: store, deviceId: "strap")
        collector.ingestStandardHR(hr: 60, rr: [1000], family: .whoop5, at: 100)
        collector.ingestStandardHR(hr: 60, rr: [1001], family: .whoop4, at: 101)
        collector.ingestStandardHR(hr: 60, rr: [1002], at: 102)
        store.failNextInsert = true
        await collector.flushStandardHR()
        XCTAssertTrue(store.inserted.isEmpty)
        await collector.flushStandardHR()
        XCTAssertEqual(store.inserted.flatMap(\.rr).map(\.srcChannel), [.whoop5Standard, nil, nil])
        XCTAssertEqual(store.inserted.flatMap(\.rr).map(\.rrMs), [1000, 1001, 1002])
    }

    func testDenseRrDoesNotShortenTheThirtyReadingBatch() async {
        let store = CaptureStore()
        var clock: TimeInterval = 0
        let collector = Collector(store: store, deviceId: "strap", monotonic: { clock })
        for offset in 0..<15 {
            clock = Double(offset)
            collector.ingestStandardHR(hr: 60, rr: [800, 900, 1000], family: .whoop5, at: offset)
            await Task.yield()
        }
        XCTAssertTrue(store.inserted.isEmpty, "R-R rows must not turn fifteen readings into a full batch")
        for offset in 15..<30 {
            clock = Double(offset)
            collector.ingestStandardHR(hr: 60, rr: [800, 900, 1000], family: .whoop5, at: offset)
        }
        for _ in 0..<100 where store.inserted.isEmpty { await Task.yield() }
        XCTAssertEqual(store.inserted.count, 1)
        XCTAssertEqual(store.inserted.flatMap(\.hr).count, 30)
        XCTAssertEqual(store.inserted.flatMap(\.rr).count, 90)
        XCTAssertTrue(store.inserted.flatMap(\.rr).allSatisfy { $0.srcChannel == .whoop5Standard })
    }

    func testSparseReadingsFlushAtElapsedBound() async {
        let store = CaptureStore()
        var clock: TimeInterval = 0
        let collector = Collector(store: store, deviceId: "strap", monotonic: { clock })
        collector.ingestStandardHR(hr: 60, rr: [1000], at: 100)
        clock = 29
        collector.ingestStandardHR(hr: 61, rr: [999], at: 129)
        await Task.yield()
        XCTAssertTrue(store.inserted.isEmpty)
        clock = 30
        collector.ingestStandardHR(hr: 62, rr: [998], at: 130)
        for _ in 0..<100 where store.inserted.isEmpty { await Task.yield() }
        XCTAssertEqual(store.inserted.flatMap(\.hr).map(\.bpm), [60, 61, 62])
        XCTAssertEqual(store.inserted.flatMap(\.rr).map(\.rrMs), [1000, 999, 998])
    }

    func testFailedWriteRetainsAgeAndReadingsForAutomaticRetry() async {
        let store = CaptureStore()
        store.failNextInsert = true
        var clock: TimeInterval = 0
        let collector = Collector(store: store, deviceId: "strap", monotonic: { clock })
        collector.ingestStandardHR(hr: 60, rr: [1000], family: .whoop5, at: 100)
        await collector.flushStandardHR()
        XCTAssertTrue(store.inserted.isEmpty)
        clock = 30
        collector.ingestStandardHR(hr: 61, rr: [999], family: .whoop5, at: 130)
        for _ in 0..<100 where store.inserted.isEmpty { await Task.yield() }
        XCTAssertEqual(store.inserted.flatMap(\.hr).map(\.bpm), [60, 61])
        XCTAssertEqual(store.inserted.flatMap(\.rr).map(\.rrMs), [1000, 999])
        XCTAssertTrue(store.inserted.flatMap(\.rr).allSatisfy { $0.srcChannel == .whoop5Standard })
    }

    func testRowCapFlushesDenseBatchBeforeThirtyReadings() async {
        let store = CaptureStore()
        let collector = Collector(store: store, deviceId: "strap", monotonic: { 0 })
        collector.ingestStandardHR(hr: 60, rr: Array(repeating: 1000, count: 256), at: 100)
        for _ in 0..<100 where store.inserted.isEmpty { await Task.yield() }
        XCTAssertEqual(store.inserted.flatMap(\.hr).count, 1)
        XCTAssertEqual(store.inserted.flatMap(\.rr).count, 256)
    }

    func testReadingsArrivingDuringFailedWriteKeepOrderAndOriginalDeadline() async {
        let store = CaptureStore()
        store.pauseNextInsert = true
        store.failNextInsert = true
        var clock: TimeInterval = 0
        let collector = Collector(store: store, deviceId: "strap", monotonic: { clock })
        collector.ingestStandardHR(hr: 60, rr: [1000], family: .whoop5, at: 100)
        let flush = Task { await collector.flushStandardHR() }
        for _ in 0..<100 where store.resumeInsert == nil { await Task.yield() }
        guard let resume = store.resumeInsert else { XCTFail("Insert must reach the suspension point"); return }
        clock = 5
        collector.ingestStandardHR(hr: 61, rr: [999], family: .whoop4, at: 105)
        resume.resume()
        await flush.value
        XCTAssertTrue(store.inserted.isEmpty)
        clock = 30
        collector.ingestStandardHR(hr: 62, rr: [998], family: .whoop5, at: 130)
        for _ in 0..<100 where store.inserted.isEmpty { await Task.yield() }
        XCTAssertEqual(store.inserted.flatMap(\.hr).map(\.ts), [100, 105, 130])
        XCTAssertEqual(store.inserted.flatMap(\.rr).map(\.srcChannel), [.whoop5Standard, nil, .whoop5Standard])
    }
}
