package com.noop.ui

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Timer
import androidx.compose.ui.platform.testTag
import com.noop.BuildConfig
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.noop.R
import com.noop.push.SelfHostedPushScreen

/** Stable entry points shared by the shell, quick actions and the iOS parity inventory. */
internal object BroopNavigation {
    val tabs = listOf("today", "health_hub", "more")
    val routes = setOf(
        "today", "health_hub", "more", "sleep", "score/{score}", "full_day_chart", "coupled_view",
        "workouts", "activity", "live", "lift_log", "breathe", "intervals", "health", "stress",
        "lab_book", "rhythm", "explore", "trends", "hydration", "compare", "healthspan", "mind",
        "energy", "jet_lag", "vital_detail/{key}", "vital_signs", "insights", "insights_hub",
        "intelligence", "fused_record", "coach", "coach_settings", "smart_alarm", "settings",
        "devices", "apple_health", "mi_band", "data_sources", "backup_sync", "shortcuts_export",
        "noop_limitations", "automations", "android_shortcuts", "power_saving", "test_centre",
        "classic_today", "live_session", "lift_active", "integrations", "account/{section}", "notifications",
        "steps_calibration", "self_hosted_push", "ground_truth_collector", "journal_insights",
    )

    /** Platform equivalents are explicit so new Swift destinations cannot silently disappear. */
    val swiftDestinations = mapOf(
        "sleep" to "sleep", "fullDayChart" to "full_day_chart", "coupled" to "coupled_view",
        "workouts" to "workouts", "live" to "live", "liftLog" to "lift_log", "breathe" to "breathe",
        "intervals" to "intervals", "health" to "health", "stress" to "stress", "labBook" to "lab_book",
        "rhythm" to "rhythm", "metricExplorer" to "explore", "trends" to "trends", "hydration" to "hydration",
        "compare" to "compare", "healthspan" to "healthspan", "mind" to "mind", "energy" to "energy",
        "jetLag" to "jet_lag", "metric" to "vital_detail/{key}", "journal" to "insights",
        "insightsHub" to "insights_hub", "intelligence" to "intelligence", "fusedRecord" to "fused_record",
        "coach" to "coach", "alarms" to "smart_alarm", "settings" to "settings", "devices" to "devices",
        "appleHealth" to "apple_health", "miBand" to "mi_band", "dataSources" to "data_sources",
        "backupSync" to "backup_sync", "shortcutsExport" to "shortcuts_export", "noopLimitations" to "noop_limitations",
        "automations" to "automations", "siriShortcuts" to "android_shortcuts", "powerSaving" to "power_saving",
        "testCentre" to "test_centre", "classicToday" to "classic_today",
    )

