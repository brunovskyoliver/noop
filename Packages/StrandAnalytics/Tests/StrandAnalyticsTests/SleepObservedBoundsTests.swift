import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// A night reports only what the strap observed: HR-less edges leave the session and HR-less interior
/// stretches stay out of the sleep total, while a truncated read no longer leaves a fragment on the day.
final class SleepObservedBoundsTests: XCTestCase {
    let d0 = 1_791_936_000 // 2026-10-14 00:00 UTC

    private func moving(_ a: Int, _ b: Int) -> [GravitySample] {
        stride(from: a, to: b, by: 1).map {
            GravitySample(ts: $0, x: sin(Double($0)) * 0.3, y: cos(Double($0) * 1.7) * 0.3, z: 0.9)
        }
    }
    private func still(_ a: Int, _ b: Int) -> [GravitySample] {
        stride(from: a, to: b, by: 1).map { GravitySample(ts: $0, x: 0.1, y: 0.2, z: 0.97) }
    }
    private func hr(_ a: Int, _ b: Int, _ bpm: Int) -> [HRSample] {
        stride(from: a, to: b, by: 1).map { HRSample(ts: $0, bpm: bpm + (($0 / 97) % 5) - 2) }
    }
    private func tstMin(_ s: SleepSession) -> Double { SleepStager.hypnogramMetrics(s).tstS / 60 }

    /// Strap on the nightstand from 07:30 to 10:00: the night ends at the last heartbeat.
    func testOffWristTailEndsTheNightAtTheLastHeartbeat() throws {
        let a = d0 + 18 * 3600, s = d0 + 23 * 3600, off = d0 + 31 * 3600 + 1800, on = d0 + 34 * 3600, e = d0 + 36 * 3600
        let grav = moving(a, s) + still(s, on) + moving(on, e)
        let beats = hr(a, s, 75) + hr(s, off, 54) + hr(on, e, 78)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertEqual(night.end, off - 1)
        XCTAssertLessThanOrEqual(tstMin(night), Double(off - s) / 60)
    }

    /// The same for a strap put on after lying still: the night opens at the first heartbeat.
    func testHRlessLeadInStartsTheNightAtTheFirstHeartbeat() throws {
        let a = d0 + 18 * 3600, s = d0 + 22 * 3600, on = d0 + 23 * 3600, w = d0 + 31 * 3600, e = d0 + 33 * 3600
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = hr(a, s - 1800, 75) + hr(on, w, 54) + hr(w, e, 78)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertEqual(night.start, on)
    }

    /// A 40-minute hole inside a night is neither staged nor counted, and efficiency ignores it.
    func testInteriorGapIsNotStagedOrCounted() throws {
        let a = d0 + 18 * 3600, s = d0 + 23 * 3600, gap = d0 + 27 * 3600, resume = gap + 2400, w = d0 + 31 * 3600, e = d0 + 33 * 3600
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = hr(a, s, 75) + hr(s, gap, 54) + hr(resume, w, 54) + hr(w, e, 78)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertFalse(night.stages.contains { $0.start < resume - 1 && gap < $0.end })
        XCTAssertLessThanOrEqual(tstMin(night), Double(w - s - 2400) / 60 + 1)
        let wake = night.stages.filter { SleepStageVocabulary.isWake($0.stage) }.reduce(0) { $0 + $1.end - $1.start }
        let covered = night.stages.reduce(0) { $0 + $1.end - $1.start }
        XCTAssertEqual(night.efficiency, Double(covered - wake) / Double(covered), accuracy: 0.001)
    }

    /// A short dropout under the threshold stays inside the staged night.
    func testShortDropoutStaysStaged() throws {
        let a = d0 + 18 * 3600, s = d0 + 23 * 3600, gap = d0 + 27 * 3600, w = d0 + 31 * 3600, e = d0 + 33 * 3600
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = hr(a, s, 75) + hr(s, gap, 54) + hr(gap + 200, w, 54) + hr(w, e, 78)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertTrue(night.stages.contains { $0.start <= gap + 100 && gap + 100 < $0.end })
    }

    /// A sparse stream (WHOOP 4.0 reconstruction) has natural gaps; its bounds and stages stay untouched.
    func testSparseHRStreamIsNotTrimmed() throws {
        let a = d0 + 18 * 3600, s = d0 + 23 * 3600, w = d0 + 31 * 3600, e = d0 + 33 * 3600
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = stride(from: a, to: e, by: 900).map { HRSample(ts: $0, bpm: $0 >= s && $0 < w ? 54 : 75) }
        let night = SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first
        if let night {
            XCTAssertEqual(night.stages.reduce(0) { $0 + $1.end - $1.start }, night.end - night.start)
        }
    }

