package com.noop.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.noop.analytics.Baselines
import com.noop.analytics.HrZones
import com.noop.analytics.ReadinessEngine
import com.noop.analytics.RestScorer
import com.noop.analytics.StrainScorer
import com.noop.data.DailyMetric
import com.noop.data.SleepSession
import com.noop.data.WorkoutRow
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.WeakHashMap
import kotlin.math.abs
import kotlin.math.sqrt
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A single selected-day value shared by Home and the three score deep dives. */
internal class BroopOverviewState {
    private var selectedOffset by mutableIntStateOf(0)
    var dayOffset: Int
        get() = selectedOffset
        set(value) {
            if (value != selectedOffset) { selectedOffset = value; snapshot = null; loadedKey = null }
        }
    var snapshot by mutableStateOf<BroopOverviewSnapshot?>(null)
    var loadedKey: Any? = null
    var reloadToken by mutableIntStateOf(0)

    fun reload() { loadedKey = null; reloadToken++ }

    fun step(delta: Int, maxOffset: Int) {
        dayOffset = (dayOffset + delta).coerceIn(0, maxOffset)
    }
}

private val broopOverviewStates = WeakHashMap<AppViewModel, BroopOverviewState>()

internal fun broopSelectOverviewToday(vm: AppViewModel) {
    broopOverviewStates.getOrPut(vm) { BroopOverviewState() }.dayOffset = 0
}

internal data class BroopOverviewSnapshot(
    val dayKey: String,
    val day: DailyMetric?,
    val days: List<DailyMetric>,
    val rest: Double?,
    val restDay: DailyMetric?,
    val restDayKey: String,
    val charge: Double?,
    val carriedChargeDay: DailyMetric?,
    val calibrationNights: Int?,
    val effort: Double?,
    val effortMax: Double,
    val night: HeroNight?,
    val needMinutes: Double,
    val consistency: Double?,
    val workouts: List<WorkoutRow>,
    val zoneMinutes: List<Double>?,
    val journalDays: Set<String>,
    val readiness: ReadinessEngine.Readiness,
    val readings: List<BroopOverviewReading>,
    val restSeries: Map<String, Double>,
    val hoursVsNeededStored: Double? = null,
    val sleepStressPct: Double? = null,
    val sleepModel: SleepModel? = null,
    val vitals: List<Vital> = emptyList(),
    val effortTarget: com.noop.analytics.StrainTarget.Band? = null,
    val habitualMidsleepSec: Long? = null,
    val activeKcal: Double? = null,
) {
    val asleepMinutes: Double? get() = restDay?.totalSleepMin
    val efficiency: Double? get() = restDay?.efficiency?.let { if (it <= 1) it * 100 else it }
    val restorativePct: Double? get() {
        val asleep = asleepMinutes?.takeIf { it > 0 } ?: return null
        return ((restDay?.deepMin ?: return null) + (restDay.remMin ?: return null)) / asleep * 100
    }
    val hoursVsNeeded: Double? get() = hoursVsNeededStored ?: asleepMinutes?.let { it / needMinutes * 100 }
}

internal data class BroopOverviewReading(
    val key: String,
    val value: Double,
    val baseline: Double?,
    val lower: Double?,
    val upper: Double?,
) {
    val inRange: Boolean? get() = if (lower != null && upper != null) value in lower..upper else null
}

/** The previous 30 rows exclude the selected day, matching Swift BroopStore's statistics. */
internal fun broopOverviewReading(key: String, value: Double?, history: List<Double>): BroopOverviewReading? {
    if (value == null || !value.isFinite()) return null
    val clean = history.filter(Double::isFinite).takeLast(30)
    if (clean.isEmpty()) return BroopOverviewReading(key, value, null, null, null)
    val mean = clean.sum() / clean.size
    val variance = clean.sumOf { (it - mean) * (it - mean) } / clean.size
    val sd = maxOf(sqrt(variance), abs(mean) * 0.02, 0.05)
    return BroopOverviewReading(key, value, mean, mean - sd, mean + sd)
}

