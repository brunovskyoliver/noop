import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class WorkoutAutoLogTests: XCTestCase {

    private let t0 = 1_800_000_000 / 60 * 60

    /// 1 Hz HR around `base`, with a square wave of `amp` bpm and `periodS` (sets and rests) on top.
    private func hr(_ durS: Int, base: Int = 115, amp: Int, periodS: Int = 180) -> [HRSample] {
        (0..<durS).map { i in HRSample(ts: t0 + i, bpm: base + ((i / (periodS / 2)) % 2 == 0 ? amp : -amp)) }
    }

    /// Steps at `perMin` a minute for the minutes in `walking`, still otherwise; one sample a second.
    private func steps(minutes: Int, walking: Set<Int>, perMin: Int = 100) -> [StepSample] {
        var out: [StepSample] = []
        var counter = 0
        for m in 0..<minutes {
            for s in 0..<60 {
                let w = walking.contains(m)
                if w { counter += s < perMin - 60 ? 2 : 1 }   // perMin in 60..<120
                out.append(StepSample(ts: t0 + m * 60 + s, counter: counter & 0xFFFF, activityClass: w ? 1 : 0))
            }
        }
        return out
    }

    func testSwingSeparatesSetsFromSteadyHR() {
        XCTAssertGreaterThan(WorkoutAutoLog.hrSwingSD(hr: hr(2400, amp: 10), start: t0, end: t0 + 2400)!, 6.5)
        XCTAssertLessThan(WorkoutAutoLog.hrSwingSD(hr: hr(2400, amp: 2), start: t0, end: t0 + 2400)!, 6.5)
        XCTAssertNil(WorkoutAutoLog.hrSwingSD(hr: hr(500, amp: 10), start: t0, end: t0 + 500), "under 600 samples")
    }

    func testAWalkNeedsTwelveMinutes() {
        let s = steps(minutes: 40, walking: Set(2..<16).union(20..<30))
        let spans = WorkoutAutoLog.walkSpans(steps: s, excluding: [], ticksPerStep: 1)
        XCTAssertEqual(spans.map { ($0.0 - t0) / 60 }, [2], "14 min is a walk, 10 min is not")
        XCTAssertEqual(spans.first.map { ($0.1 - $0.0 + 1) / 60 }, 14)
    }

    func testAShortStopDoesNotSplitAWalk() {
        let s = steps(minutes: 30, walking: Set(0..<8).union(10..<18))
        XCTAssertEqual(WorkoutAutoLog.walkSpans(steps: s, excluding: [], ticksPerStep: 1).count, 1)
    }

    /// The walk to the gym and the walk home never join across a saved lift.
    func testAWalkNeverCrossesASavedSession() {
        let s = steps(minutes: 40, walking: Set(0..<40))
        let lift = (t0 + 14 * 60, t0 + 16 * 60 - 1)
        let spans = WorkoutAutoLog.walkSpans(steps: s, excluding: [lift], ticksPerStep: 1)
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans.allSatisfy { $0.1 < lift.0 || $0.0 > lift.1 })
    }

    /// Two lift halves 10 min apart are one visit; a walk piece touching it gets no row of its own.
    func testGymVisitJoinsLiftPiecesAndFoldsTheWalkIn() {
        func s(_ a: Int, _ b: Int) -> ExerciseSession {
            ExerciseSession(start: t0 + a * 60, end: t0 + b * 60, avgHR: 120, peakHR: 150, strain: 5,
                            durationS: Double((b - a) * 60), zoneTimePct: [:], avgHRRPct: 45, hrmax: 195,
                            hrmaxSource: "caller", caloriesKcal: nil, caloriesKJ: nil, hrCoveragePct: 100,
                            isActivityTier: true)
        }
        let walkIn = s(0, 10), first = s(11, 40), second = s(50, 80), later = s(200, 230)
        let out = WorkoutAutoLog.gymVisits([walkIn, first, second, later], gaitTs: [],
                                           isWalk: { $0 == walkIn }, isLift: { $0 == first || $0 == second },
                                           make: { a, b, _ in s((a - self.t0) / 60, (b - self.t0) / 60) })
        XCTAssertEqual(out.map { ($0.start - t0) / 60 }, [11, 200])
        XCTAssertEqual(out.first.map { ($0.end - t0) / 60 }, 80)
    }
}
