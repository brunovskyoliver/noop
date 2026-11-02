import XCTest
@testable import StrandAnalytics

final class CyclePhaseEngineTests: XCTestCase {

    /// Build a synthetic biphasic series of `cycles` repeats of a `cycleLen`-day cycle, oldest→newest.
    /// Follicular nights sit near 0; luteal nights (the back `lutealLen` days of each cycle) are elevated.
    /// tempZ leads, rhrZ ↑ and hrvZ ↓ corroborate (note hrvZ is the RAW HRV z, which the engine negates).
    private func biphasic(cycles: Int, cycleLen: Int = 28, lutealLen: Int = 12,
                          start: String = "2026-01-01") -> [CyclePhaseEngine.Night] {
        var nights: [CyclePhaseEngine.Night] = []
        var idx = 0
        for _ in 0..<cycles {
            for dayInCycle in 0..<cycleLen {
                let day = CyclePhaseEngine.shiftDay(start, by: idx)!
                let luteal = dayInCycle >= (cycleLen - lutealLen)
                let tempZ = luteal ? 1.4 : -0.2
                let rhrZ = luteal ? 1.0 : -0.1
                let hrvZ = luteal ? -1.0 : 0.1     // HRV DROPS in luteal (negative z)
                nights.append(.init(day: day, tempZ: tempZ, rhrZ: rhrZ, hrvZ: hrvZ))
                idx += 1
            }
        }
        return nights
    }

    // MARK: - Biphasic series classifies correctly

    func testLutealNightClassifiesLuteal() {
        // End the series deep inside a luteal run.
        let nights = biphasic(cycles: 3)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertEqual(r.phase, .luteal)
        XCTAssertNotEqual(r.confidence, .learning)
        XCTAssertFalse(r.shiftMarkers.isEmpty)
    }

    func testFollicularNightClassifiesFollicular() {
        // 3 full cycles (luteal ends each) + a short follicular run, so the LAST night is follicular.
        var nights = biphasic(cycles: 3)
        let startNext = CyclePhaseEngine.shiftDay(nights.last!.day, by: 1)!
        for i in 0..<8 {                          // 8 follicular nights past the last luteal
            let day = CyclePhaseEngine.shiftDay(startNext, by: i)!
            nights.append(.init(day: day, tempZ: -0.2, rhrZ: -0.1, hrvZ: 0.1))
        }
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertEqual(r.phase, .follicular)
    }

    func testDetectsPlausibleCycleLength() {
        let nights = biphasic(cycles: 4, cycleLen: 28)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertNotNil(r.cycleLengthDays)
        if let len = r.cycleLengthDays {
            XCTAssertTrue((CyclePhaseEngine.minCycleDays...CyclePhaseEngine.maxCycleDays).contains(len))
            XCTAssertEqual(len, 28, accuracy: 2)
        }
        XCTAssertEqual(r.confidence, .solid)
    }

    func testCycleDayEstimateIsARangeNotAPoint() {
        let nights = biphasic(cycles: 3)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertNotNil(r.cycleDayLow)
        XCTAssertNotNil(r.cycleDayHigh)
        if let lo = r.cycleDayLow, let hi = r.cycleDayHigh {
            XCTAssertLessThan(lo, hi)          // a genuine range, never a single confident day
        }
    }

    // MARK: - Next-period output is a WINDOW, never a single date

    func testNextPeriodIsAWindow() {
        let nights = biphasic(cycles: 4)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        if let w = r.nextPeriodWindow {
            XCTAssertLessThanOrEqual(w.earliestDay, w.latestDay)
            XCTAssertNotEqual(w.earliestDay, w.latestDay)   // a range, not a hard date
        }
    }

    /// Temperature-only mode (no logged start): the anchor is the shift near ovulation, so the next
    /// period is about one luteal phase later. 4 cycles of 28 days, luteal = last 12 days: the last shift
    /// is day 100, the next period starts on day 112. The old anchor + cycle length landed on day 128.
    func testTemperatureOnlyWindowIsOneLutealPhaseAfterTheShift() {
        let nights = biphasic(cycles: 4)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        let w = r.nextPeriodWindow!
        let expected = CyclePhaseEngine.shiftDay("2026-01-01", by: 112)!
        XCTAssertLessThanOrEqual(w.earliestDay, expected)
        XCTAssertGreaterThanOrEqual(w.latestDay, expected)
        XCTAssertEqual(w.latestDay, CyclePhaseEngine.shiftDay("2026-01-01", by: 114)!)
    }

