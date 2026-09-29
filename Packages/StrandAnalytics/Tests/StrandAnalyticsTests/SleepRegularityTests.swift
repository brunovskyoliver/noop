import XCTest
@testable import StrandAnalytics

final class SleepRegularityTests: XCTestCase {
    typealias SR = SleepRegularity
    let utc = TimeZone(identifier: "UTC")!

    func days(_ n: Int, from first: String = "2026-01-01") -> [String] {
        (0..<n).map { SR.dayKey(first, offset: $0)! }
    }
    /// A session starting `onsetH` hours after `day`'s window start (18:00 the evening before), `lenH` long.
    func night(_ day: String, onsetH: Double = 5, lenH: Double = 8, wake: [(Double, Double)] = []) -> SR.Session {
        let w = SR.windowStart(day: day, timeZone: utc)!
        let s = w + Int(onsetH * 3600)
        return SR.Session(start: s, end: s + Int(lenH * 3600),
                          wake: wake.map { (w + Int($0.0 * 3600))..<(w + Int($0.1 * 3600)) })
    }

    func testPerfectlyRegularScheduleIs100() {
        let d = days(10)
        let r = SR.sri(days: [d.last!], sessions: d.map { night($0) }, timeZone: utc)
        XCTAssertEqual(r[d.last!]!, 100, accuracy: 1e-9)
        XCTAssertEqual(SR.restConsistency(days: [d.last!], sessions: d.map { night($0) }, timeZone: utc)[d.last!]!,
                       1, accuracy: 1e-9)
    }

    func testRandomScheduleIsNearZero() {
        // Every 5 min block asleep with probability 1/2, independently: P(same) = 1/2, SRI ≈ 0
        // (sd ≈ 2.4 over 1,728 block pairs). Seeded, so the test is deterministic.
        var seed: UInt64 = 0x5EED
        func coin() -> Bool { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 63 == 1 }
        var sessions: [SR.Session] = []
        let d = days(7)
        for day in d {
            let w = SR.windowStart(day: day, timeZone: utc)!
            for b in 0..<288 where coin() {
                sessions.append(SR.Session(start: w + b * 300, end: w + (b + 1) * 300))
            }
        }
        let r = SR.sri(days: [d.last!], sessions: sessions, timeZone: utc)
        XCTAssertEqual(r[d.last!]!, 0, accuracy: 8)
    }

    func testShiftedScheduleRecoversAnalyticSRI() {
        // Alternate days shifted by δ h: each consecutive pair mismatches 2δ of 24 h, so SRI = 100 − 200·2δ/24.
        let d = days(7)
        for delta in [0.5, 1, 2, 3] {
            let sessions = d.enumerated().map { night($0.element, onsetH: 5 + ($0.offset.isMultiple(of: 2) ? 0 : delta)) }
            let r = SR.sri(days: [d.last!], sessions: sessions, timeZone: utc)[d.last!]!
            XCTAssertEqual(r, 100 - 200 * 2 * delta / 24, accuracy: 1e-9, "δ = \(delta) h")
        }
        // Rest's 4-day credit for tonight shifted 1 h against identical prior nights: A = 1 − 2/24, 2A − 1.
        var sessions = d.dropLast().map { night($0) }
        sessions.append(night(d.last!, onsetH: 6))
        XCTAssertEqual(SR.restConsistency(days: [d.last!], sessions: sessions, timeZone: utc)[d.last!]!,
                       1 - 4.0 / 24, accuracy: 1e-9)
    }

    func testNapsAndWASOMoveTheValueTheRightWay() {
        let d = days(7)
        let base = d.map { night($0) }
        // The same nap every day keeps the schedule perfectly regular.
        let dailyNap = base + d.map { night($0, onsetH: 20, lenH: 1) }
        XCTAssertEqual(SR.sri(days: [d.last!], sessions: dailyNap, timeZone: utc)[d.last!]!, 100, accuracy: 1e-9)
        // One irregular nap lowers it.
        let oneNap = base + [night(d[3], onsetH: 20, lenH: 1)]
        XCTAssertLessThan(SR.sri(days: [d.last!], sessions: oneNap, timeZone: utc)[d.last!]!, 100)
        // One night with an hour awake in the middle lowers it; the main-sleep window alone would not.
        var waso = base
        waso[3] = night(d[3], wake: [(8, 9)])
        let v = SR.sri(days: [d.last!], sessions: waso, timeZone: utc)[d.last!]!
        XCTAssertEqual(v, 100 - 200 * 2.0 / (6 * 24), accuracy: 1e-9)
    }

    func testMissingDaysAndColdStartAreNil() {
        let d = days(7)
        // Six nights: day 0's window is not captured, so only 5 of 6 pairs (120 h) remain: still valid.
        XCTAssertNotNil(SR.sri(days: [d.last!], sessions: d.dropFirst().map { night($0) }, timeZone: utc)[d.last!])
        // Two missing nights in the middle leave under 120 h of known pairs.
        let gappy = d.enumerated().filter { $0.offset != 2 && $0.offset != 4 }.map { night($0.element) }
        XCTAssertNil(SR.sri(days: [d.last!], sessions: gappy, timeZone: utc)[d.last!])
        // A short strap-off day (under 2 h recorded) is unknown, not "awake all day".
        var short = d.map { night($0) }
        short[3] = night(d[3], lenH: 1)
        short[5] = night(d[5], lenH: 1)
        XCTAssertNil(SR.sri(days: [d.last!], sessions: short, timeZone: utc)[d.last!])
        // Cold start.
        XCTAssertNil(SR.sri(days: [d[2]], sessions: d.prefix(3).map { night($0) }, timeZone: utc)[d[2]])
        XCTAssertNil(SR.restConsistency(days: [d[1]], sessions: d.prefix(2).map { night($0) }, timeZone: utc)[d[1]])
    }

    func testImportedConsistencyWinsAndSRIIsClampedForDisplay() {
        let keys = ["2026-09-01", "2026-09-02"]
        let sri = ["2026-09-01": 80.0, "2026-09-02": -20.0]
        XCTAssertEqual(SR.resolve(dayKeys: keys, importedPct: [:], sriByDay: sri).map(\.pct), [80, 0])
        XCTAssertEqual(SR.resolve(dayKeys: keys, importedPct: ["2026-09-02": 61], sriByDay: sri).map(\.pct), [61])
        // Imported that does not cover the newest day falls back to the SRI.
        XCTAssertEqual(SR.resolve(dayKeys: keys, importedPct: ["2026-09-01": 61], sriByDay: sri).map(\.pct), [80, 0])
    }

    func testStagesJSONWakeSegmentsBecomeWASO() {
        let json = #"[{"start":100,"end":400,"stage":"light"},{"start":400,"end":500,"stage":"wake"},{"start":500,"end":900,"stage":"deep"}]"#
        XCTAssertEqual(SR.Session(start: 100, end: 900, stagesJSON: json).wake, [400..<500])
        XCTAssertEqual(SR.Session(start: 100, end: 900, stagesJSON: #"{"light":200,"awake":10}"#).wake, [])
    }
}
