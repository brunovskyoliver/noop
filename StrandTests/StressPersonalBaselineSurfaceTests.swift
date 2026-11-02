import XCTest
@testable import Strand

/// #2430: the personal daytime-stress lens reaches Stress detail and both Apple Today layouts.
///
/// The baseline math has package tests; this pins the app-target wiring that can otherwise compile
/// while silently omitting the preference at one call site.
final class StressPersonalBaselineSurfaceTests: XCTestCase {
    private func source(_ path: String, file: StaticString = #filePath) throws -> String {
        let testFile = URL(fileURLWithPath: "\(file)")
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testDetailAndTodayUseTheSameSelectedMode() throws {
        let detail = try source("Strand/Screens/StressView.swift")
        let producer = try source("Strand/Data/StressDayCurve.swift")
        let today = try source("Strand/Screens/TodayView.swift")
        let liquidToday = try source("Strand/Liquid/LiquidTodayView.swift")

        XCTAssertNotNil(detail.range(
            of: #"DaytimeStressMode\.selected\([\s\S]*?personalBaseline:\s*PuffinExperiment\.stressPersonalBaselineEnabled"#,
            options: .regularExpression
        ))
        XCTAssertNotNil(detail.range(
            of: #"DaytimeStress\.analyze\([\s\S]*?mode:\s*mode,"#,
            options: .regularExpression
        ))
        // One curve: the producer maps the analysis every other surface reads, and scores nothing itself.
        XCTAssertTrue(producer.contains("repo.stressToday(now: now)"))
        XCTAssertTrue(producer.contains("StressMonitor.curve("))
        XCTAssertFalse(producer.contains("DaytimeStress.analyze("))
        for body in [today, liquidToday] {
            XCTAssertTrue(body.contains("StressDayCurve.today(repo: repo)"))
        }
    }

    func testWidgetPublisherUsesTheOneCurve() throws {
        let widget = try source("StrandiOS/Widgets/WidgetPublish.swift")
        XCTAssertTrue(widget.contains("StressDayCurve.today(repo: model.repo)"))
    }
}
