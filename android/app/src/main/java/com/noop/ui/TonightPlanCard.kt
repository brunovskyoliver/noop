package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.analytics.SleepPlanner
import kotlin.math.roundToInt

/**
 * Tonight's bedtime for all / most / the minimum of the sleep need ([AppViewModel.tonightPlan], built by
 * [SleepPlanner]). The same plan sets the caffeine cutoff and the wind-down reminder. Twin of the iOS
 * `TonightPlanCard`.
 */
@Composable
internal fun TonightPlanCard(vm: AppViewModel) {
    val plan by vm.tonightPlan.collectAsStateWithLifecycle()
    val days by vm.recentDays.collectAsStateWithLifecycle()
    LaunchedEffect(days) { vm.refreshTonightPlan() }
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.gap)) {
        SectionHeader(uiString(R.string.tonight_plan_title), overline = uiString(R.string.tonight_plan_overline))
        NoopCard(tint = Palette.restColor) {
            val p = plan
            if (p == null) {
                Text(uiString(R.string.tonight_plan_loading), style = NoopType.subhead, color = Palette.textTertiary)
            } else {
                TonightPlanContent(p)
            }
        }
    }
}

@Composable
private fun TonightPlanContent(plan: SleepPlanner.Plan) {
    val target = plan.target
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Overline(uiString(R.string.tonight_plan_bed_by))
            Text(clockLabel(target.bedMinute), style = NoopType.number(34f), color = Palette.textPrimary)
            Text(
                if (target.reachable) uiString(R.string.tonight_plan_full, hoursMinutes(plan.needMin))
                else uiString(R.string.tonight_plan_capped, hoursMinutes(target.expectedSleepMin)),
                style = NoopType.subhead, color = Palette.textSecondary,
            )
        }
        if (!target.reachable) {
            Text(uiString(R.string.tonight_plan_capped_note), style = NoopType.footnote, color = Palette.statusWarning)
        }
        plan.tiers.drop(1).forEach { tier ->
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    uiString(if (tier.fraction >= 0.8) R.string.tonight_plan_most else R.string.tonight_plan_minimum),
                    style = NoopType.footnote, color = Palette.textSecondary, modifier = Modifier.weight(1f),
                )
                Text(clockLabel(tier.bedMinute), style = NoopType.bodyNumber, color = Palette.textPrimary)
            }
        }
        HorizontalDivider(color = Palette.hairline)
        Row(modifier = Modifier.fillMaxWidth()) {
            listOf(
                uiString(R.string.tonight_plan_base) to hoursMinutes(plan.baseNeedMin),
                uiString(R.string.tonight_plan_debt) to "+" + hoursMinutes(plan.debtAddMin),
                uiString(R.string.tonight_plan_naps) to "−" + hoursMinutes(plan.napSubMin),
                uiString(R.string.tonight_plan_wake) to clockLabel(plan.wakeMinute),
            ).forEach { (label, value) ->
                Column(modifier = Modifier.weight(1f)) {
                    Overline(label, color = Palette.textTertiary)
                    Text(value, style = NoopType.bodyNumber, color = Palette.textPrimary)
                }
            }
        }
        Text(
            uiString(R.string.tonight_plan_assumes, (plan.efficiency * 100).roundToInt(), plan.latencyMin.roundToInt()),
            style = NoopType.footnote, color = Palette.textTertiary,
        )
    }
}
