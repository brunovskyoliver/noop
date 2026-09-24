import XCTest
@testable import StrandAnalytics

final class VitalityEngineTests: XCTestCase {

    /// An average-for-their-age person nets ~0 hazard → Body Age == chronological age, Vitality 50.
    func testAveragePersonReadsAtTheirAge() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 65, vo2max: 45, expectedVO2max: 45,
            sleepHours: 7.5, sleepConsistency: 0.75, rmssd: 45, rmssdNorm: 45, steps: 7000))!
        XCTAssertEqual(r.bodyAge, 40, accuracy: 0.01)
        XCTAssertEqual(r.vitality, 50, accuracy: 0.01)
        XCTAssertEqual(r.deltaYears, 0, accuracy: 0.01)
        XCTAssertEqual(r.factorsUsed, 6)
    }

    /// A clearly healthy person reads younger + higher vitality. VO₂max (−0.39) dominates the fitness
    /// domain, so resting HR (−0.13) counts at half: Δage = 0.75·(−0.39 − 0.065 − 0.068 − 0.032 − 0.256)
    /// / (ln2/8) ≈ −7.02.
    func testHealthyPersonIsYounger() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 52, vo2max: 55.5, expectedVO2max: 45,
            sleepHours: 7.5, sleepConsistency: 0.9, rmssd: 54, rmssdNorm: 45, steps: 11000))!
        XCTAssertEqual(r.bodyAge, 32.98, accuracy: 0.01)
        XCTAssertEqual(r.vitality, 67.54, accuracy: 0.01)
        XCTAssertGreaterThan(r.deltaYears, 0)   // younger than chrono age
    }

    /// A clearly unhealthy person reads older + lower vitality. Resting HR (+0.15) sits under VO₂max (+0.39)
    /// in the fitness domain and counts at half: Δage ≈ +9.06.
    func testUnhealthyPersonIsOlder() {
        let r = VitalityEngine.compute(.init(
            chronoAge: 40, restingHR: 80, vo2max: 34.5, expectedVO2max: 45,
            sleepHours: 5.5, sleepConsistency: 0.5, rmssd: 31.5, rmssdNorm: 45, steps: 3000))!
        XCTAssertEqual(r.bodyAge, 49.06, accuracy: 0.01)
        XCTAssertEqual(r.vitality, 27.35, accuracy: 0.01)
        XCTAssertLessThan(r.deltaYears, 0)      // older than chrono age
    }

    /// Below the minimum-factor honesty gate → nil (don't show a number on too little data).
    func testNilBelowMinFactors() {
        XCTAssertNil(VitalityEngine.compute(.init(chronoAge: 40, restingHR: 65, sleepHours: 7.5))) // 2 factors
        XCTAssertNotNil(VitalityEngine.compute(.init(chronoAge: 40, restingHR: 65, sleepHours: 7.5,
                                                     sleepConsistency: 0.75)))                     // 3 factors
    }

    /// Body Age + Vitality stay within their clamped ranges at the extremes.
    func testClamps() {
        let young = VitalityEngine.compute(.init(
            chronoAge: 22, restingHR: 40, vo2max: 70, expectedVO2max: 40,
            sleepHours: 7.5, sleepConsistency: 1.0, rmssd: 90, rmssdNorm: 45, steps: 11000))!
        XCTAssertGreaterThanOrEqual(young.bodyAge, VitalityEngine.minBodyAge)
        XCTAssertLessThanOrEqual(young.vitality, 100)
        XCTAssertGreaterThanOrEqual(young.vitality, 0)

        let old = VitalityEngine.compute(.init(
            chronoAge: 85, restingHR: 110, vo2max: 12, expectedVO2max: 35,
            sleepHours: 3, sleepConsistency: 0.1, rmssd: 8, rmssdNorm: 30, steps: 200))!
        XCTAssertLessThanOrEqual(old.bodyAge, VitalityEngine.maxBodyAge)
        XCTAssertGreaterThanOrEqual(old.vitality, 0)
    }

    func testRmssdNormByAge() {
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 20), 47, accuracy: 0.01)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 40), 33, accuracy: 0.01)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 45), 31, accuracy: 0.01)   // halfway 33→29
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 90), 20, accuracy: 0.01)   // clamps to last anchor
    }

    func testSleepConsistency() {
        XCTAssertEqual(VitalityEngine.sleepConsistency(nightlyHours: [7, 7, 7, 7])!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.sleepConsistency(nightlyHours: [6, 8, 6, 8])!, 0.857, accuracy: 0.005)
        XCTAssertNil(VitalityEngine.sleepConsistency(nightlyHours: [7, 7]))   // < 3 nights
    }

    /// Contributions carry the right sign: a low resting HR is protective (negative), a high one ages you.
    func testContributionSigns() {
        let lowRHR = VitalityEngine.contributions(.init(chronoAge: 40, restingHR: 50))
            .first { $0.key == "rhr" }!
        XCTAssertLessThan(lowRHR.lnHazard, 0)
        let highRHR = VitalityEngine.contributions(.init(chronoAge: 40, restingHR: 85))
            .first { $0.key == "rhr" }!
        XCTAssertGreaterThan(highRHR.lnHazard, 0)
    }
}
