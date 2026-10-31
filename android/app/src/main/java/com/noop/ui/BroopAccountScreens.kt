package com.noop.ui

import android.text.format.Formatter
import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Backup
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Sensors
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.data.WhoopDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class BroopAccountSection(val key: String, @StringRes val titleRes: Int) {
    Profile("profile", R.string.broop_account_profile_information),
    HeartRate("heart_rate", R.string.broop_account_heart_rate_zones),
    Units("units", R.string.l10n_settings_screen_units_12748281),
    Appearance("appearance", R.string.l10n_settings_screen_appearance_41def7a0),
    Sleep("sleep", R.string.nav_sleep),
    Features("features", R.string.broop_account_features),
    Strap("strap", R.string.broop_account_strap_sync),
    Data("data", R.string.broop_account_backup_export),
    Scoring("scoring", R.string.broop_account_scoring),
    Experimental("experimental", R.string.broop_account_experimental),
    About("about", R.string.broop_account_about),
    Storage("storage", R.string.broop_account_storage),
    Integrations("integrations", R.string.broop_account_integrations),
    ShortcutsExport("shortcuts_export", R.string.broop_account_shortcuts_export),
    AndroidShortcuts("android_shortcuts", R.string.broop_account_android_shortcuts),
    MiBand("mi_band", R.string.broop_account_mi_band);

    val route: String get() = "account/$key"

    companion object {
        fun fromRoute(raw: String): BroopAccountSection? =
            entries.firstOrNull { it.key == raw.substringAfterLast('/') }
    }
}

@Composable
fun BroopSettingsScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val profile = remember { ProfileStore.from(context) }
    BroopPage(stringResource(R.string.broop_account_app_settings)) {
        BroopSection(stringResource(R.string.broop_account_account))
        BroopRow(stringResource(R.string.broop_account_profile_information),
            stringResource(R.string.broop_account_age, profile.age), Icons.Outlined.Person) { onNavigate(BroopAccountSection.Profile.route) }
        BroopRow(stringResource(R.string.broop_account_heart_rate_zones),
            stringResource(R.string.broop_account_max_hr, profile.hrMax), Icons.Outlined.FavoriteBorder) { onNavigate(BroopAccountSection.HeartRate.route) }
        BroopRow(stringResource(R.string.l10n_settings_screen_units_12748281),
            stringResource(if (UnitPrefs.system(context) == UnitSystem.IMPERIAL) R.string.broop_account_imperial else R.string.broop_account_metric),
            Icons.Outlined.Straighten) { onNavigate(BroopAccountSection.Units.route) }

        BroopSection(stringResource(R.string.more_group_app))
        BroopRow(stringResource(R.string.nav_notifications), icon = Icons.Outlined.Notifications) { onNavigate(Destination.Notifications.route) }
        BroopRow(stringResource(R.string.l10n_settings_screen_appearance_41def7a0),
            stringResource(R.string.broop_account_appearance_detail), Icons.Outlined.Palette) { onNavigate(BroopAccountSection.Appearance.route) }
        BroopRow(stringResource(R.string.nav_sleep), icon = Icons.Outlined.Bedtime) { onNavigate(BroopAccountSection.Sleep.route) }
        BroopRow(stringResource(R.string.broop_account_features), icon = Icons.Outlined.AutoAwesome) { onNavigate(BroopAccountSection.Features.route) }
        BroopRow(stringResource(R.string.broop_account_strap_sync),
            stringResource(R.string.broop_account_strap_detail), Icons.Outlined.Sensors) { onNavigate(BroopAccountSection.Strap.route) }
        BroopCard {
            BroopAccountToggle(stringResource(R.string.broop_account_classic_interface),
                stringResource(R.string.broop_account_classic_interface_detail), !BroopPrefs.enabled) {
                BroopPrefs.setEnabled(context, !it)
            }
        }

        BroopSection(stringResource(R.string.broop_account_privacy_group))
        BroopRow(stringResource(R.string.broop_account_backup_export), stringResource(R.string.broop_account_backup_detail), Icons.Outlined.Backup) { onNavigate(BroopAccountSection.Data.route) }
        BroopRow(stringResource(R.string.broop_account_storage), icon = Icons.Outlined.Storage) { onNavigate(BroopAccountSection.Storage.route) }
        BroopSection(stringResource(R.string.l10n_settings_screen_advanced_4d064726))
        BroopRow(stringResource(R.string.broop_account_scoring), stringResource(R.string.broop_account_scoring_detail), Icons.Outlined.Tune) { onNavigate(BroopAccountSection.Scoring.route) }
        BroopRow(stringResource(R.string.broop_account_experimental), icon = Icons.Outlined.Science) { onNavigate(BroopAccountSection.Experimental.route) }
        BroopRow(stringResource(R.string.nav_test_centre), stringResource(R.string.broop_account_diagnostics_detail), Icons.Outlined.BugReport) { onNavigate(Destination.TestCentre.route) }
        BroopSection(stringResource(R.string.broop_account_support))
        BroopRow(stringResource(R.string.broop_account_about), icon = Icons.Outlined.Info) { onNavigate(BroopAccountSection.About.route) }
    }
}

