import XCTest
@testable import Strand

/// The Apple Intelligence brief: written once a day and again only after new data, stored as metric ids and
/// sentences (never values), and rendered with the app's own values.
final class AppleCoachBriefTests: XCTestCase {

    private let brief = AppleCoachBrief(day: "2026-09-30", dataKey: "2026-09-30|64%|81%",
                                        headline: "A steady day to build on",
                                        points: [.init(metric: "charge", sentence: "You're recovered enough for a solid session."),
                                                 .init(metric: "sleepDebt", sentence: "An earlier night keeps debt down.")],
                                        offDevice: false, factsOnly: false)

    func testGeneratesOncePerDayAndAgainOnlyAfterNewData() {
        XCTAssertTrue(AppleCoachBriefPolicy.shouldGenerate(stored: nil, today: "2026-09-30", dataKey: "k"))
        XCTAssertFalse(AppleCoachBriefPolicy.shouldGenerate(stored: brief, today: "2026-09-30", dataKey: brief.dataKey))
        XCTAssertTrue(AppleCoachBriefPolicy.shouldGenerate(stored: brief, today: "2026-09-30", dataKey: "2026-09-30|66%|81%"))
        XCTAssertTrue(AppleCoachBriefPolicy.shouldGenerate(stored: brief, today: "2026-10-01", dataKey: brief.dataKey))
    }

    /// The text for the notification and widget takes its values from the app, not from the stored brief.
    func testPlainTextUsesTheAppsValues() {
        let text = brief.plainText { $0 == .charge ? "64%" : ($0 == .sleepDebt ? "1 h 5 min" : nil) }
        XCTAssertEqual(text, """
        A steady day to build on
        • Charge 64%: You're recovered enough for a solid session.
        • Sleep debt 1 h 5 min: An earlier night keeps debt down.
        """)
    }

    func testFactsOnlyBriefHasNoProse() {
        let b = AppleCoachBriefPolicy.factsOnly(day: "2026-09-30", dataKey: "k", metrics: [.charge, .rest], offDevice: true)
        XCTAssertTrue(b.factsOnly)
        XCTAssertTrue(b.points.allSatisfy { $0.sentence.isEmpty })
        XCTAssertEqual(b.plainText { _ in "1" }, "Today's numbers\n• Charge 1\n• Rest 1")
    }

    func testStoresAndLoads() {
        let suite = "noop.test.appleBrief"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        brief.save(d)
        XCTAssertEqual(AppleCoachBrief.load(d), brief)
        d.removePersistentDomain(forName: suite)
    }

    /// The wake brief goes out for a night that just ended this morning, not for an afternoon sync or a
    /// night-time wake.
    func testWakeBriefOnlyForAFreshMorningWake() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: h, minute: m))! }
        XCTAssertTrue(CoachBriefScheduler.isFreshWake(nightEnd: at(7), now: at(7, 20), calendar: cal))
        XCTAssertTrue(CoachBriefScheduler.isFreshWake(nightEnd: at(7), now: at(10), calendar: cal))
        XCTAssertFalse(CoachBriefScheduler.isFreshWake(nightEnd: at(7), now: at(10, 1), calendar: cal))  // scored over three hours late
        XCTAssertFalse(CoachBriefScheduler.isFreshWake(nightEnd: at(3, 30), now: at(3, 45), calendar: cal)) // night-time wake
        XCTAssertFalse(CoachBriefScheduler.isFreshWake(nightEnd: at(7), now: at(6, 59), calendar: cal))  // clock skew
        XCTAssertFalse(CoachBriefScheduler.isFreshWake(nightEnd: at(7).addingTimeInterval(-86_400), now: at(7, 10), calendar: cal))
    }
}
