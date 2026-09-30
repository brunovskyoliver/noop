import XCTest
@testable import Strand

final class JetLagTripTests: XCTestCase {
    private func trip(_ date: String, destination: Int, bed: Int = 23 * 60) -> JetLagTrip {
        JetLagTrip(travelDate: ISO8601DateFormatter().date(from: date)!, originTimeZone: "Europe/Copenhagen",
                   destinationOffsetMinutes: destination, bedMinute: bed, wakeMinute: 7 * 60)
    }

    func testOriginOffsetUsesTravelDateDaylightSaving() throws {
        let winter = try XCTUnwrap(trip("2026-01-10T12:00:00Z", destination: 240).resolve())
        let summer = try XCTUnwrap(trip("2026-07-10T12:00:00Z", destination: 240).resolve())
        XCTAssertEqual(winter.days.count, 3)
        XCTAssertEqual(summer.days.count, 2)
        XCTAssertEqual(winter.days.last?.timing.targetWakeHour, 4)
        XCTAssertEqual(summer.days.last?.timing.targetWakeHour, 5)
    }

    func testDatesAreBeforeTravelAndDelayWrapsAfterMidnight() throws {
        let input = trip("2026-01-10T12:00:00Z", destination: -120)
        let plan = try XCTUnwrap(input.resolve())
        XCTAssertEqual(plan.direction, .delay)
        XCTAssertEqual(plan.days.first?.timing.targetSleepHour, 0)
        XCTAssertEqual(plan.days.last?.timing.targetSleepHour, 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.originTimeZone)!
        XCTAssertEqual(plan.days.map { calendar.component(.day, from: $0.date) }, [7, 8, 9])
        XCTAssertEqual(plan.days.map(\.id), [1, 2, 3])
    }

    func testInvalidAndDateLineInputsHaveNoPlan() {
        XCTAssertNil(trip("2026-07-10T12:00:00Z", destination: -720).resolve())
        XCTAssertNil(trip("2026-07-10T12:00:00Z", destination: 900).resolve())
        XCTAssertNil(trip("2026-07-10T12:00:00Z", destination: 0, bed: -1).resolve())
    }

    func testSavedTripRoundTripKeepsItsTiming() throws {
        let input = trip("2026-07-10T12:00:00Z", destination: 330)
        let copy = try JSONDecoder().decode(JetLagTrip.self, from: JSONEncoder().encode(input))
        XCTAssertEqual(copy, input)
        XCTAssertEqual(copy.resolve()?.days.count, 4)
    }
}
