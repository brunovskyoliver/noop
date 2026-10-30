import XCTest

final class BroopActivityReadingsTests: XCTestCase {
    func testAppleHealthValuesRemainVisibleWithWhoopOnlyHistory() {
        let result = BroopActivityReadings.resolve(day: "2026-10-19",
            native: [.init(day: "2026-10-18"), .init(day: "2026-10-19")],
            apple: [.init(day: "2026-10-19", steps: 5005, activeKcal: 1628)], estimates: [])
        XCTAssertEqual(result.steps?.value, 5005)
        XCTAssertEqual(result.activeKcal?.value, 1628)
        XCTAssertEqual(result.steps?.history, [])
        XCTAssertEqual(result.activeKcal?.history, [])
    }

    func testAppleHealthHistorySuppliesBothComparisons() {
        let result = BroopActivityReadings.resolve(day: "2026-10-19", native: [],
            apple: [.init(day: "2026-10-17", steps: 1000, activeKcal: 300),
                    .init(day: "2026-10-18", steps: 2000, activeKcal: 500),
                    .init(day: "2026-10-19", steps: 5005, activeKcal: 1628)], estimates: [])
        XCTAssertEqual(result.steps?.history, [1000, 2000])
        XCTAssertEqual(result.activeKcal?.history, [300, 500])
    }

    func testSourcePriorityMatchesForTodayAndHistoryWithoutSummingDuplicates() {
        let result = BroopActivityReadings.resolve(day: "2026-10-19",
            native: [.init(day: "2026-10-18", steps: 100, activeKcal: 900),
                     .init(day: "2026-10-19", steps: 200, activeKcal: 1000)],
            apple: [.init(day: "2026-10-18", steps: 400, activeKcal: 300),
                    .init(day: "2026-10-18", steps: 500, activeKcal: 250),
                    .init(day: "2026-10-19", steps: 600, activeKcal: 450)],
            estimates: [("2026-10-18", 700), ("2026-10-19", 800)])
        XCTAssertEqual(result.steps?.value, 200)
        XCTAssertEqual(result.steps?.history, [100])
        XCTAssertEqual(result.activeKcal?.value, 450)
        XCTAssertEqual(result.activeKcal?.history, [300])
    }

    func testMissingCurrentValuesDoNotBorrowAnotherDay() {
        let result = BroopActivityReadings.resolve(day: "2026-10-19", native: [],
            apple: [.init(day: "2026-10-18", steps: 100, activeKcal: 200)],
            estimates: [("2026-10-18", 300), ("2026-10-20", 400)])
        XCTAssertNil(result.steps)
        XCTAssertNil(result.activeKcal)
    }

    func testZeroIsAReadingAndCurrentOrFutureDaysCannotEnterBaseline() {
        let result = BroopActivityReadings.resolve(day: "2026-10-19", native: [],
            apple: [.init(day: "2026-10-18", steps: 100, activeKcal: 200),
                    .init(day: "2026-10-19", steps: 0, activeKcal: 0),
                    .init(day: "2026-10-20", steps: 9000, activeKcal: 900)], estimates: [])
        XCTAssertEqual(result.steps?.value, 0)
        XCTAssertEqual(result.activeKcal?.value, 0)
        XCTAssertEqual(result.steps?.history, [100])
        XCTAssertEqual(result.activeKcal?.history, [200])
    }

    func testEstimatesFillMissingStepsAndHistoryIsBounded() {
        let estimates = (1...31).map { (day: String(format: "2026-10-%02d", $0), value: Double($0)) }
            + [(day: "2026-11-01", value: 50)]
        let result = BroopActivityReadings.resolve(day: "2026-11-01", native: [], apple: [], estimates: estimates)
        XCTAssertEqual(result.steps?.value, 50)
        XCTAssertEqual(result.steps?.history, (2...31).map(Double.init))
        XCTAssertNil(result.activeKcal)
    }
}
