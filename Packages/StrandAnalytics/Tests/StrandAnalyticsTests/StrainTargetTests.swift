import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class StrainTargetTests: XCTestCase {
    typealias ST = StrainTarget
    let to21 = 21.0 / 100.0

    func band21(_ i: ST.Inputs) -> (Double, Double) {
        let b = ST.band(i)!
        return (b.lower * to21, b.upper * to21)
    }

    func testBandsAreMonotoneInChargeAndReproduceTheOldBandsAtTheirMidpoints() {
        var prev: (Double, Double)?
        for c in stride(from: 0.0, through: 100, by: 1) {
            let b = band21(.init(charge: c))
            XCTAssertLessThan(b.0, b.1)
            if let prev { XCTAssertGreaterThan(b.0, prev.0); XCTAssertGreaterThan(b.1, prev.1) }
            prev = b
        }
        // Old: red 4–10, yellow 10–14, green 14–18.
        for (c, lo, hi) in [(17.0, 4.0, 10.0), (50.0, 10.0, 14.0), (83.0, 14.0, 18.0)] {
            let b = band21(.init(charge: c))
            XCTAssertEqual(b.0, lo, accuracy: 0.8); XCTAssertEqual(b.1, hi, accuracy: 0.05)
        }
    }

    func testUnknownChargeHasNoTarget() {
        XCTAssertNil(ST.band(.init(charge: nil)))
        XCTAssertNil(ST.band(.init(charge: .nan, sleepDebtMin: 300, illness: true)))
    }

    func testDebtIllnessAndGoalShiftTheBand() {
        let base = band21(.init(charge: 70))
        // 60 min of debt is free; 3 h → −1.0; 10 h caps at −2.0.
        XCTAssertEqual(band21(.init(charge: 70, sleepDebtMin: 60)).0, base.0, accuracy: 1e-9)
        XCTAssertEqual(band21(.init(charge: 70, sleepDebtMin: 180)).0, base.0 - 1, accuracy: 1e-9)
        XCTAssertEqual(band21(.init(charge: 70, sleepDebtMin: 600)).1, base.1 - 2, accuracy: 1e-9)
        // Illness caps at the old red band.
        let ill = band21(.init(charge: 95, illness: true))
        XCTAssertEqual(ill.0, 4, accuracy: 1e-9); XCTAssertEqual(ill.1, 10, accuracy: 1e-9)
        XCTAssertEqual(band21(.init(charge: 70, goal: .restore)).0, base.0 - 3, accuracy: 1e-9)
        XCTAssertEqual(band21(.init(charge: 70, goal: .build)).1, base.1 + 2, accuracy: 1e-9)
        // Clamped to the axis with a minimum width, and the lower bound kept above 0 so an idle day is
        // never "in target".
        let floor = band21(.init(charge: 0, sleepDebtMin: 900, illness: true, goal: .restore))
        XCTAssertEqual(floor.0, ST.minLower21, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(floor.1, ST.minLower21 + ST.minWidth21 - 1e-9)
        for c in stride(from: 0.0, through: 100, by: 1) {
            for goal in ST.Goal.allCases {
                let b = ST.band(.init(charge: c, sleepDebtMin: 900, illness: true, goal: goal))!
                XCTAssertEqual(b.zone(effort: 0), .restoring, "charge \(c) goal \(goal)")
            }
        }
        let top = band21(.init(charge: 100, goal: .build))
        XCTAssertLessThanOrEqual(top.1, 21 + 1e-9)
    }

    func testZoneAtTheEdges() {
        let b = ST.Band(lower: 40, upper: 60)
        XCTAssertEqual(b.zone(effort: 39.99), .restoring)
        XCTAssertEqual(b.zone(effort: 40), .optimal)
        XCTAssertEqual(b.zone(effort: 60), .optimal)
        XCTAssertEqual(b.zone(effort: 60.01), .overreaching)
    }

    func testMinutesToTargetRecoversKnownValuesAcrossHeartRates() {
        // RHR 60, HRmax 190 → HRR 130. Zone cut-offs at 50/60/70/80/90 %HRR.
        let rest = 60.0, max = 190.0
        for (bpm, weight) in [(120.0, 0.0), (126.0, 1.0), (140.0, 2.0), (155.0, 3.0), (166.0, 4.0), (180.0, 5.0)] {
            XCTAssertEqual(ST.edwardsTrimpPerMinute(bpm: bpm, restingHR: rest, maxHR: max), weight, "bpm \(bpm)")
        }
        // Scoring a synthetic session and asking the inverse must give the session's length back.
        for (bpm, minutes) in [(126.0, 90.0), (140.0, 45.0), (166.0, 20.0), (180.0, 12.0)] {
            let start = 1_700_000_000
            let before = (0..<3600).map { HRSample(ts: start + $0, bpm: Int(bpm)) }   // an hour already done
            let after = before + (0..<Int(minutes * 60)).map { HRSample(ts: start + 3600 + $0, bpm: Int(bpm)) }
            let e0 = StrainScorer.strain(before, maxHR: max, restingHR: rest)!
            let e1 = StrainScorer.strain(after, maxHR: max, restingHR: rest)!
            let rate = ST.edwardsTrimpPerMinute(bpm: bpm, restingHR: rest, maxHR: max)
            // Stored Effort is rounded to 2 dp, so allow the rounding's share of a minute.
            XCTAssertEqual(ST.minutesToReach(targetEffort: e1, currentEffort: e0, trimpPerMinute: rate)!,
                           minutes, accuracy: 0.6, "bpm \(bpm)")
        }
        XCTAssertEqual(ST.minutesToReach(targetEffort: 30, currentEffort: 40, trimpPerMinute: 3), 0)
        XCTAssertNil(ST.minutesToReach(targetEffort: 50, currentEffort: 40, trimpPerMinute: 0))
    }

    func testEffortMaxHRFunnel() {
        XCTAssertEqual(StrainScorer.effortMaxHR(override: 200, age: 30), 200)
        XCTAssertEqual(StrainScorer.effortMaxHR(override: nil, age: 30)!, 187, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.effortMaxHR(override: 0, age: 30)!, 187, accuracy: 1e-9)
        XCTAssertNil(StrainScorer.effortMaxHR(override: nil, age: 0))
    }
}
