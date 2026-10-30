package com.noop.analytics

import com.noop.data.HrSample

/** Recorded HR seconds, not wear, optical quality or activity-classification accuracy. */
data class HRInputCoverage(val recordedSeconds: Int, val expectedSeconds: Int, val longestGapSeconds: Int) {
    val fraction: Double get() = if (expectedSeconds > 0) recordedSeconds.toDouble() / expectedSeconds else 0.0
    // Conservative display policy, not a calibrated probability of accuracy.
    val isComplete: Boolean get() = fraction >= 0.95 && longestGapSeconds <= 300

    companion object {
        fun measure(samples: List<HrSample>, start: Long, endExclusive: Long): HRInputCoverage {
            val seconds = samples.asSequence().filter {
                it.ts >= start && it.ts < endExclusive && it.bpm in 25..250
            }.map { it.ts }.toSortedSet()
            var cursor = start
            var gap = 0L
            for (second in seconds) {
                gap = maxOf(gap, second - cursor)
                cursor = second + 1
            }
            return HRInputCoverage(seconds.size, maxOf(0L, endExclusive - start).toInt(),
                maxOf(gap, endExclusive - cursor).toInt())
        }
    }
}