    /// The 09baea0b regression at the scoring level: a day read past midnight keeps no piece of a night
    /// that goes on, and the following day owns all of it.
    func testNightCrossingMidnightLeavesNoFragmentOnTheEarlierDay() {
        let dayD = "2026-10-14", dayNext = "2026-10-15"
        let a = d0 + 6 * 3600, s = d0 + 22 * 3600, w = d0 + 86_400 + 6 * 3600, e = d0 + 86_400 + 9 * 3600
        let readEndD = d0 + 86_400 + LocalDayWindows.scoredDayOverrunSeconds
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = hr(a, s, 75) + hr(s, w, 54) + hr(w, e, 78)
        let earlier = AnalyticsEngine.analyzeDay(day: dayD, hr: beats.filter { $0.ts <= readEndD },
                                                 gravity: grav.filter { $0.ts <= readEndD },
                                                 profile: .init(), useSleepStagerV2: true)
        XCTAssertTrue(earlier.sleepSessions.isEmpty, "\(earlier.sleepSessions.map { ($0.start - d0, $0.end - d0) })")
        let later = AnalyticsEngine.analyzeDay(day: dayNext, hr: beats, gravity: grav, profile: .init(), useSleepStagerV2: true)
        XCTAssertEqual(Double(later.sleepSessions.first?.start ?? 0), Double(s), accuracy: 300)
        XCTAssertEqual(Double(later.sleepSessions.first?.end ?? 0), Double(w), accuracy: 300)
        // The read that stopped one second short of midnight is what kept the fragment.
        let cut = d0 + 86_399
        let truncated = AnalyticsEngine.analyzeDay(day: dayD, hr: beats.filter { $0.ts <= cut },
                                                   gravity: grav.filter { $0.ts <= cut },
                                                   profile: .init(), useSleepStagerV2: true)
        XCTAssertEqual(truncated.sleepSessions.count, 1)
    }
}

extension SleepObservedBoundsTests {
    /// 21:30-23:50, a half hour up, then 00:20-07:00 is one night and belongs wholly to the later day.
    func testNightSplitAcrossMidnightLandsOnTheDayItEnds() {
        let a = d0 + 8 * 3600, s1 = d0 + 21 * 3600 + 1800, up = d0 + 23 * 3600 + 3000
        let s2 = d0 + 86_400 + 1200, w = d0 + 86_400 + 7 * 3600, e = d0 + 86_400 + 10 * 3600
        let grav = moving(a, s1) + still(s1, up) + moving(up, s2) + still(s2, w) + moving(w, e)
        let beats = hr(a, s1, 78) + hr(s1, up, 54) + hr(up, s2, 78) + hr(s2, w, 54) + hr(w, e, 78)
        let readEndD = d0 + 86_400 + LocalDayWindows.scoredDayOverrunSeconds
        let earlier = AnalyticsEngine.analyzeDay(day: "2026-10-14", hr: beats.filter { $0.ts <= readEndD },
                                                 gravity: grav.filter { $0.ts <= readEndD },
                                                 profile: .init(), useSleepStagerV2: true)
        XCTAssertTrue(earlier.sleepSessions.isEmpty)
        let later = AnalyticsEngine.analyzeDay(day: "2026-10-15", hr: beats, gravity: grav,
                                               profile: .init(), useSleepStagerV2: true)
        XCTAssertEqual(later.sleepSessions.count, 2)
        XCTAssertGreaterThan(later.daily.totalSleepMin ?? 0, 500)
    }
}

extension SleepObservedBoundsTests {
    /// Still on the sofa at HR 62 from 21:30, asleep at HR 52 from 23:00: the night opens with the HR drop.
    func testPreBedStillnessIsTrimmedToTheHRDrop() throws {
        let a = d0 + 12 * 3600, tv = d0 + 21 * 3600 + 1800, s = d0 + 23 * 3600, w = d0 + 31 * 3600, e = d0 + 34 * 3600
        let grav = moving(a, tv) + still(tv, w) + moving(w, e)
        let beats = hr(a, tv, 78) + hr(tv, s, 62) + hr(s, w, 52) + hr(w, e, 80)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertEqual(Double(night.start), Double(s), accuracy: 15 * 60)
    }

    /// A night whose HR never drops from its opening level keeps its start.
    func testFlatHRNightKeepsItsOnset() throws {
        let a = d0 + 12 * 3600, s = d0 + 23 * 3600, w = d0 + 31 * 3600, e = d0 + 34 * 3600
        let grav = moving(a, s) + still(s, w) + moving(w, e)
        let beats = hr(a, s, 78) + hr(s, w, 54) + hr(w, e, 80)
        let night = try XCTUnwrap(SleepStager.detectSleep(hr: beats, gravity: grav, useSleepStagerV2: true).first)
        XCTAssertEqual(Double(night.start), Double(s), accuracy: 5 * 60)
    }
}

