import XCTest
@testable import StrandAnalytics

final class VitalityWindowTests: XCTestCase {

    // MARK: VO₂max reference

    func testExpectedVO2maxFollowsPublishedTable() {
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 20, sex: "male"), 46)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 30, sex: "female"), 38)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 47.5, sex: "male"), 36.5, accuracy: 1e-12)   // halfway 37→36
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 15, sex: "male"), 46)          // flat below 20
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 110, sex: "female"), 18)       // flat above 100
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 30, sex: "nonbinary"), 41)     // mean of 44 and 38
    }

    // MARK: Zone time

    /// Meeting the 150 min/week guideline nets zero; none ages you; the Arem plateau caps the benefit.
    func testZoneTimeCurve() {
        func zones(_ z13: Double, _ z45: Double) -> Double {
            VitalityEngine.contributions(.init(chronoAge: 40, zone13MinPerWeek: z13, zone45MinPerWeek: z45))
                .first { $0.key == "zones" }!.lnHazard
        }
        XCTAssertEqual(zones(150, 0), 0, accuracy: 1e-12)
        XCTAssertEqual(zones(100, 25), 0, accuracy: 1e-12)       // vigorous minutes count double
        XCTAssertEqual(zones(0, 0), 0.2971036163525209, accuracy: 1e-12)
        XCTAssertEqual(zones(600, 0), zones(2000, 0), accuracy: 1e-12)
        XCTAssertLessThan(zones(300, 30), 0)
    }

    func testZoneMinutesFromJSON() {
        let a = VitalityEngine.zoneMinutes(zonesJSON: #"{"z1":10,"z2":20,"z3":30,"z4":30,"z5":10}"#, durationS: 3600)!
        XCTAssertEqual(a.z13, 36, accuracy: 1e-9)
        XCTAssertEqual(a.z45, 24, accuracy: 1e-9)
        let b = VitalityEngine.zoneMinutes(zonesJSON: #"{"zone1":50,"zone4":50}"#, durationS: 1200)!
        XCTAssertEqual(b.z13, 10, accuracy: 1e-9)
        XCTAssertEqual(b.z45, 10, accuracy: 1e-9)
        XCTAssertNil(VitalityEngine.zoneMinutes(zonesJSON: nil, durationS: 600))
        XCTAssertNil(VitalityEngine.zoneMinutes(zonesJSON: #"{"z1":0}"#, durationS: 600))
        XCTAssertNil(VitalityEngine.zoneMinutes(zonesJSON: "not json", durationS: 600))
    }

    // MARK: Overlap domains

    /// The larger of two factors in one domain counts in full, the smaller at half; lone factors stay 1.
    func testDomainWeights() {
        let c = VitalityEngine.contributions(.init(
            chronoAge: 40, restingHR: 75, vo2max: 38, expectedVO2max: 45, sleepHours: 7.5, steps: 9000,
            zone13MinPerWeek: 0, zone45MinPerWeek: 0))
        let w = Dictionary(uniqueKeysWithValues: c.map { ($0.key, $0.weight) })
        XCTAssertEqual(w["vo2max"], 1)      // 0.26 vs RHR 0.10
        XCTAssertEqual(w["rhr"], 0.5)
        XCTAssertEqual(w["zones"], 1)       // 0.297 vs steps 0.128
        XCTAssertEqual(w["steps"], 0.5)
        XCTAssertEqual(w["sleep"], 1)
    }

    // MARK: Windows + Pace of Aging

    func testEpochDay() {
        XCTAssertEqual(VitalityEngine.epochDay("1970-01-01"), 0)
        XCTAssertEqual(VitalityEngine.epochDay("2000-03-01"), 11_017)
        XCTAssertEqual(VitalityEngine.epochDay("2026-09-24"), 20_720)
        XCTAssertNil(VitalityEngine.epochDay("2026-13-01"))
        XCTAssertNil(VitalityEngine.epochDay("garbage"))
    }

    private func days(_ n: Int, endingOn end: String, _ make: (Int) -> VitalityEngine.Day) -> [VitalityEngine.Day] {
        let e = VitalityEngine.epochDay(end)!
        return (0..<n).map { i in
            var d = make(i)
            d.day = Self.dayString(e - (n - 1) + i)
            return d
        }
    }

    static func dayString(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch) * 86_400)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Periodic within 30 days, so the 30-day window's averages equal the 180-day ones.
    private func steady(_ i: Int) -> VitalityEngine.Day {
        .init(day: "", restingHR: 60, sleepHours: i % 2 == 0 ? 7.2 : 7.8, rmssd: 40, steps: 8000,
              vo2max: i % 7 == 0 ? 44 : nil, zone13Min: i % 2 == 0 ? 30 : 0, zone45Min: i % 10 == 0 ? 10 : 0)
    }

    /// Same habits for six months → Pace 1.0 exactly.
    func testSteadyHabitsPaceOne() {
        let h = VitalityEngine.healthspan(days: days(180, endingOn: "2026-09-24", steady),
                                          asOf: "2026-09-24", chronoAge: 35, sex: "male")!
        XCTAssertEqual(h.coveredDays, 180)
        XCTAssertEqual(h.recentCoveredDays, 30)
        XCTAssertEqual(h.paceOfAging!, 1, accuracy: 1e-6)
        XCTAssertEqual(h.bodyAge.factorsUsed, 7)
    }

    /// A worse last month (higher RHR, fewer steps, no training) pushes Pace above 1; a better one below.
    func testRecentChangeMovesPace() {
        let worse = days(180, endingOn: "2026-09-24") { i in
            i < 150 ? self.steady(i) : .init(day: "", restingHR: 68, sleepHours: 6.0, rmssd: 32, steps: 4000)
        }
        let better = days(180, endingOn: "2026-09-24") { i in
            i < 150 ? .init(day: "", restingHR: 68, sleepHours: 6.0, rmssd: 32, steps: 4000) : self.steady(i)
        }
        let w = VitalityEngine.healthspan(days: worse, asOf: "2026-09-24", chronoAge: 35, sex: "male")!
        let b = VitalityEngine.healthspan(days: better, asOf: "2026-09-24", chronoAge: 35, sex: "male")!
        XCTAssertGreaterThan(w.paceOfAging!, 1)
        XCTAssertLessThan(b.paceOfAging!, 1)
        XCTAssertLessThanOrEqual(w.paceOfAging!, VitalityEngine.maxPace)
        XCTAssertGreaterThanOrEqual(b.paceOfAging!, VitalityEngine.minPace)
    }

    /// Too little history → Body Age only, no Pace. Days outside 180 are ignored.
    func testPaceNeedsHistory() {
        let short = VitalityEngine.healthspan(days: days(40, endingOn: "2026-09-24", steady),
                                              asOf: "2026-09-24", chronoAge: 35, sex: "male")!
        XCTAssertNil(short.paceOfAging)
        XCTAssertEqual(short.coveredDays, 40)
        let old = days(40, endingOn: "2026-01-01", steady)
        XCTAssertNil(VitalityEngine.healthspan(days: old, asOf: "2026-09-24", chronoAge: 35, sex: "male"))
    }

    /// A factor missing from the recent window keeps its 6-month value instead of vanishing.
    func testRecentGapKeepsLongValue() {
        let d = days(180, endingOn: "2026-09-24") { i in
            var x = self.steady(i)
            if i >= 150 { x.vo2max = nil }
            return x
        }
        let h = VitalityEngine.healthspan(days: d, asOf: "2026-09-24", chronoAge: 35, sex: "male")!
        XCTAssertEqual(h.recentBodyAge!.factorsUsed, h.bodyAge.factorsUsed)
        XCTAssertEqual(h.paceOfAging!, 1, accuracy: 1e-6)
    }

    func testPaceBands() {
        XCTAssertEqual(VitalityEngine.paceBand(-0.2), .reversing)
        XCTAssertEqual(VitalityEngine.paceBand(0), .slowing)
        XCTAssertEqual(VitalityEngine.paceBand(0.94), .slowing)
        XCTAssertEqual(VitalityEngine.paceBand(0.95), .steady)
        XCTAssertEqual(VitalityEngine.paceBand(1.049), .steady)
        XCTAssertEqual(VitalityEngine.paceBand(1.05), .accelerated)
    }

    // MARK: Cross-platform oracle

    /// A mixed 200-day history (unworn days, sparse HRV, weekly VO₂max, a worse last month). These exact
    /// values are pinned verbatim in the Kotlin `VitalityWindowTest.oracleScenario`; change both together.
    static func oracleDays() -> [VitalityEngine.Day] {
        let end = VitalityEngine.epochDay("2026-09-19")!
        var out: [VitalityEngine.Day] = []
        for i in 0..<200 {
            if i % 11 == 5 { continue }   // unworn days
            let late = i >= 170
            out.append(.init(day: dayString(end - 199 + i),
                restingHR: Double(55 + (i * 7) % 9) + (late ? 3 : 0),
                sleepHours: 6.1 + Double((i * 5) % 13) / 7.0 - (late ? 0.4 : 0),
                rmssd: i % 4 == 0 ? nil : 38 + Double((i * 3) % 17) / 3.0,
                steps: Double(6200 + (i * 347) % 5100),
                vo2max: i % 7 == 3 ? 41.3 + Double(i % 5) * 0.37 : nil,
                zone13Min: i % 3 == 0 ? 22.5 + Double(i % 4) * 3.3 : 0,
                zone45Min: (i % 5 == 0 && !late) ? 6.7 : 0))
        }
        return out
    }

    func testOracleScenario() {
        let h = VitalityEngine.healthspan(days: Self.oracleDays(), asOf: "2026-09-19", chronoAge: 38, sex: "female")!
        XCTAssertEqual(h.bodyAge.bodyAge, 33.91589056915685)
        XCTAssertEqual(h.bodyAge.vitality, 60.21027357710787)
        XCTAssertEqual(h.recentBodyAge?.bodyAge, 34.42838703817101)
        XCTAssertEqual(h.paceOfAging, 2.024992938028319)
        XCTAssertEqual(h.coveredDays, 164)
        XCTAssertEqual(h.recentCoveredDays, 27)
        let c = Dictionary(uniqueKeysWithValues: h.bodyAge.contributions.map { ($0.key, ($0.lnHazard, $0.weight)) })
        XCTAssertEqual(c["rhr"]!.0, -0.06); XCTAssertEqual(c["rhr"]!.1, 0.5)
        XCTAssertEqual(c["vo2max"]!.0, -0.27070683229813625)
        XCTAssertEqual(c["sleep"]!.0, 0.012916376306620032)
        XCTAssertEqual(c["consistency"]!.0, -0.07605684646886696)
        XCTAssertEqual(c["hrv"]!.0, -0.029147286821705424)
        XCTAssertEqual(c["steps"]!.0, -0.11368819512195116)
        XCTAssertEqual(c["zones"]!.0, 0.06973592311234264); XCTAssertEqual(c["zones"]!.1, 0.5)
        let z = VitalityEngine.zoneMinutes(zonesJSON: #"{"z1":12.5,"z2":30.1,"z3":20,"z4":7.3,"z5":1.1}"#, durationS: 2873)!
        XCTAssertEqual(z.z13, 29.97496666666667)
        XCTAssertEqual(z.z45, 4.022200000000001)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 38, sex: "female"), 34.8)
        XCTAssertEqual(VitalityEngine.expectedVO2max(age: 63.3, sex: ""), 28.509999999999998)
    }
}
