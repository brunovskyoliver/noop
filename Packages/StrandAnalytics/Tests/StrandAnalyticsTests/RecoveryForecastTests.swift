import XCTest
@testable import StrandAnalytics

/// RecoveryForecaster — AR(1) estimate of tomorrow-morning Charge with a measured band. The Android
/// RecoveryForecastTest still pins the earlier weighted model; this suite is no longer its oracle.
final class RecoveryForecastTests: XCTestCase {

    func testNilUntilEnoughBaseline() {
        XCTAssertNil(RecoveryForecaster.forecast(recentCharge: []))
        XCTAssertNil(RecoveryForecaster.forecast(recentCharge: [60, 61, 62, 63]))
        XCTAssertNotNil(RecoveryForecaster.forecast(recentCharge: [60, 61, 62, 63, 64]))
    }

    func testFlatHistoryForecastsItself() {
        let f = RecoveryForecaster.forecast(recentCharge: Array(repeating: 60, count: 14))!
        XCTAssertEqual(f.charge, 60)
        XCTAssertEqual(f.band, RecoveryForecaster.minBandPoints)
        XCTAssertEqual(f.nights, 14)
    }

    /// Charge falling 80 to 40. The old slope term pushed this up to about 63, away from the trend and
    /// above the mean. AR(1) sits between the mean and the last value.
    func testFallingChargeStaysBetweenMeanAndLastValue() {
        let falling = (0..<14).map { 80.0 - 40.0 * Double($0) / 13.0 }
        let f = RecoveryForecaster.forecast(recentCharge: falling)!
        XCTAssertLessThan(f.charge, f.baseline)
        XCTAssertGreaterThanOrEqual(f.charge, falling.last!.rounded())
    }

    /// Alternating days have negative autocorrelation: φ clamps to 0, so the forecast is the mean.
    func testNegativeAutocorrelationFallsBackToTheMean() {
        let f = RecoveryForecaster.forecast(recentCharge: (0..<14).map { $0 % 2 == 0 ? 40.0 : 80.0 })!
        XCTAssertEqual(f.charge, 60)
    }

    func testThinBaselineWidensBandAndIsBuilding() {
        let f = RecoveryForecaster.forecast(recentCharge: Array(repeating: 60, count: 6))!
        XCTAssertEqual(f.band, RecoveryForecaster.minBandPoints + RecoveryForecaster.thinBandPoints)
        XCTAssertEqual(f.confidence, .building)
        XCTAssertNil(f.coverage)
    }

    /// With enough history the band is the measured error, and coverage is what a walk-forward replay
    /// found. A deterministic wobble: every error is known, so the band must match them.
    func testBandAndCoverageComeFromPastErrors() {
        let history = (0..<60).map { 60.0 + 20.0 * sin(Double($0) * 1.9) }
        let f = RecoveryForecaster.forecast(recentCharge: history)!
        XCTAssertEqual(f.confidence, .solid)
        var errors: [Double] = []
        for t in 14..<60 {
            errors.append(abs(RecoveryForecaster.point(Array(history[(t - 14)..<t])) - history[t]))
        }
        XCTAssertEqual(f.band, errors.sorted()[Int(0.8 * Double(errors.count))].rounded())
        XCTAssertEqual(f.coverageDays, errors.count - RecoveryForecaster.minResidualsForBand)
        XCTAssertNotNil(f.coverage)
        XCTAssertTrue((0...1).contains(f.coverage!))
    }

    func testOutOfRangeStaysClamped() {
        let f = RecoveryForecaster.forecast(recentCharge: Array(repeating: 100, count: 14))!
        XCTAssertLessThanOrEqual(f.high, 100)
        XCTAssertGreaterThanOrEqual(f.low, 0)
    }

    func testStatHelpers() {
        XCTAssertEqual(RecoveryForecaster.mean([1, 2, 3]), 2)
        XCTAssertEqual(RecoveryForecaster.sampleSD([2, 4]), 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(RecoveryForecaster.sampleSD([5]), 0)
    }

    func testClampPreservesInputSignedZeroAtInclusiveBounds() {
        XCTAssertEqual(RecoveryForecaster.clamp(-0.0, 0, 100).sign, .minus)
    }
}