    /// A logged period start is day 1: the window sits one cycle length later.
    func testLoggedStartWindowIsOneCycleAfterTheLog() {
        let nights = biphasic(cycles: 4)
        let lastStart = CyclePhaseEngine.shiftDay("2026-01-01", by: 84)!
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true, loggedPeriodStarts: [lastStart])
        let w = r.nextPeriodWindow!
        XCTAssertEqual(w.latestDay, CyclePhaseEngine.shiftDay("2026-01-01", by: 84 + 28 + 2)!)
    }

    // MARK: - Flat / irregular → "no clear pattern", never a fabricated phase

    func testFlatSeriesYieldsUnknownNotAPhase() {
        // No elevation anywhere → no onset → unknown, with shiftMarkers empty.
        var nights: [CyclePhaseEngine.Night] = []
        for i in 0..<60 {
            let day = CyclePhaseEngine.shiftDay("2026-01-01", by: i)!
            nights.append(.init(day: day, tempZ: 0.05, rhrZ: 0.0, hrvZ: 0.0))
        }
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertEqual(r.phase, .unknown)
        XCTAssertNil(r.cycleLengthDays)
        XCTAssertNil(r.nextPeriodWindow)
    }

    // MARK: - Gates: < 1.5 cycles, untrusted baseline → learning

    func testInsufficientDataIsLearning() {
        let nights = biphasic(cycles: 1, cycleLen: 28)   // 28 < 42 nights
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true)
        XCTAssertEqual(r.phase, .learning)
        XCTAssertEqual(r.confidence, .learning)
    }

    func testUnusableBaselineIsLearning() {
        let nights = biphasic(cycles: 3)
        let r = CyclePhaseEngine.classify(nights, baselineUsable: false)
        XCTAssertEqual(r.phase, .learning)
    }

    // MARK: - Logged-period mode: agrees, and a mistimed log is flagged

    func testLoggedPeriodMistimedIsFlagged() {
        // Anchor a logged "period start" implausibly far before the latest night (> max cycle).
        let nights = biphasic(cycles: 3)
        let lastDay = nights.last!.day
        let badStart = CyclePhaseEngine.shiftDay(lastDay, by: -50)!
        let r = CyclePhaseEngine.classify(nights, baselineUsable: true, loggedPeriodStarts: [badStart])
        XCTAssertTrue(r.note.lowercased().contains("logged"))
    }

    // MARK: - No fertility / contraception language anywhere (banned strings)

    func testNoFertilityOrContraceptionLanguage() {
        let banned = ["fertile", "fertility", "safe day", "safe days", "ovulation prediction",
                      "contracept", "conceive", "conception", "pregnan"]
        // Exercise multiple phases + the awareness line.
        let series: [[CyclePhaseEngine.Night]] = [
            biphasic(cycles: 3),
            Array(biphasic(cycles: 3).dropLast(6)),
            (0..<60).map { CyclePhaseEngine.Night(day: CyclePhaseEngine.shiftDay("2026-01-01", by: $0)!,
                                                  tempZ: 0.05, rhrZ: 0, hrvZ: 0) },
        ]
        for nights in series {
            let note = CyclePhaseEngine.classify(nights, baselineUsable: true).note.lowercased()
            for b in banned { XCTAssertFalse(note.contains(b), "note contained banned term \(b): \(note)") }
        }
        let awareness = CyclePhaseEngine.awarenessLine.lowercased()
        for b in banned {
            // The awareness line legitimately contains "contraception" via "not contraception"; allow only that.
            if b == "contracept" { continue }
            XCTAssertFalse(awareness.contains(b))
        }
        XCTAssertTrue(CyclePhaseEngine.awarenessLine.contains("not contraception"))
    }

    // MARK: - Fusion math

    func testFusedIndexNegatesHRVAndRenormalises() {
        // Temp-only night: index == tempZ exactly (renormalised over the single present weight).
        XCTAssertEqual(CyclePhaseEngine.fusedIndex(tempZ: 1.5, rhrZ: nil, hrvZ: nil)!, 1.5, accuracy: 1e-9)
        // All three present: (0.6·1 + 0.2·1 + 0.2·(−(−1))) / 1.0 = 1.0
        XCTAssertEqual(CyclePhaseEngine.fusedIndex(tempZ: 1, rhrZ: 1, hrvZ: -1)!, 1.0, accuracy: 1e-9)
        // No signal → nil.
        XCTAssertNil(CyclePhaseEngine.fusedIndex(tempZ: nil, rhrZ: nil, hrvZ: nil))
    }

    // MARK: - Assembly seam (a live deviation must reach classify)

    private func rows(_ n: Int, _ value: (Int) -> Double?) -> [CyclePhaseEngine.DayRow] {
        (0..<n).map { i in
            .init(day: CyclePhaseEngine.shiftDay("2026-01-01", by: i)!, skinTempDevC: value(i), restingHr: nil, hrv: nil)
        }
    }

    func testLiveDeviationsMakeTheBaselineUsable() {
        let a = CyclePhaseEngine.assemble(rows(60) { i in Double(i % 11) / 10 - 0.5 })
        XCTAssertTrue(a.baselineUsable)
        XCTAssertEqual(a.nights.compactMap(\.tempZ).count, 60)
        XCTAssertNotEqual(CyclePhaseEngine.classify(a.nights, baselineUsable: a.baselineUsable).phase, .learning)
    }

    func testImportedAndLiveRowsAreScoredOnTheirOwnScales() {
        let a = CyclePhaseEngine.assemble(rows(60) { i in i < 30 ? 33 + Double(i % 5) / 10 : Double(i % 5) / 10 - 0.2 })
        for z in a.nights.compactMap(\.tempZ) { XCTAssertLessThan(abs(z), 5) }
    }

    // MARK: - Noise and debouncing

    /// Small deterministic generator, so the noise numbers do not change between runs.
    private struct LCG { var s: UInt64
        mutating func uniform() -> Double {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(s >> 11) / Double(1 << 53)
        }
        mutating func gauss() -> Double {
            (-2 * log(max(uniform(), 1e-12))).squareRoot() * cos(2 * .pi * uniform())
        }
    }

    private func noisy(_ n: Int, seed: UInt64, luteal: (Int) -> Double = { _ in 0 }) -> [CyclePhaseEngine.Night] {
        var g = LCG(s: seed)
        return (0..<n).map { i in
            .init(day: CyclePhaseEngine.shiftDay("2026-01-01", by: i)!, tempZ: g.gauss() + luteal(i), rhrZ: nil, hrvZ: nil)
        }
    }

    func testNoiseRarelyNamesAPhase() {
        var named = 0
        for seed in 1...500 where CyclePhaseEngine.classify(noisy(180, seed: UInt64(seed)), baselineUsable: true).phase != .unknown {
            named += 1
        }
        XCTAssertLessThan(named, 25, "noise named a phase in \(named)/500 series")
    }

    func testAOneNightWobbleIsNotAShift() {
        var nights = biphasic(cycles: 3)
        nights[5] = .init(day: nights[5].day, tempZ: 3, rhrZ: 1, hrvZ: -1)
        XCTAssertEqual(CyclePhaseEngine.classify(nights, baselineUsable: true).shiftMarkers.count, 3)
    }

    func testMissingNightDoesNotCreateAnOnset() {
        let full = biphasic(cycles: 3)
        var gapped = full
        let n = gapped[20]   // inside a luteal run
        gapped[20] = .init(day: n.day, tempZ: nil, rhrZ: nil, hrvZ: nil)
        XCTAssertEqual(CyclePhaseEngine.classify(gapped, baselineUsable: true).shiftMarkers,
                       CyclePhaseEngine.classify(full, baselineUsable: true).shiftMarkers)
    }

    func testIrregularCadenceIsUnknown() {
        // Three strong shifts 15 and 37 days apart: spread far beyond a regular cycle.
        var nights: [CyclePhaseEngine.Night] = []
        let onsets = [10, 25, 62]
        for i in 0..<80 {
            let hot = onsets.contains { i >= $0 && i < $0 + 8 }
            nights.append(.init(day: CyclePhaseEngine.shiftDay("2026-01-01", by: i)!, tempZ: hot ? 2 : 0, rhrZ: nil, hrvZ: nil))
        }
        XCTAssertEqual(CyclePhaseEngine.classify(nights, baselineUsable: true).phase, .unknown)
    }

    func testYoungShiftIsReportedAroundTheTurnNotLuteal() {
        let r = CyclePhaseEngine.classify(Array(biphasic(cycles: 4).dropLast(9)), baselineUsable: true)
        XCTAssertEqual(r.phase, .periOvulatory)
    }

    func testOneShiftNeedsALoggedPeriod() {
        let nights = Array(biphasic(cycles: 2).dropFirst(14))   // one confirmed shift inside this slice
        var last = Array(nights.prefix(28))
        let tail = (0..<16).map { CyclePhaseEngine.Night(day: CyclePhaseEngine.shiftDay(last.last!.day, by: $0 + 1)!,
                                                          tempZ: -0.2, rhrZ: -0.1, hrvZ: 0.1) }
        last += tail
        XCTAssertEqual(CyclePhaseEngine.classify(last, baselineUsable: true).phase, .unknown)
    }
}
