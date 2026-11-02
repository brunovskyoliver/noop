import XCTest
@testable import Strand

/// #2430: the personal daytime-stress lens reaches the stress curve the widget publishes.
///
/// The baseline math has package tests; this pins the app-target wiring that can otherwise compile
/// while silently omitting the preference at one call site.
final class StressPersonalBaselineSurfaceTests: XCTestCase {
    private func source(_ path: String, file: StaticString = #filePath) throws -> String {
        let testFile = URL(fileURLWithPath: "\(file)")
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testProducerMapsTheOneAnalysis() throws {
        let producer = try source("Strand/Data/StressDayCurve.swift")
        XCTAssertTrue(producer.contains("repo.stressToday(now: now)"))
        XCTAssertTrue(producer.contains("StressMonitor.curve("))
        XCTAssertFalse(producer.contains("DaytimeStress.analyze("))
    }

    func testWidgetPublisherUsesTheOneCurve() throws {
        let widget = try source("StrandiOS/Widgets/WidgetPublish.swift")
        XCTAssertTrue(widget.contains("StressDayCurve.today(repo: model.repo)"))
    }
}