/** The editors retain their existing preference keys, permission gates, and export/restore actions. */
@Composable
fun BroopAccountDetailScreen(vm: AppViewModel, section: String, onNavigate: (String) -> Unit) {
    val selected = BroopAccountSection.fromRoute(section)
    when (selected) {
        BroopAccountSection.HeartRate -> BroopHeartRateSettingsScreen()
        BroopAccountSection.Sleep -> BroopSleepSettingsScreen()
        BroopAccountSection.Storage -> BroopStorageScreen(vm, onNavigate)
        BroopAccountSection.Integrations -> BroopIntegrationsScreen(vm, onNavigate)
        BroopAccountSection.AndroidShortcuts -> BroopAndroidShortcutsScreen(onNavigate)
        BroopAccountSection.ShortcutsExport,
        BroopAccountSection.MiBand -> BroopPlatformIntegrationScreen(selected, onNavigate)
        null -> BroopPage(stringResource(R.string.broop_account_app_settings)) {
            BroopEmpty(stringResource(R.string.broop_account_unknown_page), stringResource(R.string.broop_account_unknown_page_detail))
            BroopRow(stringResource(R.string.broop_account_app_settings), icon = Icons.Outlined.Settings) { onNavigate(Destination.Settings.route) }
        }
        else -> SettingsScreen(
            vm = vm,
            onOpenTestCentre = { onNavigate(Destination.TestCentre.route) },
            onOpenBackupSync = { onNavigate(Destination.BackupSync.route) },
            onOpenSelfHostedPush = { onNavigate(Destination.SelfHostedPush.route) },
            onOpenStepsCalibration = { onNavigate(Destination.StepsCalibration.route) },
            section = selected,
        )
    }
}

@Composable
fun BroopIntegrationsScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    BroopPage(stringResource(R.string.broop_account_integrations)) {
        BroopSection(stringResource(R.string.broop_account_connected_apps))
        BroopRow(stringResource(R.string.broop_account_health_connect),
            stringResource(R.string.broop_account_health_connect_detail), Icons.Outlined.FavoriteBorder) { onNavigate(Destination.AppleHealth.route) }
        BroopRow(stringResource(R.string.broop_account_mi_band),
            stringResource(R.string.broop_account_mi_band_detail), Icons.Outlined.Sensors) { onNavigate(BroopAccountSection.MiBand.route) }
        BroopSection(stringResource(R.string.broop_account_import_export))
        BroopRow(stringResource(R.string.nav_data_sources), stringResource(R.string.broop_account_data_sources_detail), Icons.Outlined.Storage) { onNavigate(Destination.DataSources.route) }
        BroopRow(stringResource(R.string.broop_account_shortcuts_export),
            stringResource(R.string.broop_account_shortcuts_export_detail), Icons.Outlined.Link) { onNavigate(BroopAccountSection.ShortcutsExport.route) }
        BroopRow(stringResource(R.string.broop_account_android_shortcuts), icon = Icons.Outlined.AutoAwesome) { onNavigate(BroopAccountSection.AndroidShortcuts.route) }
        BroopRow(stringResource(R.string.nav_backup_sync), icon = Icons.Outlined.CloudSync) { onNavigate(Destination.BackupSync.route) }
    }
}

@Composable
private fun BroopPlatformIntegrationScreen(section: BroopAccountSection, onNavigate: (String) -> Unit) {
    BroopPage(stringResource(section.titleRes)) {
        BroopCard {
            Text(stringResource(when (section) {
                BroopAccountSection.MiBand -> R.string.broop_account_mi_band_explanation
                BroopAccountSection.AndroidShortcuts -> R.string.broop_account_android_shortcuts_explanation
                else -> R.string.broop_account_shortcuts_explanation
            }), style = BroopType.body, color = BroopPalette.textBody)
        }
        if (section == BroopAccountSection.MiBand) {
            BroopRow(stringResource(R.string.broop_account_open_imports), icon = Icons.Outlined.Storage) { onNavigate(Destination.DataSources.route) }
        } else {
            BroopRow(stringResource(R.string.broop_account_health_connect), icon = Icons.Outlined.FavoriteBorder) { onNavigate(Destination.AppleHealth.route) }
            BroopRow(stringResource(R.string.broop_account_backup_export), icon = Icons.Outlined.Backup) { onNavigate(BroopAccountSection.Data.route) }
            BroopRow(stringResource(R.string.nav_automations), icon = Icons.Outlined.AutoAwesome) { onNavigate(Destination.Automations.route) }
        }
    }
}