/** Carry the night and its score together; future clock outliers cannot become last night's Rest. */
internal fun broopRestDayKey(dayKey: String, isToday: Boolean, rest: Map<String, Double>): String? {
    if (rest[dayKey] != null) return dayKey
    val latest = rest.filterKeys { it <= dayKey }.maxByOrNull { it.key } ?: return null
    return latest.key.takeIf {
        freshRestScore(null, latest.key, latest.value, isToday, dayKey) != null
    }
}

internal fun broopOverviewMaxOffset(days: List<DailyMetric>, today: LocalDate): Int =
    days.minOfOrNull { it.day }?.let { first ->
        runCatching { ChronoUnit.DAYS.between(LocalDate.parse(first), today).coerceIn(0, Int.MAX_VALUE.toLong()).toInt() }
            .getOrDefault(0)
    } ?: 0

@Composable
internal fun rememberBroopOverview(vm: AppViewModel, independentToday: Boolean = false): BroopOverviewState {
    val state = remember(vm, independentToday) {
        if (independentToday) BroopOverviewState() else broopOverviewStates.getOrPut(vm) { BroopOverviewState() }
    }
    // Journal entries and saved layouts can change without rewriting a daily metric. Re-entering a
    // page must refresh its shared snapshot even when all physiological Flow values compare equal.
    LaunchedEffect(vm) { state.reload() }
    val days by vm.recentDays.collectAsStateWithLifecycle()
    val today by vm.today.collectAsStateWithLifecycle()
    val baselines by vm.chargeBaselines.collectAsStateWithLifecycle()
    val activeCycle by vm.activeDayCycle.collectAsStateWithLifecycle()
    val workouts by vm.workouts.collectAsStateWithLifecycle()
    val spo2Candidates by vm.spo2CandidateByDay.collectAsStateWithLifecycle()
    val hrvOverCount by vm.hrvOverCountByDay.collectAsStateWithLifecycle()
    val healthAlert by vm.healthAlert.collectAsStateWithLifecycle()
    val targetDebt by vm.strainTargetDebtMin.collectAsStateWithLifecycle()
    val syncRevision by vm.lastHistorySyncAt.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val profile = remember(context) { ProfileStore.from(context) }
    val scale = UnitPrefs.effortScale(context)
    val mode = NoopPrefs.dayCycleMode(context)
    val date = logicalDayNow().minusDays(state.dayOffset.toLong())
    val isToday = state.dayOffset == 0
    val day = if (isToday) resolveTodayRow(days, date.toString(), LocalDate.now().toString()) ?: today
        else days.lastOrNull { it.day == date.toString() }
    val key = day?.day ?: date.toString()
    val hrvEpoch = NoopPrefs.of(context).getLong(Baselines.hrvBaselineEpochKey, 0L).toDouble()
    val strainGoal = com.noop.analytics.StrainTarget.Goal.fromRaw(NoopPrefs.of(context).getString("noop.strainTargetGoal", null))
    val restV2Enabled = NoopPrefs.of(context).getBoolean(com.noop.analytics.RestPerformanceV2.enabledKey, true)
    val loadKey = listOf(days, today, baselines, state.dayOffset, scale, mode, activeCycle, workouts, vm.activeStrapId,
        state.reloadToken, spo2Candidates, hrvOverCount, healthAlert, strainGoal, syncRevision, restV2Enabled, targetDebt)

    LaunchedEffect(days, vm.activeStrapId) { vm.loadWorkouts(); vm.refreshTonightPlan() }
    LaunchedEffect(loadKey) {
        if (state.loadedKey == loadKey && state.snapshot?.dayKey == key) return@LaunchedEffect
        suspend fun series(metric: String, through: String = key): Map<String, Double> = runCatching {
            vm.repo.resolvedSeries(metric, "my-whoop", "0000-00-00", through,
                strapDeviceId = vm.activeStrapId).values.associate { it.first to it.second }
        }.getOrDefault(emptyMap())

        val restSeries = series("sleep_performance")
        val restKey = broopRestDayKey(key, isToday, restSeries) ?: key
        val sleepDay = days.lastOrNull { it.day == restKey } ?: day?.takeIf { it.day == restKey }
        val importedNeed = series("sleep_need_min")[restKey]
        val need = importedNeed
            ?: (RestScorer.personalizedNeedHours(days.mapNotNull { it.totalSleepMin?.div(60) }, profile.age) * 60)
        suspend fun restPart(metric: String): Double? = if (!restV2Enabled) null else runCatching {
            vm.repo.metricSeriesComputedUnion(vm.activeStrapId, metric, restKey, restKey).lastOrNull()?.value
        }.getOrNull()
        val consistency = series("sleep_consistency")[restKey] ?: restPart(com.noop.analytics.RestPerformanceV2.consistencyKey)
        val hoursVsNeeded = if (importedNeed == null) restPart(com.noop.analytics.RestPerformanceV2.hoursVsNeedKey) else null
        val sleepStressPct = restPart("sleep_stress_pct")
        val imported = runCatching { vm.repo.sleepSessionsUnion(vm.activeStrapId, 0, System.currentTimeMillis() / 1000) }
            .getOrDefault(emptyList())
        val computed = runCatching { vm.repo.computedSleepSessionsUnion(vm.activeStrapId, 0, System.currentTimeMillis() / 1000) }
            .getOrDefault(emptyList())
        val importedDays = imported.mapTo(HashSet()) { localDayString(it.endTs) }
        val sessions: List<SleepSession> = (imported + computed.filter { localDayString(it.endTs) !in importedDays }).sortedBy { it.effectiveStartTs }
        val navDays = sessions.groupBy { localDayString(it.endTs) }.toSortedMap(reverseOrder()).values
            .map { it.sortedBy(SleepSession::effectiveStartTs) }
        val nightIndex = broopSleepNightIndex(navDays, restKey) ?: -1
        val habitual = runCatching { vm.repo.habitualMidsleepSec(vm.activeStrapId) }.getOrNull()
        val motion = if (nightIndex >= 0) runCatching { vm.repo.sessionMotions(vm.activeStrapId, navDays[nightIndex]) }.getOrDefault(emptyMap()) else emptyMap()
        val night = if (nightIndex >= 0) selectNight(navDays, days, nightIndex, habitual, motion, is24h = ClockPrefs.uses24Hour(context)) else null
        val importedSleep = ImportedSleepSeries(restSeries, series("sleep_consistency"), series("sleep_need_min"), series("sleep_debt_min"))
        val sleepModel = withContext(Dispatchers.Default) {
            buildSleepModel(days, night?.session, importedSleep,
                selectedDay = restKey, heroStages = night?.groupStages, heroSegments = night?.groupSegments,
                sessions = sessions, is24h = ClockPrefs.uses24Hour(context))
        }
        val zone = ZoneId.systemDefault()
        val calendarStart = date.atStartOfDay(zone).toEpochSecond()
        val calendarEnd = if (isToday) System.currentTimeMillis() / 1000 else date.plusDays(1).atStartOfDay(zone).toEpochSecond()
        val markers = if (mode == com.noop.analytics.DayCycleMode.SLEEP_ONSET) series(com.noop.analytics.DayCycleIntelligenceIntegration.ONSET_KEY, date.plusDays(1).toString()) else emptyMap()
        val start = if (isToday) activeDayCycleStart(mode, activeCycle?.onsetTs, calendarStart)
            else markers[key]?.toLong() ?: calendarStart
        val end = if (isToday) calendarEnd else markers[date.plusDays(1).toString()]?.toLong() ?: calendarEnd
        val hr = runCatching { vm.repo.hrSamplesUnion(vm.activeStrapId, start, maxOf(start, end - 1)) }.getOrDefault(emptyList())
        val live = if (isToday) withContext(Dispatchers.Default) { StrainScorer.strain(hr, profile.hrMaxOverride.takeIf { it > 0 }?.toDouble()
            ?: StrainScorer.tanakaHRmax(profile.age.toDouble()), day?.restingHr?.toDouble() ?: StrainScorer.defaultRestingHR,
            method = NoopPrefs.effortMethod(context), sex = profile.sex) } else null
        val effort = StrainScorer.effectiveEffort(live, day?.strain)?.let { UnitFormatter.effortValue(it, scale) }
        val calibration = if (isToday) recoveryCalibrationNights(baselines?.hrvHistory?.values.orEmpty(),
            baselines?.hrvHistory?.dayKeys.orEmpty(), day?.recovery != null, hrvEpoch) else null
        val carry = lastScoredRecoveryDay(days, key, isToday, day?.recovery != null, calibration != null,
            maxOf(key, LocalDate.now().toString()))
        val anchor = carry?.day ?: key
        val prior = days.filter { it.day < key }.takeLast(30)
        val activeEnergy = vm.repo.metricSeriesComputedUnion(vm.activeStrapId, "active_energy_kcal",
            date.minusDays(31).toString(), key).associate { it.day to it.value }
        val appleActive = vm.repo.appleDaily(com.noop.data.WhoopRepository.APPLE_HEALTH_SOURCE,
            date.minusDays(31).toString(), key).associate { it.day to it.activeKcal }
        fun activeKcal(day: String): Double? = appleActive[day] ?: activeEnergy[day]
        fun vital(current: Double?, fallback: (DailyMetric) -> Double?): Double? = current
            ?: if (isToday) days.lastOrNull { it.day < key && fallback(it) != null }?.let(fallback) else null
        val readings = listOfNotNull(
            broopOverviewReading("hrv", vital(day?.avgHrv) { it.avgHrv }, prior.mapNotNull { it.avgHrv }),
            broopOverviewReading("rhr", vital(day?.restingHr?.toDouble()) { it.restingHr?.toDouble() }, prior.mapNotNull { it.restingHr?.toDouble() }),
            broopOverviewReading("resp_rate", vital(day?.respRateBpm) { it.respRateBpm }, prior.mapNotNull { it.respRateBpm }),
            broopOverviewReading("spo2", vital(day?.spo2Pct) { it.spo2Pct }, prior.mapNotNull { it.spo2Pct }),
            broopOverviewReading("steps", day?.steps?.toDouble(), prior.mapNotNull { it.steps?.toDouble() }),
            broopOverviewReading("active_kcal", activeKcal(key), prior.mapNotNull { activeKcal(it.day) }),
        )
        val journal = runCatching { vm.repo.journal(JOURNAL_DEVICE_ID, date.minusDays(6).toString(), key).mapTo(HashSet()) { it.day } }
            .getOrDefault(emptySet())
        val zones = withContext(Dispatchers.Default) {
            HrZones.timeInZone(hr, profile.hrZoneSet).seconds.map { it / 60 }.takeIf { it.any { n -> n > 0 } }
        }
        val debt = if (isToday) targetDebt else null
        val target = com.noop.analytics.StrainTarget.band(com.noop.analytics.StrainTarget.Inputs(
            day?.recovery, debt, isToday && healthAlert != null, strainGoal))
        currentCoroutineContext().ensureActive()
        state.snapshot = BroopOverviewSnapshot(key, day, days, restSeries[restKey], sleepDay, restKey,
            day?.recovery ?: carry?.recovery, carry, calibration, effort,
            if (scale == EffortScale.WHOOP) 21.0 else 100.0, night, need, consistency,
            workouts.filter { it.startTs in start until end },
            zones, journal, ReadinessEngine.evaluate(days, anchor), readings, restSeries,
            hoursVsNeededStored = hoursVsNeeded, sleepStressPct = sleepStressPct, sleepModel = sleepModel,
            vitals = vitalsFor(day, days, UnitPrefs.temperature(context), spo2Candidates,
                NoopPrefs.spo2CandidateDisplay(context), hrvOverCount, UnitPrefs.skinTempPreferred(context)), effortTarget = target,
            habitualMidsleepSec = habitual, activeKcal = activeKcal(key))
        state.loadedKey = loadKey
    }
    return state
}
