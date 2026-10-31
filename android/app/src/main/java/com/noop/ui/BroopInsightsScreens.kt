package com.noop.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.R
import com.noop.data.JournalEntry
import kotlinx.coroutines.launch
import java.time.LocalDate

/** The shared Android hub already runs the same EffectRanker and DoseResponse engines as iOS. */
@Composable
fun BroopInsightsScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    InsightsHubScreen(vm, broop = true)
}

/** Journal writes remain native-source only; opening a day never manufactures answers. */
@Composable
fun BroopJournalScreen(vm: AppViewModel, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    var dayOffset by rememberSaveable { mutableStateOf(0L) }
    var currentDay by remember { mutableStateOf(LocalDate.now()) }
    var sequence by remember { mutableIntStateOf(0) }
    var importedQuestions by remember { mutableStateOf<List<String>>(emptyList()) }
    var catalog by remember { mutableStateOf(loadJournalCatalogItems(context)) }
    var answers by remember { mutableStateOf<Map<String, Boolean>>(emptyMap()) }
    var numeric by remember { mutableStateOf<Map<String, Double>>(emptyMap()) }
    var loadedDay by remember { mutableStateOf<String?>(null) }
    var loadFailed by remember { mutableStateOf(false) }
    var saveFailed by remember { mutableStateOf(false) }
    val dayKey = journalDayKey(dayOffset, currentDay)
    val pendingDay by vm.pendingJournalDayOffset.collectAsStateWithLifecycle()

    LaunchedEffect(pendingDay) {
        pendingDay?.let {
            dayOffset = it.coerceIn(-1L, JOURNAL_BACKFILL_DAYS.toLong())
            vm.requestJournalDay(null)
        }
    }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                currentDay = LocalDate.now()
                catalog = loadJournalCatalogItems(context)
                sequence++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(vm, sequence, dayKey) {
        loadFailed = false
        try {
            importedQuestions = vm.repo.journal("my-whoop", "0000-01-01", "9999-12-31")
                .map { it.question }.distinct()
            val native = vm.repo.journal(JOURNAL_DEVICE_ID, dayKey, dayKey)
            answers = native.associate { it.question to it.answeredYes }
            numeric = native.mapNotNull { entry -> entry.numericValue?.let { entry.question to it } }.toMap()
            loadedDay = dayKey
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            loadFailed = true
        }
    }

    fun updateCatalog(next: List<JournalCatalogItem>) {
        saveJournalCatalogItems(context, next)
        catalog = next
    }

    fun save(question: String, yes: Boolean, value: Double? = null) {
        val targetDay = dayKey
        scope.launch {
            try {
                vm.repo.upsertJournal(listOf(JournalEntry(JOURNAL_DEVICE_ID, targetDay, question,
                    answeredYes = yes, numericValue = value)))
                saveFailed = false
                sequence++
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                saveFailed = true
            }
        }
    }

    BroopPage(stringResource(R.string.broop_account_journal)) {
        Text(stringResource(R.string.broop_account_journal_intro), style = BroopType.body, color = BroopPalette.textBody)
        when {
            loadFailed -> {
                BroopEmpty(stringResource(R.string.broop_account_journal_load_error), "")
                BroopRow(stringResource(R.string.broop_account_journal_retry), icon = Icons.Outlined.Edit) { sequence++ }
            }
            loadedDay != dayKey -> Text(stringResource(R.string.broop_account_loading), style = BroopType.body, color = BroopPalette.textBody)
            else -> JournalLogCard(
                items = resolveJournalItems(importedQuestions, catalog, includeHidden = false),
                answers = answers,
                numericAnswers = numeric,
                dayOffset = dayOffset,
                onDayOffset = { dayOffset = it.coerceIn(-1L, JOURNAL_BACKFILL_DAYS.toLong()) },
                onAnswer = { question, yes -> save(question, yes) },
                onNumeric = { question, value -> save(question, true, value) },
                onClear = { question ->
                    val targetDay = dayKey
                    scope.launch {
                        try {
                            vm.repo.deleteJournalEntry(JOURNAL_DEVICE_ID, targetDay, question)
                            saveFailed = false
                            sequence++
                        } catch (cancelled: kotlinx.coroutines.CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            saveFailed = true
                        }
                    }
                },
                onAddCustom = { question, kind, group -> updateCatalog(addCustomJournalItem(catalog, question, kind, group)) },
                onRename = { question, name -> updateCatalog(renameJournalItem(catalog, question, name)) },
                onSetGroup = { question, group -> updateCatalog(setJournalItemGroup(catalog, question, group)) },
                onSetKind = { question, kind -> updateCatalog(setJournalItemKind(catalog, question, kind)) },
                onRemoveQuestion = { updateCatalog(removeJournalItem(catalog, it)) },
                onRestoreQuestion = { updateCatalog(restoreJournalItem(catalog, it)) },
            )
        }
        if (saveFailed) Text(stringResource(R.string.broop_account_journal_error), style = BroopType.body, color = BroopPalette.warning)
        BroopSection(stringResource(R.string.broop_account_journal_more))
        BroopRow(stringResource(R.string.broop_account_journal_analysis), icon = Icons.Outlined.Edit) { onNavigate("journal_insights") }
        BroopRow(stringResource(R.string.nav_insights_hub), icon = Icons.Outlined.AutoAwesome) { onNavigate(Destination.InsightsHub.route) }
        BroopRow(stringResource(R.string.nav_intelligence), icon = Icons.Outlined.Psychology) { onNavigate(Destination.Intelligence.route) }
        BroopRow(stringResource(R.string.nav_coach), icon = Icons.Outlined.AutoAwesome) { onNavigate(Destination.Coach.route) }
    }
}
