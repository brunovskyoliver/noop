package com.noop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.noop.R
import com.noop.analytics.ReadinessEngine
import java.util.Locale

@Composable
internal fun BroopOverviewReadinessDetails(snap: BroopOverviewSnapshot?) {
    BroopCard {
        BroopCaps(stringResource(R.string.broop_overview_readiness))
        val readiness = snap?.readiness
        if (readiness == null || readiness.level == ReadinessEngine.Level.INSUFFICIENT) {
            Text(stringResource(R.string.broop_overview_no_charge), style = BroopType.body, color = BroopPalette.textBody)
        } else {
            Text(broopReadinessCopy(readiness.headlineRes), style = BroopType.section, color = BroopPalette.textPrimary)
            Text(broopReadinessCopy(readiness.summaryRes), style = BroopType.body, color = BroopPalette.textBody)
            readiness.signals.forEach { signal ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
                    androidx.compose.foundation.layout.Box(Modifier.size(BroopMetrics.compactGap).background(when (signal.flag) {
                        ReadinessEngine.Flag.GOOD -> BroopPalette.teal
                        ReadinessEngine.Flag.WATCH -> BroopPalette.warning
                        ReadinessEngine.Flag.BAD -> BroopPalette.bandLow
                        ReadinessEngine.Flag.NEUTRAL -> BroopPalette.textSecondary
                    }, CircleShape))
                    Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
                        Text(broopReadinessCopy(signal.labelRes), style = BroopType.demi, color = BroopPalette.textPrimary)
                        Text(broopReadinessSignalDetail(signal), style = BroopType.body, color = BroopPalette.textBody)
                        signal.evidence?.let { Text(broopReadinessEvidenceText(it), style = BroopType.caption, color = BroopPalette.textSecondary) }
                    }
                }
            }
        }
    }
}

@Composable
private fun broopReadinessEvidenceText(evidence: ReadinessEngine.Evidence): String {
    fun number(value: Double, decimals: Int): String = if (decimals == 0) {
        Math.round(value).toString()
    } else {
        String.format(Locale.getDefault(), "%.${decimals}f", value)
    }
    return when (evidence) {
        is ReadinessEngine.Evidence.MetricVsBaseline -> {
            val unit = when (evidence.unit) {
                ReadinessEngine.MetricUnit.MS -> uiString(R.string.today_unit_ms)
                ReadinessEngine.MetricUnit.BPM -> uiString(R.string.today_unit_bpm)
                ReadinessEngine.MetricUnit.RPM -> uiString(R.string.today_unit_rpm)
            }
            uiString(
                R.string.today_readiness_evidence_metric,
                number(evidence.value, evidence.decimals), number(evidence.baseline, evidence.decimals), unit,
            )
        }
        is ReadinessEngine.Evidence.Monotony ->
            uiString(R.string.today_readiness_evidence_monotony, number(evidence.value, 1))
        is ReadinessEngine.Evidence.TrainingLoad ->
            uiString(
                R.string.today_readiness_evidence_load,
                number(evidence.acute, 1), number(evidence.chronic, 1),
            )
    }
}

