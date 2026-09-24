import XCTest
@testable import StrandAnalytics

final class HRVStatusTests: XCTestCase {

    private let asOf = "2026-09-24"

    /// 67 days ending on asOf: 60 usual-range days alternating 45/55 ms, then 7 days at `recent` ms.
    private func series(recent: Double?, recentNights: Int = 7, usualNights: Int = 60) -> [HRVStatus.Night] {
        let end = VitalityEngine.epochDay(asOf)!
        var out: [HRVStatus.Night] = []
        for i in 0..<67 {
            let day = HRVStatus.dayString(end - 66 + i)
            if i < 60 {
                out.append(.init(day: day, rmssd: i >= 60 - usualNights ? (i % 2 == 0 ? 45 : 55) : nil))
            } else {
                out.append(.init(day: day, rmssd: 66 - i < recentNights ? recent : nil))   // the LAST n days
            }
        }
        return out
    }

    private func band(_ o: HRVStatus.Outcome) -> HRVStatus.Band? {
        if case .status(let r) = o { return r.band }
        return nil
    }

    func testDayStringInvertsEpochDay() {
        for s in ["1970-01-01", "2000-02-29", "2026-09-24", "2100-12-31"] {
            XCTAssertEqual(HRVStatus.dayString(VitalityEngine.epochDay(s)!), s)
        }
    }

    /// Tracks a varying input: several step sizes land in the matching band.
    func testStepChangesLandInTheirBands() {
        // Usual: ln 45 / ln 55 alternating → μ ≈ ln 49.75, σ ≈ 0.1011.
        XCTAssertEqual(band(HRVStatus.evaluate(nights: series(recent: 50), asOf: asOf)), .balanced)
        XCTAssertEqual(band(HRVStatus.evaluate(nights: series(recent: 55), asOf: asOf)), .above)
        XCTAssertEqual(band(HRVStatus.evaluate(nights: series(recent: 46), asOf: asOf)), .below)
        XCTAssertEqual(band(HRVStatus.evaluate(nights: series(recent: 42), asOf: asOf)), .low)
        XCTAssertEqual(band(HRVStatus.evaluate(nights: series(recent: 30), asOf: asOf)), .low)
    }

    func testCalibratingUntilTwentyOneUsualNights() {
        XCTAssertEqual(HRVStatus.evaluate(nights: series(recent: 50, usualNights: 20), asOf: asOf),
                       .calibrating(baselineNights: 20))
        XCTAssertNotNil(band(HRVStatus.evaluate(nights: series(recent: 50, usualNights: 21), asOf: asOf)))
    }

    func testNeedsThreeRecentNightsAndFreshData() {
        XCTAssertEqual(HRVStatus.evaluate(nights: series(recent: 50, recentNights: 2), asOf: asOf), .noRecentData)
        guard case .status(let r) = HRVStatus.evaluate(nights: series(recent: 50, recentNights: 3), asOf: asOf)
        else { return XCTFail("expected a status") }
        XCTAssertTrue(r.tentative)
        // Four days on, the newest recent night is 4 days old → stale.
        let later = HRVStatus.dayString(VitalityEngine.epochDay(asOf)! + 4)
        XCTAssertEqual(HRVStatus.evaluate(nights: series(recent: 50, recentNights: 3), asOf: later), .noRecentData)
    }

    /// A sustained drop does not pull its own baseline down: the short window is not in the usual range.
    func testShortWindowExcludedFromUsualRange() {
        guard case .status(let r) = HRVStatus.evaluate(nights: series(recent: 30), asOf: asOf)
        else { return XCTFail("expected a status") }
        XCTAssertEqual(r.baselineNights, 60)
        XCTAssertGreaterThan(r.usualLowMs, 45)
    }

    func testFlaggedDaysLeaveTheUsualRangeAndMarkTheReading() {
        let nights = series(recent: 50)
        let end = VitalityEngine.epochDay(asOf)!
        let flaggedOld = Set((10..<50).map { HRVStatus.dayString(end - 66 + $0) })   // 40 usual days
        XCTAssertEqual(HRVStatus.evaluate(nights: nights, asOf: asOf, flaggedDays: flaggedOld),
                       .calibrating(baselineNights: 20))
        guard case .status(let r) = HRVStatus.evaluate(nights: nights, asOf: asOf, flaggedDays: [asOf])
        else { return XCTFail("expected a status") }
        XCTAssertTrue(r.mayReflectFlaggedDays)
    }

    func testHistoryIsOldestFirst() {
        let h = HRVStatus.history(nights: series(recent: 50), asOf: asOf, days: 5)
        XCTAssertEqual(h.map(\.day).last, asOf)
        XCTAssertEqual(h.count, 5)
    }

    /// Pinned for the Kotlin twin (`HRVStatusTest.oracle`): values printed by this implementation.
    func testOracle() {
        let end = VitalityEngine.epochDay(asOf)!
        var nights: [HRVStatus.Night] = []
        for i in 0..<70 {
            let v: Double? = i % 9 == 4 ? nil : 38 + Double((i * 7) % 23) + (i >= 63 ? -6 : 0)
            nights.append(.init(day: HRVStatus.dayString(end - 69 + i), rmssd: i == 20 ? 400 : v))
        }
        guard case .status(let r) = HRVStatus.evaluate(nights: nights, asOf: asOf) else { return XCTFail() }
        XCTAssertEqual(r.band, .low)
        XCTAssertEqual(r.mean7Ms, 39.911849096666415)
        XCTAssertEqual(r.usualLowMs, 45.53189199366618)
        XCTAssertEqual(r.usualHighMs, 52.226802964407376)
        XCTAssertEqual(r.lowMs, 42.513496495352065)
        XCTAssertEqual(r.shortNights, 6)
        XCTAssertEqual(r.baselineNights, 52)
    }
}