    fun ownsRoute(route: String): Boolean = route in routes || routes.any { pattern ->
        pattern.contains('{') && pattern.substringBefore('{') == route.substringBeforeLast('/') + "/"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BroopAppRoot(vm: AppViewModel, initialRoute: String = "today") {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    val route = entry?.destination?.route ?: "today"
    val context = LocalContext.current
    val planDays by vm.recentDays.collectAsStateWithLifecycle()
    LaunchedEffect(route, planDays, vm.activeStrapId) { vm.refreshTonightPlan() }
    var quickActions by remember { mutableStateOf(false) }
    var startActivity by remember { mutableStateOf(false) }
    var addActivity by remember { mutableStateOf(false) }
    var inbox by remember { mutableStateOf(false) }
    var whatsNew by remember { mutableStateOf(false) }
    val updateStore = remember(context) { UpdateStore.from(context) }
    var selectedTab by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("today") }
    LaunchedEffect(route) { if (route in BroopNavigation.tabs) selectedTab = route }
    val navigate: (String) -> Unit = { requested ->
        when (requested) {
            "start_activity" -> startActivity = true
            "add_activity" -> addActivity = true
            "quick_actions" -> quickActions = true
            else -> {
                require(BroopNavigation.ownsRoute(requested)) { "Unknown Broop destination: $requested" }
                nav.navigate(requested) { launchSingleTop = true }
            }
        }
    }
    LaunchedEffect(Unit) {
        NoopRouteBus.workoutDetected.collect { pending ->
            if (pending != null && nav.currentDestination?.route != "workouts") {
                nav.navigate("workouts") { launchSingleTop = true }
            }
        }
    }
    LaunchedEffect(nav) {
        NoopRouteBus.resumeLift.collect { pending ->
            if (pending) {
                nav.navigate("lift_active") { launchSingleTop = true }
                NoopRouteBus.consumeLiftResume()
            }
        }
    }
    // The native bar owns the navigation inset. Existing scrolling editors use the measured content clearance.
    LaunchedEffect(Unit) { BottomBarStyleStore.barHeight = 0.dp }
    Scaffold(
        containerColor = BroopPalette.bgTop,
        bottomBar = {
            Column {
                BroopLiftMiniBar(vm) { navigate("lift_active") }
            Row(
                Modifier.fillMaxWidth().background(BroopPalette.bgBottom).navigationBarsPadding(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                NavigationBar(
                    modifier = Modifier.weight(1f), containerColor = BroopPalette.bgBottom,
                    contentColor = BroopPalette.textPrimary,
                    windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0),
                ) {
                    listOf(
                        Triple("today", R.string.broop_home, Icons.Filled.Home),
                        Triple("health_hub", R.string.broop_health, Icons.Filled.FavoriteBorder),
                        Triple("more", R.string.nav_more, Icons.Filled.Menu),
                    ).forEach { (target, label, icon) ->
                        NavigationBarItem(
                            selected = selectedTab == target,
                            onClick = {
                                selectedTab = target
                                nav.navigate(target) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(icon, null) },
                            label = { Text(stringResource(label), style = BroopType.tab) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = BroopPalette.textPrimary,
                                selectedTextColor = BroopPalette.textPrimary,
                                unselectedIconColor = BroopPalette.textSecondary,
                                unselectedTextColor = BroopPalette.textSecondary,
                                indicatorColor = BroopPalette.pillOuter,
                            ),
                        )
                    }
                }
                IconButton(onClick = { quickActions = true }, modifier = Modifier.size(BroopMetrics.touch).testTag("broop.quickActions")) {
                    Icon(Icons.Filled.Add, stringResource(R.string.broop_quick_actions), tint = BroopPalette.textPrimary)
                }
            }
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).background(BroopPalette.background)) {
            if (BuildConfig.ENABLE_DEMO) {
                Text(stringResource(R.string.broop_demo), style = BroopType.caption, color = BroopPalette.textSecondary,
                    modifier = Modifier.fillMaxWidth().background(BroopPalette.pillOuter).padding(horizontal = BroopMetrics.page, vertical = BroopMetrics.compactGap))
            }
            if (route !in BroopNavigation.tabs) {
                Row(Modifier.fillMaxWidth().height(BroopMetrics.touch), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { nav.popBackStack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, null, modifier = Modifier.size(BroopMetrics.smallIcon))
                        Text(stringResource(R.string.broop_back), style = BroopType.demi)
                    }
                }
            }
            NavHost(
                navController = nav, startDestination = initialRoute, modifier = Modifier.weight(1f),
                enterTransition = { fadeIn(tween(Motion.durationFast)) },
                exitTransition = { fadeOut(tween(Motion.durationFast)) },
                popEnterTransition = { fadeIn(tween(Motion.durationFast)) },
                popExitTransition = { fadeOut(tween(Motion.durationFast)) },
            ) {
                composable("today") { BroopHomeScreen(vm, navigate, onQuickActions = { quickActions = true }) }
                composable("health_hub") { BroopHealthHubScreen(vm, navigate) }
                composable("more") { BroopMoreScreen(vm, navigate) }
                composable("sleep") { BroopSleepScreen(vm, navigate) }
                composable("score/{score}") { BroopScoreScreen(vm, it.arguments?.getString("score") ?: "charge", navigate) }
                composable("full_day_chart") { BroopOverviewDayChartScreen(vm) }
                composable("coupled_view") { BroopOverviewCoupledScreen(vm, navigate) }
                composable("activity") { BroopActivityScreen(vm, navigate) }
                composable("workouts") { WorkoutsScreen(vm) }
                composable("live") { LiveScreen(vm, onManageDevices = { navigate("devices") }) }
                composable("lift_log") { BroopLiftLogScreen(vm) }
                composable("lift_active") { BroopLiftLogScreen(vm, autoResume = true) }
                composable("breathe") { BreatheScreen(vm) }
                composable("intervals") { IntervalsScreen(vm) }
                composable("health") {
                    HealthScreen(vm, onVitalClick = { navigate("vital_detail/$it") },
                        onOpenLabBook = { navigate("lab_book") }, onOpenFusedRecord = { navigate("fused_record") },
                        onOpenSettings = { navigate("settings") })
                }
                composable("stress") { BroopStressScreen(vm, navigate) }
                composable("lab_book") { LabBookScreen(vm) }
                composable("rhythm") { RhythmRoute(vm) }
                composable("explore") { TrendsExploreScreen(vm) }
                composable("trends") { TrendsScreen(vm) }
                composable("hydration") { HydrationScreen(vm) }
                composable("compare") { CompareScreen(vm) }
                composable("healthspan") { BroopHealthspanScreen(vm, navigate) }
                composable("mind") { BroopMindScreen(vm) }
                composable("energy") { BroopEnergyScreen(vm) }
                composable("jet_lag") { BroopJetLagScreen(vm) }
                composable("vital_signs") { VitalSignsScreen(vm, onVitalClick = { navigate("vital_detail/$it") }) }
                composable("vital_detail/{key}") {
                    val key = it.arguments?.getString("key").orEmpty()
                    val native = when (key) { "resp_rate" -> "resp"; "steps" -> "steps_est"; "sleep_performance" -> "rest"; else -> key }
                    if (native in setOf("hrv", "rhr", "resp", "spo2", "skin_temp", "steps_est", "active_kcal", "rest", "recovery", "strain", "fitness_age", "vo2max_est", "sdnn")) {
                        VitalDetailScreen(vm, native)
                    } else BroopOverviewMetricScreen(vm, key, onBack = { nav.popBackStack() })
                }
                composable("insights") { BroopJournalScreen(vm, navigate) }
                composable("journal_insights") { InsightsScreen(vm, onOpenInsightsHub = { navigate("insights_hub") }) }
                composable("insights_hub") { BroopInsightsScreen(vm, navigate) }
                composable("intelligence") { IntelligenceScreen(vm) }
                composable("fused_record") { FusedRecordRoute(vm) }
                composable("coach") { CoachScreen(onOpenSettings = { navigate("coach_settings") }) }
                composable("coach_settings") {
                    val owner = remember(it) { runCatching { nav.getBackStackEntry("coach") }.getOrDefault(it) }
                    CoachSettingsScreen(vm = viewModel(owner))
                }
                composable("smart_alarm") { SmartAlarmScreen(vm) }
                composable("settings") { BroopSettingsScreen(vm, navigate) }
                composable("account/{section}") { BroopAccountDetailScreen(vm, it.arguments?.getString("section").orEmpty(), navigate) }
                composable("integrations") { BroopIntegrationsScreen(vm, navigate) }
                composable("devices") { DevicesScreen(vm, onUseFileImport = { navigate("data_sources") }) }
                composable("apple_health") { AppleHealthScreen(vm) }
                composable("mi_band") { DataSourcesScreen(vm) }
                composable("data_sources") { DataSourcesScreen(vm) }
                composable("backup_sync") { BackupSyncScreen() }
                composable("shortcuts_export") { BroopAccountDetailScreen(vm, "shortcuts_export", navigate) }
                composable("android_shortcuts") { BroopAccountDetailScreen(vm, "android_shortcuts", navigate) }
                composable("noop_limitations") { NoopLimitationsScreen() }
                composable("automations") { AutomationsScreen(vm) }
                composable("power_saving") { PowerSavingScreen(vm) }
                composable("notifications") { NotificationsSettingsScreen(vm) }
                composable("test_centre") { TestCentreScreen(vm, onOpenGroundTruthCollector = { navigate("ground_truth_collector") }) }
                composable("ground_truth_collector") { GroundTruthCollectorScreen(vm) }
                composable("self_hosted_push") { SelfHostedPushScreen() }
                composable("steps_calibration") {
                    val profile = remember(context) { ProfileStore.from(context) }
                    var revision by remember { mutableStateOf(0) }
                    @Suppress("UNUSED_VARIABLE") val tick = revision
                    StepsCalibrationScreen(vm, profile, onProfileChanged = { revision++ }, onClose = { nav.popBackStack() })
                }
                composable("classic_today") {
                    TodayScreen(vm, onQuickActions = { quickActions = true }, updateStore = updateStore,
                        onOpenUpdates = { inbox = true }, onOpenSettings = { navigate("settings") },
                        onOpenHydration = { navigate("hydration") }, onOpenStress = { navigate("stress") },
                        onOpenHealth = { navigate("health") }, onOpenMetric = { navigate("vital_detail/$it") },
                        onOpenStepsCalibration = { navigate("steps_calibration") }, onOpenSleep = { navigate("sleep") },
                        onOpenCoupled = { navigate("coupled_view") }, onOpenCoach = { navigate("coach") },
                        onOpenActiveWorkout = { vm.openActiveWorkout(); navigate("live") },
                        onOpenDevices = { navigate("devices") }, onOpenJournal = { navigate("insights") })
                }
                composable("live_session") { LiveSessionScreen(vm, onClose = { nav.popBackStack() }) }
            }
        }
    }
    if (quickActions) {
        ModalBottomSheet(
            onDismissRequest = { quickActions = false }, containerColor = BroopPalette.card,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(BroopMetrics.page),
                verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
            ) {
                BroopCaps(stringResource(R.string.broop_quick_actions))
                BroopRow(stringResource(R.string.broop_start_activity), icon = Icons.Filled.PlayArrow) {
                    quickActions = false
                    startActivity = true
                }
                BroopRow(stringResource(R.string.broop_add_activity), icon = Icons.Filled.Add) {
                    quickActions = false
                    addActivity = true
                }
                listOf(
                    Triple(R.string.broop_strength_trainer, "lift_log", Icons.Filled.FitnessCenter),
                    Triple(R.string.broop_complete_journal, "insights", Icons.Filled.Edit),
                    Triple(R.string.broop_live_hr, "live", Icons.Filled.FavoriteBorder),
                    Triple(R.string.nav_breathe, "breathe", Icons.Filled.Air),
                    Triple(R.string.nav_intervals, "intervals", Icons.Filled.Timer),
                    Triple(R.string.nav_workouts, "workouts", Icons.Filled.FitnessCenter),
                ).forEach { (label, destination, icon) ->
                    BroopRow(stringResource(label), icon = icon) { quickActions = false; navigate(destination) }
                }
                BroopRow(stringResource(R.string.broop_updates), icon = Icons.Filled.Notifications) {
                    quickActions = false
                    inbox = true
                }
            }
        }
    }
    if (startActivity) {
        ModalBottomSheet(
            onDismissRequest = { startActivity = false }, containerColor = BroopPalette.card,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) { StartWorkoutSheet(vm, onDismiss = { startActivity = false }) }
    }
    if (inbox) {
        ModalBottomSheet(
            onDismissRequest = { inbox = false }, containerColor = BroopPalette.bgBottom,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            UpdatesInboxScreen(
                store = updateStore,
                onClose = { inbox = false },
                onDeepLink = { key ->
                    inbox = false
                    if (key == UpdateStore.WHATS_NEW_DEEP_LINK) whatsNew = true
                    else if (BroopNavigation.ownsRoute(key)) navigate(key)
                },
                onRestore = { cardId ->
                    TodayCardDismissal.setDismissed(context, cardId, false)
                    updateStore.restoreRequest = cardId
                },
            )
        }
    }
    if (whatsNew) {
        Dialog(onDismissRequest = { whatsNew = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            WhatsNewSheet(onClose = { whatsNew = false })
        }
    }
    if (addActivity) {
        ManualWorkoutDialog(editing = null, onDismiss = { addActivity = false }, onSave = { row, replacing ->
            vm.saveManualWorkout(row, replacing)
            addActivity = false
        })
    }
}