@Composable
private fun broopReadinessCopy(copy: ReadinessEngine.Copy): String = uiString(
    when (copy) {
        ReadinessEngine.Copy.TODAY_READINESS_BALANCED -> R.string.today_readiness_balanced
        ReadinessEngine.Copy.TODAY_READINESS_BALANCED_SUMMARY -> R.string.today_readiness_balanced_summary
        ReadinessEngine.Copy.TODAY_READINESS_HRV_BAD -> R.string.today_readiness_hrv_bad
        ReadinessEngine.Copy.TODAY_READINESS_HRV_GOOD -> R.string.today_readiness_hrv_good
        ReadinessEngine.Copy.TODAY_READINESS_HRV_WATCH -> R.string.today_readiness_hrv_watch
        ReadinessEngine.Copy.TODAY_READINESS_LOAD_BUILDING_FAST -> R.string.today_readiness_load_building_fast
        ReadinessEngine.Copy.TODAY_READINESS_LOAD_RAMPING_DOWN -> R.string.today_readiness_load_ramping_down
        ReadinessEngine.Copy.TODAY_READINESS_LOAD_SPIKING -> R.string.today_readiness_load_spiking
        ReadinessEngine.Copy.TODAY_READINESS_LOAD_SWEET_SPOT -> R.string.today_readiness_load_sweet_spot
        ReadinessEngine.Copy.TODAY_READINESS_MONOTONY_WATCH -> R.string.today_readiness_monotony_watch
        ReadinessEngine.Copy.TODAY_READINESS_MORE_NIGHTS -> R.string.today_readiness_more_nights
        ReadinessEngine.Copy.TODAY_READINESS_NORMAL_RANGE -> R.string.today_readiness_normal_range
        ReadinessEngine.Copy.TODAY_READINESS_PRIMED -> R.string.today_readiness_primed
        ReadinessEngine.Copy.TODAY_READINESS_PRIMED_SUMMARY -> R.string.today_readiness_primed_summary
        ReadinessEngine.Copy.TODAY_READINESS_RESP_BAD -> R.string.today_readiness_resp_bad
        ReadinessEngine.Copy.TODAY_READINESS_RESP_WATCH -> R.string.today_readiness_resp_watch
        ReadinessEngine.Copy.TODAY_READINESS_RHR_BAD -> R.string.today_readiness_rhr_bad
        ReadinessEngine.Copy.TODAY_READINESS_RHR_GOOD -> R.string.today_readiness_rhr_good
        ReadinessEngine.Copy.TODAY_READINESS_RHR_WATCH -> R.string.today_readiness_rhr_watch
        ReadinessEngine.Copy.TODAY_READINESS_RUN_DOWN -> R.string.today_readiness_run_down
        ReadinessEngine.Copy.TODAY_READINESS_RUN_DOWN_SUMMARY -> R.string.today_readiness_run_down_summary
        ReadinessEngine.Copy.TODAY_READINESS_SIGNAL_HRV -> R.string.today_readiness_signal_hrv
        ReadinessEngine.Copy.TODAY_READINESS_SIGNAL_RESPIRATORY -> R.string.today_readiness_signal_respiratory
        ReadinessEngine.Copy.TODAY_READINESS_SIGNAL_RESTING_HR -> R.string.today_readiness_signal_resting_hr
        ReadinessEngine.Copy.TODAY_READINESS_SIGNAL_TRAINING_LOAD -> R.string.today_readiness_signal_training_load
        ReadinessEngine.Copy.TODAY_READINESS_SIGNAL_TRAINING_VARIETY -> R.string.today_readiness_signal_training_variety
        ReadinessEngine.Copy.TODAY_READINESS_STRAINED -> R.string.today_readiness_strained
        ReadinessEngine.Copy.TODAY_READINESS_STRAINED_SUMMARY -> R.string.today_readiness_strained_summary
        ReadinessEngine.Copy.TODAY_READINESS_TITLE -> R.string.today_readiness_title
        ReadinessEngine.Copy.TODAY_READINESS_WEAR_FOR_NIGHTS -> R.string.today_readiness_wear_for_nights
    },
)

@Composable
private fun broopReadinessSignalDetail(signal: ReadinessEngine.Signal): String {
    val load = signal.evidence as? ReadinessEngine.Evidence.TrainingLoad
    return if (load != null && load.chronic > 0.0) {
        uiString(
            when (signal.detailRes) {
                ReadinessEngine.Copy.TODAY_READINESS_LOAD_RAMPING_DOWN -> R.string.today_readiness_load_ramping_down
                ReadinessEngine.Copy.TODAY_READINESS_LOAD_SWEET_SPOT -> R.string.today_readiness_load_sweet_spot
                ReadinessEngine.Copy.TODAY_READINESS_LOAD_BUILDING_FAST -> R.string.today_readiness_load_building_fast
                ReadinessEngine.Copy.TODAY_READINESS_LOAD_SPIKING -> R.string.today_readiness_load_spiking
                else -> error("Training-load evidence requires a training-load detail")
            },
            String.format(Locale.getDefault(), "%.2f", load.acute / load.chronic),
        )
    } else {
        broopReadinessCopy(signal.detailRes)
    }
}