extension SleepObservedBoundsTests {
    /// Two short nights a day apart with sparse gravity stay two runs: reading past midnight must not lose
    /// the earlier one to a 25-hour stitched run.
    func testDayLongHoleIsNotBridgedByTheBeatsAtItsEnd() {
        let start = d0 + 2 * 3600, end = start + 2 * 3600
        let beats = stride(from: start - 900, through: end, by: 5).map { HRSample(ts: $0, bpm: 50) }
        let grav = stride(from: start, through: end, by: 5).map { GravitySample(ts: $0, x: 0, y: 0, z: 1, unit: "g") }
        let to = d0 + 86_400 + LocalDayWindows.scoredDayOverrunSeconds
        let nextBeats = beats.map { HRSample(ts: $0.ts + 86_400, bpm: $0.bpm) }.filter { $0.ts <= to }
        let nextGrav = grav.map { GravitySample(ts: $0.ts + 86_400, x: 0, y: 0, z: 1, unit: "g") }.filter { $0.ts <= to }
        let r = AnalyticsEngine.analyzeDay(day: "2026-10-14", hr: beats + nextBeats, gravity: grav + nextGrav,
                                           profile: .init(), useSleepStagerV2: true)
        XCTAssertEqual(r.sleepSessions.count, 1)
        // The read can also end on the next night's very first sample, a blip after the hole.
        let blip = SleepStager.mergePeriods([SleepStager.Period(stage: "sleep", start: start, end: end),
                                             SleepStager.Period(stage: "sleep", start: start + 86_400, end: start + 86_400)])
        XCTAssertEqual(blip.first?.end, end)
    }
}

/// The smaller audit items pinned where they live.
final class SleepAuditRegressionTests: XCTestCase {
    /// Sleep held at 23:00-07:00 wall clock across the October change scores perfect consistency.
    func testRestConsistencyIsUnmovedByAClockChange() throws {
        let zone = TimeZone(identifier: "Europe/Bratislava")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        func at(_ d: Int, _ h: Int) -> Int {
            Int(cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))!.timeIntervalSince1970)
        }
        let sessions = (18...30).map { SleepRegularity.Session(start: at($0 - 1, 23), end: at($0, 7), wake: []) }
        let days = (24...30).map { String(format: "2026-10-%02d", $0) }
        let scores = SleepRegularity.restConsistency(days: days, sessions: sessions, timeZone: zone)
        for day in days { XCTAssertEqual(try XCTUnwrap(scores[day]), 1, accuracy: 0.001, day) }
    }

    /// Scored at 08:00, the rest of today is unknown rather than a day awake that disagrees with bedtimes.
    func testUnlivedEpochsAreUnknown() throws {
        let zone = TimeZone(identifier: "UTC")!
        let base = 1_791_936_000 // 2026-10-14 00:00 UTC
        let sessions = (-6...0).map { d in
            SleepRegularity.Session(start: base + d * 86_400 - 3600, end: base + d * 86_400 + 7 * 3600, wake: [])
        }
        let today = "2026-10-14"
        // The 18:00-18:00 window ending on the 14th is all lived by then; the 15th's is not.
        let tl = try XCTUnwrap(SleepRegularity.timeline(first: "2026-10-13", last: today, sessions: sessions,
                                                        timeZone: zone, now: base + 8 * 3600 - 3 * 3600))
        XCTAssertEqual(tl.state.last, -1)
    }

    /// A 4 h night three weeks back stops counting; the same night followed by a record keeps its carry.
    func testDebtDecaysAcrossUnrecordedNights() {
        let need = AnalyticsEngine.Rest.defaultNeedHours
        let stale = SleepDebt.ledger(series: [("2026-10-01", 240), ("2026-10-22", 480)], needHours: need)
        let fresh = SleepDebt.ledger(series: [("2026-10-21", 240), ("2026-10-22", 480)], needHours: need)
        XCTAssertEqual(stale.balanceMin, 0)
        XCTAssertLessThan(fresh.balanceMin, 0)
        let trailing = SleepDebt.ledger(series: [("2026-10-01", 240), ("2026-10-22", nil)], needHours: need)
        XCTAssertEqual(trailing.balanceMin, 0)
    }

    /// Need follows settled nights: a steady sleeper owes nothing to their own variability, and rebounds
    /// after short nights do not lift it.
    func testNeedIsTheMedianOfSettledNights() {
        let steady = [8.0, 8.65, 7.35, 8.65, 8.65, 7.35, 8.0, 8.0, 8.65, 7.35]
        XCTAssertEqual(AnalyticsEngine.Rest.personalizedNeedHours(nightlyHours: steady, age: 30), 8.0, accuracy: 0.34)
        let rebounds = [8.2, 8.2, 8.2, 8.2, 8.2, 5.0, 10.5, 5.0, 10.5, 8.2, 8.2]
        XCTAssertEqual(AnalyticsEngine.Rest.personalizedNeedHours(nightlyHours: rebounds, age: 30), 8.2, accuracy: 0.001)
        XCTAssertEqual(AnalyticsEngine.Rest.populationNeedFloorHours(age: 70), 7.5)
    }
}
