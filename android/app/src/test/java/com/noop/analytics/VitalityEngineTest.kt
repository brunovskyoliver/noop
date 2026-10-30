package com.noop.analytics

import org.junit.Assert.*
import org.junit.Test

class VitalityEngineTest {
    private fun neutral(age: Double = 40.0, sex: String = "male"): VitalityEngine.Inputs {
        var inputs = VitalityEngine.Inputs(age, sex)
        for (factor in VitalityEngine.Factor.entries) inputs = inputs.setting(factor, VitalityEngine.target(factor, age, sex))
        return inputs
    }

    @Test fun meetingEveryRecommendationReadsChronologicalAge() {
        for (age in listOf(22.0, 30.0, 47.5, 63.0, 80.0)) for (sex in listOf("male", "female", "")) {
            val result = VitalityEngine.compute(neutral(age, sex))!!
            assertEquals(age, result.bodyAge, 0.0)
            assertEquals(50.0, result.vitality, 0.0)
            assertEquals(9, result.factorsUsed)
            assertTrue(result.impacts.all { it.years == 0.0 })
        }
    }

    @Test fun missingInputsHaveNoImpactAndDoNotCountTowardGate() {
        val input = VitalityEngine.Inputs(40.0, sleepHours = 7.0, restingHR = 60.0)
        assertNull(VitalityEngine.compute(input))
        assertNull(VitalityEngine.compute(input.copy(chronoAge = 0.0, steps = 8000.0)))
        val result = VitalityEngine.compute(input.copy(steps = 8000.0))!!
        assertEquals(3, result.factorsUsed)
        assertEquals(9, result.impacts.size)
        assertTrue(result.impacts.firstOrNull { it.factor == VitalityEngine.Factor.LEAN_MASS }!!.isMissing)
        assertEquals(0.0, result.impacts.firstOrNull { it.factor == VitalityEngine.Factor.LEAN_MASS }!!.years, 0.0)
    }

    @Test fun overlapCountsLargerImpactInFullAndSmallerAtPointSeven() {
        val result = VitalityEngine.compute(neutral(30.0).copy(vo2max = 37.0, restingHR = 70.0))!!
        assertEquals(1.0, result.impacts.firstOrNull { it.factor == VitalityEngine.Factor.VO2MAX }!!.adjustment, 0.0)
        assertEquals(0.7, result.impacts.firstOrNull { it.factor == VitalityEngine.Factor.RHR }!!.adjustment, 0.0)
        assertEquals(result.impacts.sumOf { it.years }, result.ageDelta, 1e-12)
        assertEquals(result.bodyAge - result.chronoAge, result.ageDelta, 0.0)
    }

    @Test fun derivedVitalityUsesClampedAgeDelta() {
        val low = VitalityEngine.compute(neutral(18.0).copy(sleepConsistency = 100.0, vo2max = 100.0))!!
        assertEquals(18.0, low.bodyAge, 0.0)
        assertEquals(50.0, low.vitality, 0.0)
        val high = VitalityEngine.compute(neutral(100.0).copy(sleepHours = 2.0, restingHR = 150.0))!!
        assertEquals(100.0, high.bodyAge, 0.0)
        assertEquals(50.0, high.vitality, 0.0)
    }

    @Test fun legacyDurationRegularityRemainsSeparateFromHealthspanPercent() {
        assertEquals(1.0, VitalityEngine.sleepConsistency(listOf(7.0, 7.0, 7.0))!!, 0.0)
        assertEquals(0.8571428571428572, VitalityEngine.sleepConsistency(listOf(6.0, 8.0, 6.0, 8.0))!!, 1e-15)
        assertNull(VitalityEngine.sleepConsistency(listOf(7.0, 7.0)))
        assertEquals(70.0, VitalityEngine.target(VitalityEngine.Factor.SLEEP_CONSISTENCY, 40.0, "male"), 0.0)
    }
}
