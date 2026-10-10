import XCTest
@testable import Strand

final class LocalMetricReportArchiveTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testKeepsOriginalPayloadAndDeduplicatesRepeatedDelivery() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = LocalMetricReportArchive(directory: folder)
        let data = Data("{\"includesMultipleApplicationVersions\":true,\"latestApplicationVersion\":\"11.8.0\"}".utf8)
        try archive.save(data, kind: .metrics, windowEnd: Date(timeIntervalSince1970: 100))
        try archive.save(data, kind: .metrics, windowEnd: Date(timeIntervalSince1970: 100))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), data)
    }

    func testDelayedOlderReportCannotEvictNewerWindows() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = LocalMetricReportArchive(directory: folder, maxReports: 2)
        for end in [20, 30, 10] {
            try archive.save(Data("{\"window\":\(end)}".utf8), kind: .metrics,
                             windowEnd: Date(timeIntervalSince1970: Double(end)))
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { !$0.lastPathComponent.hasPrefix("metrics-10000-") })
    }

    func testByteBudgetAndKindsPreserveUnrelatedFiles() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = LocalMetricReportArchive(directory: folder, maxBytes: 20)
        let unrelated = folder.appendingPathComponent("notes.json")
        try Data("preserve".utf8).write(to: unrelated)
        let data = Data("{\"value\":1}".utf8)
        try archive.save(data, kind: .metrics, windowEnd: Date(timeIntervalSince1970: 10))
        try archive.save(data, kind: .diagnostics, windowEnd: Date(timeIntervalSince1970: 20))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("preserve".utf8))
        XCTAssertTrue(files.contains { $0.lastPathComponent.hasPrefix("diagnostics-") })
        XCTAssertThrowsError(try archive.save(Data(repeating: 0, count: 21), kind: .metrics, windowEnd: Date()))
    }
}