@Composable
private fun BroopHeartRateSettingsScreen() {
    val context = LocalContext.current
    val profile = remember { ProfileStore.from(context) }
    var revision by remember { mutableIntStateOf(0) }
    fun mutate(block: () -> Unit) { block(); revision++ }
    BroopPage(stringResource(R.string.broop_account_heart_rate_zones)) {
        @Suppress("UNUSED_VARIABLE") val observedRevision = revision
        BroopCard {
            BroopAccountToggle(stringResource(R.string.broop_account_automatic_max_hr),
                stringResource(R.string.broop_account_max_hr, profile.hrMaxAuto), profile.hrMaxOverride == 0) {
                mutate { profile.hrMaxOverride = if (it) 0 else profile.hrMaxAuto }
            }
            if (profile.hrMaxOverride > 0) SettingsFormRow(stringResource(R.string.l10n_settings_screen_max_heart_rate_3d4ed858)) {
                StepperField(value = profile.hrMaxOverride.toString(), unit = "bpm",
                    accessibility = stringResource(R.string.broop_account_max_hr, profile.hrMax),
                    onMinus = { mutate { profile.hrMaxOverride = (profile.hrMaxOverride - 1).coerceAtLeast(0) } },
                    onPlus = { mutate { profile.hrMaxOverride = (profile.hrMaxOverride + 1).coerceAtMost(230) } })
            }
        }
        BroopCard {
            BroopAccountToggle(stringResource(R.string.l10n_settings_screen_custom_hr_zones_84736ca5),
                stringResource(R.string.l10n_settings_screen_custom_hr_zones_hint_f7fa3bae), profile.hasCustomHrZones) {
                mutate { profile.setCustomHrZonesEnabled(it) }
            }
            val thresholds = profile.hrZoneThresholds ?: com.noop.analytics.HrZones.defaultLowerBounds(profile.hrMax.toDouble())
            thresholds.forEachIndexed { index, value ->
                HorizontalDivider(color = BroopPalette.hairline)
                SettingsFormRow(stringResource(R.string.l10n_settings_screen_zone_starts_a0a60d45, index + 1)) {
                    if (profile.hasCustomHrZones) {
                        StepperField(value = value.toString(), unit = "bpm",
                            accessibility = stringResource(R.string.broop_account_zone_start, index + 1, value),
                            onMinus = { mutate { profile.stepHrZoneThreshold(index, false) } },
                            onPlus = { mutate { profile.stepHrZoneThreshold(index, true) } })
                    } else Text(stringResource(R.string.broop_account_bpm, value), style = BroopType.demi, color = BroopPalette.textBody)
                }
            }
        }
    }
}

@Composable
private fun BroopSleepSettingsScreen() {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(NoopPrefs.of(context).getBoolean("broop.sleep.preSleepHeartRate", false)) }
    BroopPage(stringResource(R.string.nav_sleep)) {
        BroopCard {
            BroopAccountToggle(stringResource(R.string.broop_account_pre_sleep_hr), stringResource(R.string.broop_account_pre_sleep_hr_detail), enabled) {
                enabled = it
                NoopPrefs.of(context).edit().putBoolean("broop.sleep.preSleepHeartRate", it).apply()
            }
        }
    }
}

@Composable
private fun BroopStorageScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val days by vm.recentDays.collectAsStateWithLifecycle()
    var rows by remember { mutableStateOf<Map<String, Int>?>(null) }
    var bytes by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(days) {
        rows = vm.repo.storageRowCounts()
        bytes = withContext(Dispatchers.IO) {
            val database = context.getDatabasePath(WhoopDatabase.DB_NAME)
            listOf(database, java.io.File(database.path + "-wal"), java.io.File(database.path + "-shm")).sumOf { it.length() }
        }
    }
    BroopPage(stringResource(R.string.broop_account_storage)) {
        BroopCard {
            Text(bytes?.let { Formatter.formatFileSize(context, it) } ?: stringResource(R.string.broop_account_loading),
                style = BroopType.number, color = BroopPalette.textPrimary)
            Text(stringResource(R.string.broop_account_storage_detail), style = BroopType.body, color = BroopPalette.textBody)
            if (rows != null) Text(stringResource(R.string.broop_account_stored_rows, rows!!.values.sum()), style = BroopType.demi, color = BroopPalette.textPrimary)
            rows?.forEach { (table, count) ->
                HorizontalDivider(color = BroopPalette.hairline)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(table, style = BroopType.caption, color = BroopPalette.textBody)
                    Text("%,d".format(count), style = BroopType.caption, color = BroopPalette.textPrimary)
                }
            }
        }
        BroopRow(stringResource(R.string.broop_account_backup_export), icon = Icons.Outlined.Backup) { onNavigate(BroopAccountSection.Data.route) }
        BroopRow(stringResource(R.string.nav_test_centre), icon = Icons.Outlined.BugReport) { onNavigate(Destination.TestCentre.route) }
    }
}

@Composable
internal fun BroopAccountToggle(title: String, detail: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
            Text(title, style = BroopType.demi, color = BroopPalette.textPrimary)
            if (detail.isNotEmpty()) Text(detail, style = BroopType.caption, color = BroopPalette.textBody)
        }
        Switch(checked = checked, onCheckedChange = onChange,
            modifier = Modifier.semantics { contentDescription = title },
            colors = SwitchDefaults.colors(checkedTrackColor = BroopPalette.teal,
                checkedThumbColor = BroopPalette.bgBottom, uncheckedTrackColor = BroopPalette.track,
                uncheckedThumbColor = BroopPalette.textBody, uncheckedBorderColor = BroopPalette.row))
    }
}
