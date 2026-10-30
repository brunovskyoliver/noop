package com.noop.analytics

import com.noop.data.MetricSeriesRow
import com.noop.data.SleepSession
import com.noop.data.DailyMetric

/** Stored witnesses from the nightly pass, kept outside the scoring coroutine's bytecode budget. */
internal object NightScoreRows {
    fun accuracyInputs(computedId: String, result: DayResult): List<MetricSeriesRow> = buildList {
        result.hrCoverage?.let { coverage ->
            add(MetricSeriesRow(computedId, result.daily.day, "hr_day_coverage", coverage.fraction))
            add(MetricSeriesRow(computedId, result.daily.day, "hr_day_longest_gap_s", coverage.longestGapSeconds.toDouble()))
        }
        result.activeEnergyKcal?.let { add(MetricSeriesRow(computedId, result.daily.day, "active_energy_kcal", it)) }
    }

    fun computedDay(daily: DailyMetric): IntelligenceEngine.Computed = IntelligenceEngine.Computed(
        day = daily.day,
        recovery = daily.recovery,
        strain = daily.strain,
        sleepMin = daily.totalSleepMin,
        hrv = daily.avgHrv,
        rhr = daily.restingHr,
    )

    fun witnesses(day: String, computedId: String, spo2Candidate: Int?, hrvOverCount: Boolean?,
        primarySessionRHR: Double?, coverage: PrimarySessionRestingHR.Coverage?): List<MetricSeriesRow> = buildList {
        // #103: persist the SpO₂ candidate @82 nightly mean to metricSeries as "spo2_candidate" so the
        // Blood Oxygen tile can surface it as a "strap estimate (unverified)" fallback when the toggle
        // is ON. Written under the "-noop" computed device ID, never to `spo2Pct`.
        spo2Candidate?.let { cand ->
            add(MetricSeriesRow(deviceId = computedId, day = day, key = "spo2_candidate", value = cand.toDouble()))
        }
        // #1118: persist the HRV over-count flag (1/0) so the HRV card can mark an over-counted 4.0
        // night's reading "unverified" until the two-channel de-dup lands. 0 written on a clean night
        // (not just absent) so a night that flips clean on re-score clears its prior flag.
        hrvOverCount?.let { oc ->
            add(MetricSeriesRow(deviceId = computedId, day = day, key = "hrv_rr_overcount", value = if (oc) 1.0 else 0.0))
        }
        // #1169 shadow metric: the primary-session mean RHR, stored beside the shipped floor
        // (daily.restingHr) under the "-noop" computed ID. Instrumentation only — never shown, never
        // scored — for later mean-vs-floor evaluation from exports.
        primarySessionRHR?.let { v ->
            add(MetricSeriesRow(deviceId = computedId, day = day, key = "rhr_primary_session", value = v))
        }
        // #1169: its coverage inputs beside the mean — valid-sample count + primary-session duration (s)
        // — so a thin-coverage night can be down-weighted in the later holdout. Raw inputs, not a fraction.
        coverage?.let { cov ->
            add(MetricSeriesRow(deviceId = computedId, day = day, key = "rhr_primary_session_valid_samples", value = cov.validSamples.toDouble()))
            add(MetricSeriesRow(deviceId = computedId, day = day, key = "rhr_primary_session_duration_s", value = cov.durationSec))
        }

    }
    /** Keep the detector's recorded fields and sparse-coverage flag together in the cached row. */
    fun cachedSleep(computedId: String, result: DayResult): List<SleepSession> = result.sleepSessions.map { session ->
        SleepSession(deviceId = computedId, startTs = session.start, endTs = session.end,
            efficiency = session.efficiency, restingHr = session.restingHR, avgHrv = session.avgHRV,
            stagesJSON = AnalyticsEngine.encodeStages(session.stages), stagingSparse = result.gravitySparse)
    }

}
