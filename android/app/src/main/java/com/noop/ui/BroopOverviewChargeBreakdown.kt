package com.noop.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.res.stringResource
import com.noop.R
import com.noop.analytics.ChargeBaselines
import com.noop.analytics.ChargeDriver
import com.noop.analytics.RecoveryDrivers
import com.noop.analytics.RestPerformanceV2
import com.noop.analytics.RestScorer
import com.noop.analytics.Baselines
import com.noop.analytics.VitalBands
import com.noop.data.DailyMetric
import java.util.Locale
import kotlin.math.abs

/** The repository-resolved Rest score, including Rest v2, is the sleep input used by Swift's wiring. */
internal fun broopChargeDrivers(baselines: ChargeBaselines.Resolved?, row: DailyMetric?, sleepPerformance: Double?): List<ChargeDriver> {
    val b = baselines ?: return emptyList()
    val day = row ?: return emptyList()
    val hrv = day.avgHrv ?: return emptyList()
    val rhr = day.restingHr?.toDouble() ?: return emptyList()
    if (!b.hrv.usable) return emptyList()
    return RecoveryDrivers.chargeDrivers(hrv = hrv, rhr = rhr, resp = day.respRateBpm,
        hrvBaseline = b.hrv, rhrBaseline = b.restingHR.takeIf { it.usable }, respBaseline = b.resp.takeIf { it.usable },
        sleepPerf = sleepPerformance?.div(100), skinTempDev = day.skinTempDevC)
}

/** Coupled and Charge breakdown use Repository.restScore(for:), including its unstored-row fallback. */
internal fun broopRestForRow(row: DailyMetric?, stored: Map<String, Double>, v2: Boolean): Double? {
    val day = row ?: return null
    return stored[day.day] ?: if (v2) RestPerformanceV2.composite(day) else RestScorer.restFromDaily(day)
}

internal fun broopSkinTemperatureTier(deviation: Double): Int = when {
    deviation > VitalBands.skinTempDeviationCfg.floorSpread -> R.string.broop_overview_skin_warmer
    deviation < -VitalBands.skinTempDeviationCfg.floorSpread -> R.string.broop_overview_skin_cooler
    else -> R.string.broop_overview_skin_typical
}

@Composable
internal fun BroopOverviewChargeBreakdown(
    snap: BroopOverviewSnapshot?, baselines: ChargeBaselines.Resolved?, sleepPerformance: Double?,
    onClose: () -> Unit, onHowCalculated: () -> Unit, onOpenTrend: (() -> Unit)? = null,
) {
    val row = snap?.carriedChargeDay ?: snap?.day
    val drivers = remember(baselines, row, sleepPerformance) { broopChargeDrivers(baselines, row, sleepPerformance) }
    BroopPage(stringResource(R.string.broop_overview_charge_breakdown), onBack = onClose) {
        if (drivers.isNotEmpty()) {
            BroopCard {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    BroopCaps(stringResource(R.string.today_what_shaped_it))
                    ChargeConfidencePill(chargeConfidenceTier(baselines, row))
                }
                val largest = drivers.maxOf { abs(it.deltaPoints) }.coerceAtLeast(1)
                drivers.forEach { driver ->
                    DriverRow(driver)
                    BroopDriverBar(driver.deltaPoints.toDouble() / largest)
                }
                row?.skinTempDevC?.let { deviation ->
                    Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
                        BroopCaps(stringResource(R.string.today_driver_skin_temperature), BroopPalette.warning)
                        Text(stringResource(broopSkinTemperatureTier(deviation)), style = BroopType.body, color = BroopPalette.textBody)
                        Text(stringResource(R.string.broop_overview_skin_relative, String.format(Locale.getDefault(), "%+.1f", deviation)),
                            style = BroopType.demi, color = BroopPalette.warning)
                    }
                }
                Text(stringResource(R.string.today_charge_driver_guidance), style = BroopType.caption, color = BroopPalette.textSecondary)
            }
        } else {
            snap?.calibrationNights?.let { banked -> BroopCard {
                Text(stringResource(R.string.broop_overview_calibration_remaining, maxOf(1, Baselines.minNightsSeed - banked)),
                    style = BroopType.demi, color = BroopPalette.textPrimary)
                Text(stringResource(R.string.broop_overview_calibration_unlock), style = BroopType.body, color = BroopPalette.textBody)
            } }
            BroopEmpty(stringResource(R.string.broop_overview_no_charge),
                snap?.calibrationNights?.let { stringResource(R.string.broop_overview_calibrating, it) }
                    ?: stringResource(R.string.broop_overview_coupled_no_breakdown))
        }
        onOpenTrend?.let { open -> BroopRow(stringResource(R.string.l10n_today_screen_see_the_charge_trend_9dcbcff7), onClick = open) }
        BroopRow(stringResource(R.string.today_action_how_charge), icon = Icons.Filled.Functions, onClick = onHowCalculated)
    }
}

@Composable
private fun BroopDriverBar(fraction: Double) {
    val track = BroopPalette.track
    val zero = BroopPalette.textSecondary
    val tint = if (fraction > 0) BroopPalette.bandHigh else if (fraction < 0) BroopPalette.bandLow else zero
    Canvas(Modifier.fillMaxWidth().height(BroopMetrics.gap)) {
        val middle = size.width / 2
        val width = middle * abs(fraction).coerceAtMost(1.0).toFloat()
        drawRect(track)
        if (width > 0) drawRect(tint, Offset(if (fraction >= 0) middle else middle - width, 0f), Size(width, size.height))
        drawLine(zero, Offset(middle, 0f), Offset(middle, size.height), BroopMetrics.ringStroke.toPx() / 3)
    }
}
