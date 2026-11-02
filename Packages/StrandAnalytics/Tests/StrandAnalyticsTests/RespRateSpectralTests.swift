import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// The RSA estimate tracks the breathing rate instead of a peak-picker's quantised grid, and declines to
/// answer when the tachogram holds no breathing.
final class RespRateSpectralTests: XCTestCase {
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func stream(rate: Double, ampMs: Double, noiseMs: Double, seed: UInt64, hours: Double = 6) -> [RRInterval] {
        var rng = Seeded(state: seed)
        var t = 0.0
        var out: [RRInterval] = []
        while t < hours * 3600 {
            let noise = Double.random(in: -noiseMs...noiseMs, using: &rng)
            let v = 1000 + ampMs * sin(2 * .pi * rate / 60 * t) + noise
            out.append(RRInterval(ts: Int(t), rrMs: Int(v)))
            t += v / 1000
        }
        return out
    }

    func testTracksRatesIncludingOnesOffThePeakGrid() {
        for rate in [12.0, 13.0, 14.0, 15.5, 16.0, 18.0] {
            let est = SleepStager.respRateFromRR(stream(rate: rate, ampMs: 40, noiseMs: 15, seed: 7),
                                                 start: 0, end: 6 * 3600)
            XCTAssertEqual(est, rate, accuracy: 0.3, "injected \(rate)")
        }
    }

    func testPureJitterHasNoRate() {
        for seed: UInt64 in 1...8 {
            let est = SleepStager.respRateFromRR(stream(rate: 14, ampMs: 0, noiseMs: 40, seed: seed),
                                                 start: 0, end: 6 * 3600)
            XCTAssertTrue(est.isNaN, "seed \(seed) returned \(est)")
        }
    }

    /// Nothing but a slow autonomic swing below the breathing band must not read as very slow breathing.
    func testBandEdgeDriftHasNoRate() {
        let est = SleepStager.respRateFromRR(stream(rate: 5, ampMs: 60, noiseMs: 20, seed: 3),
                                             start: 0, end: 6 * 3600)
        XCTAssertTrue(est.isNaN, "returned \(est)")
    }

    /// A night that loses the signal partway keeps its rate from the windows that had one.
    func testPartlyNoisyNightKeepsTheRateOfItsGoodWindows() {
        let good = stream(rate: 15, ampMs: 40, noiseMs: 15, seed: 11, hours: 3)
        let shift = good.last!.ts + 1
        let bad = stream(rate: 15, ampMs: 0, noiseMs: 40, seed: 12, hours: 2).map {
            RRInterval(ts: $0.ts + shift, rrMs: $0.rrMs)
        }
        XCTAssertEqual(SleepStager.respRateFromRR(good + bad, start: 0, end: 6 * 3600), 15, accuracy: 0.3)
    }

    /// Calibration record: the null distribution of the quality score, which is what the floor comes from.
    func testQualityFloorSitsAboveWhiteNoiseNull() {
        var scores: [Double] = []
        var rng = Seeded(state: 99)
        for _ in 0..<400 {
            let x = (0..<1200).map { _ in Double.random(in: -1...1, using: &rng) }
            if let r = SleepStager.rsaWindowPeak(x) { scores.append(r.quality) } else { scores.append(0) }
        }
        scores.sort()
        XCTAssertLessThan(scores[396], SleepStager.rsaMinWindowQuality)
    }
}
