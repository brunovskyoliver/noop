import XCTest
@testable import StrandAnalytics

/// The cached twiddle table in `respRegularity` must be bit-identical to the direct `cos`/`sin` DFT it
/// replaced, or Swift would drift from the Kotlin twin. Oracle: the pre-cache loop, verbatim.
final class SleepStagerV2RespTrigTests: XCTestCase {
    private func direct(_ beats: [(Double, Double)]) -> Double? {
        if beats.count < 12 { return nil }
        let t0 = beats.first!.0, tN = beats.last!.0
        if tN <= t0 { return nil }
        let n = Int(ceil((tN - t0) / 0.25 - 1e-9))
        if n < 16 { return nil }
        var y = [Double](repeating: 0, count: n)
        var seg = 0
        for i in 0..<n {
            let t = t0 + 0.25 * Double(i)
            while seg < beats.count - 2 && beats[seg + 1].0 < t { seg += 1 }
            let ta = beats[seg].0, tb = beats[seg + 1].0
            let va = beats[seg].1, vb = beats[seg + 1].1
            y[i] = tb <= ta ? va : va + min(max((t - ta) / (tb - ta), 0), 1) * (vb - va)
        }
        let mean = y.reduce(0, +) / Double(n)
        for i in 0..<n { y[i] -= mean }
        let kLo = Int(ceil(0.15 * 0.25 * Double(n)))
        let kHi = Int(floor(0.40 * 0.25 * Double(n)))
        if kHi < kLo || kLo < 0 { return nil }
        var maxP = 0.0, sumP = 0.0
        for k in kLo...kHi {
            var re = 0.0, im = 0.0
            let w = -2.0 * Double.pi * Double(k) / Double(n)
            for j in 0..<n { let a = w * Double(j); re += y[j] * cos(a); im += y[j] * sin(a) }
            let p = re * re + im * im
            sumP += p
            if p > maxP { maxP = p }
        }
        if sumP == 0 { return nil }
        return maxP / sumP
    }

    func testCachedTableMatchesDirectDFTBitForBit() {
        var rng = SystemRandomNumberGenerator()
        var trig: [Int: SleepStagerV2.RespDFT] = [:]
        for _ in 0..<300 {
            // Varying spans hit both fresh and cached grid lengths.
            let span = Int.random(in: 20...215, using: &rng)
            var beats: [(Double, Double)] = []
            for s in 0..<span where Int.random(in: 0..<10, using: &rng) > 0 {
                for _ in 0..<Int.random(in: 1...2, using: &rng) {
                    beats.append((Double(s), Double.random(in: 300...2000, using: &rng)))
                }
            }
            beats.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            let want = direct(beats), got = SleepStagerV2.respRegularity(beats, dft: &trig)
            XCTAssertEqual(want?.bitPattern, got?.bitPattern)
        }
        XCTAssertFalse(trig.isEmpty)
    }
}
