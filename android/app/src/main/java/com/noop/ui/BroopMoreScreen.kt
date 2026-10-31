package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.CompareArrows
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.Air
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.BatteryStd
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.FitnessCenter
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.HealthAndSafety
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Spa
import androidx.compose.material.icons.outlined.Timeline
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.BuildConfig
import com.noop.R

@Composable
fun BroopMoreScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val profile = remember { ProfileStore.from(context) }
    val streaks by vm.streaks.collectAsStateWithLifecycle()
    val coachEnabled = NoopPrefs.coachEnabled(context)
    BroopPage(stringResource(R.string.nav_more)) {
        BroopCard(onClick = { onNavigate(BroopAccountSection.Profile.route) }) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(BroopMetrics.page),
            ) {
                ProfileAvatar(size = BroopMetrics.barHeight, contentDescription = null)
                Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
                    Text(stringResource(R.string.broop_account_my_profile), style = BroopType.demi, color = BroopPalette.textPrimary)
                    val sex = stringResource(when (profile.sex) {
                        "female" -> R.string.broop_account_female
                        "nonbinary" -> R.string.broop_account_nonbinary
                        else -> R.string.broop_account_male
                    })
                    Text(
                        stringResource(R.string.broop_account_profile_summary, profile.age, sex,
                            UnitFormatter.massFromKilograms(profile.weightKg, UnitPrefs.system(context))),
                        style = BroopType.caption,
                        color = BroopPalette.textBody,
                    )
                    if (streaks.current > 0) Text(
                        stringResource(R.string.broop_account_streak, streaks.current),
                        style = BroopType.caption, color = BroopPalette.warning,
                    )
                }
            }
        }
        if (coachEnabled) BroopRow(
            stringResource(R.string.nav_coach), stringResource(R.string.broop_account_coach_detail), Icons.Outlined.AutoAwesome,
        ) { onNavigate(Destination.Coach.route) }
        if (LiveSessionPrefs.enabled(context)) BroopRow(
            stringResource(R.string.broop_account_live_session), stringResource(R.string.broop_account_live_session_detail), Icons.Outlined.MonitorHeart,
        ) { onNavigate("live_session") }

        BroopSection(stringResource(R.string.broop_account_day_activity))
        BroopRow(stringResource(R.string.nav_trends), icon = Icons.AutoMirrored.Outlined.TrendingUp) { onNavigate(Destination.Trends.route) }
        BroopRow(stringResource(R.string.nav_sleep), icon = Icons.Outlined.Bedtime) { onNavigate(Destination.Sleep.route) }
        BroopRow(stringResource(R.string.broop_account_live_hr), icon = Icons.Outlined.MonitorHeart) { onNavigate(Destination.Live.route) }
        BroopRow(stringResource(R.string.nav_workouts), icon = Icons.Outlined.FitnessCenter) { onNavigate(Destination.Workouts.route) }
        BroopRow(stringResource(R.string.broop_account_lift_log), icon = Icons.Outlined.FitnessCenter) { onNavigate("lift_log") }
        BroopRow(stringResource(R.string.nav_breathe), icon = Icons.Outlined.Air) { onNavigate(Destination.Breathe.route) }
        BroopRow(stringResource(R.string.nav_intervals), icon = Icons.Outlined.Timer) { onNavigate(Destination.Intervals.route) }
        BroopRow(stringResource(R.string.nav_alarms), icon = Icons.Outlined.Alarm) { onNavigate(Destination.SmartAlarm.route) }

        BroopSection(stringResource(R.string.more_group_insights))
        BroopRow(stringResource(R.string.nav_insights_hub), icon = Icons.Outlined.AutoAwesome) { onNavigate(Destination.InsightsHub.route) }
        BroopRow(stringResource(R.string.nav_intelligence), icon = Icons.Outlined.Psychology) { onNavigate(Destination.Intelligence.route) }
        BroopRow(stringResource(R.string.broop_account_journal), icon = Icons.Outlined.Edit) { onNavigate(Destination.Insights.route) }
        BroopRow(stringResource(R.string.nav_explore), icon = Icons.Outlined.GridView) { onNavigate(Destination.Explore.route) }
        BroopRow(stringResource(R.string.nav_compare), icon = Icons.AutoMirrored.Outlined.CompareArrows) { onNavigate(Destination.Compare.route) }
        BroopRow(stringResource(R.string.nav_fused_record), icon = Icons.Outlined.Timeline) { onNavigate(Destination.FusedRecord.route) }

        BroopSection(stringResource(R.string.more_group_body))
        BroopRow(stringResource(R.string.nav_health), icon = Icons.Outlined.HealthAndSafety) { onNavigate("health_hub") }
        BroopRow(stringResource(R.string.nav_stress), icon = Icons.Outlined.Spa) { onNavigate(Destination.Stress.route) }
        BroopRow(stringResource(R.string.nav_lab_book), icon = Icons.Outlined.HealthAndSafety) { onNavigate(Destination.LabBook.route) }
        BroopRow(stringResource(R.string.nav_rhythm), icon = Icons.Outlined.MonitorHeart) { onNavigate(Destination.Rhythm.route) }

        BroopSection(stringResource(R.string.broop_account_settings_group))
        BroopRow(stringResource(R.string.broop_account_devices), icon = Icons.Outlined.Sensors) { onNavigate(Destination.Devices.route) }
        BroopRow(stringResource(R.string.broop_account_app_settings), icon = Icons.Outlined.Settings) { onNavigate(Destination.Settings.route) }
        BroopRow(stringResource(R.string.broop_account_integrations), stringResource(R.string.broop_account_integrations_detail), Icons.Outlined.Link) { onNavigate(BroopAccountSection.Integrations.route) }
        BroopRow(stringResource(R.string.nav_backup_sync), icon = Icons.Outlined.CloudSync) { onNavigate(Destination.BackupSync.route) }
        BroopRow(stringResource(R.string.nav_automations), icon = Icons.Outlined.Bolt) { onNavigate(Destination.Automations.route) }
        BroopRow(stringResource(R.string.nav_power_saving), icon = Icons.Outlined.BatteryStd) { onNavigate(Destination.PowerSaving.route) }

        BroopSection(stringResource(R.string.broop_account_support))
        BroopRow(stringResource(R.string.nav_test_centre), stringResource(R.string.broop_account_diagnostics_detail), Icons.Outlined.BugReport) { onNavigate(Destination.TestCentre.route) }
        BroopRow(stringResource(R.string.nav_noop_limitations), icon = Icons.Outlined.Info) { onNavigate(Destination.NoopLimitations.route) }
        BroopRow(stringResource(R.string.broop_account_classic_today), icon = Icons.Outlined.Explore) { onNavigate("classic_today") }
        BroopRow(stringResource(R.string.broop_account_about), icon = Icons.Outlined.Info) { onNavigate(BroopAccountSection.About.route) }
        Spacer(Modifier.height(BroopMetrics.section))
        Text(
            stringResource(R.string.broop_account_version, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE),
            style = BroopType.caps, color = BroopPalette.textBody, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(stringResource(R.string.broop_onboarding_brand), style = BroopType.wordmark, color = BroopPalette.textPrimary,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
    }
}
