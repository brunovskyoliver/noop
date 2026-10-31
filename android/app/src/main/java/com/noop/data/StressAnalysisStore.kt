package com.noop.data

import com.noop.analytics.StressMonitor
import com.noop.ui.WorkoutEditing
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.WeakHashMap
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

/** One raw-data funnel for Stress, Energy and the nightly Rest pass. Bounds are local calendar days. */
object StressAnalysisStore {
    data class Analysis(val result: StressMonitor.DayResult?, val hasRawHR: Boolean, val signature: String)

    private data class MemoKey(val strap: String, val day: String, val zone: String)
    private data class WorkoutKey(val start: Long, val end: Long, val sport: String, val source: String)
    private val memo = WeakHashMap<WhoopRepository, LinkedHashMap<MemoKey, Analysis>>()
    private const val memoDays = 96
    private const val rawLimit = 250_000

    suspend fun analyzeDay(
        repo: WhoopRepository,
        activeStrapId: String,
        day: String,
        now: Long = System.currentTimeMillis() / 1000,
        sessions: List<SleepSession>? = null,
        workouts: List<WorkoutRow>? = null,
        priorFloors: List<Double?>? = null,
        priorNights: List<StressMonitor.NightAggregate?>? = null,
        zone: ZoneId = ZoneId.systemDefault(),
    ): StressMonitor.DayResult? = analyzeDayWithWitness(
        repo, activeStrapId, day, now, sessions, workouts, priorFloors, priorNights, zone,
    ).result

    /**
     * The witness distinguishes retained history from sparse-but-present HR. Present raw inputs are
     * fetched and hashed before memo reuse: COUNT/MAX cannot detect corrected R-R or motion values.
     * This saves repeated analysis, but cannot skip those raw queries without a durable write revision.
     */
    // Swift twin `Repository.stressDayAnalysis(dayKey:sessions:workouts:priors:now:)`.
    suspend fun analyzeDayWithWitness(
        repo: WhoopRepository,
        activeStrapId: String,
        day: String,
        now: Long = System.currentTimeMillis() / 1000,
        sessions: List<SleepSession>? = null,
        workouts: List<WorkoutRow>? = null,
        priorFloors: List<Double?>? = null,
        priorNights: List<StressMonitor.NightAggregate?>? = null,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Analysis {
        coroutineContext.ensureActive()
        val date = LocalDate.parse(day)
        val start = date.atStartOfDay(zone).toEpochSecond()
        val next = date.plusDays(1).atStartOfDay(zone).toEpochSecond()
        val end = minOf(next, now)
        if (end <= start) return Analysis(null, false, "$day|$start|$end")
        val allSleep = sessions ?: allSleepSessions(repo, activeStrapId, start - 3 * 86_400, next, zone)
        val main = allSleep.filter { it.endTs >= start && it.endTs < next && it.endTs - it.effectiveStartTs >= 3 * 3600 }
            .maxByOrNull { it.endTs - it.effectiveStartTs }
            ?.let { StressMonitor.Interval(it.effectiveStartTs, it.endTs) }
        val readFrom = minOf(start, main?.start ?: start)
        val sleeps = allSleep.filter { it.endTs > readFrom && it.effectiveStartTs < end && it.endTs > it.effectiveStartTs }
            .map { StressMonitor.Interval(it.effectiveStartTs, it.endTs) }.sortedBy { it.start }
        val allWorkouts = workouts ?: allWorkouts(repo, activeStrapId, start - 3 * 86_400, end)
        val acts = allWorkouts.filter { it.endTs > start && it.startTs < end && it.endTs > it.startTs }
            .map { StressMonitor.Interval(it.startTs, it.endTs) }.sortedBy { it.start }
        val prior = if (priorFloors == null || priorNights == null) storedValues(
            repo, activeStrapId, StressMonitor.aggregateKeys, date.minusDays(14).toString(), date.minusDays(1).toString(),
        ) else emptyMap()
        val previous = (14L downTo 1L).map { date.minusDays(it).toString() }
        val floors = priorFloors ?: previous.map { prior[it]?.get(StressMonitor.wakeFloorKey) }
        val nights = priorNights ?: previous.map { prior[it]?.let(StressMonitor.NightAggregate::fromStored) }

        // EXISTS includes measured and PPG-derived HR. The measured-only COUNT/MAX fingerprint must
        // never classify a PPG-only day as empty. Probe the same registered-source union as raw reads.
        val sources = rawSourceIds(repo, activeStrapId)
        var present = false
        val presence = buildString {
            for (id in sources) {
                coroutineContext.ensureActive()
                val hasRows = repo.hasHrInWindow(id, readFrom, end - 1)
                append(id.length).append(':').append(id).append('=').append(hasRows).append('|')
                present = present || hasRows
            }
        }
        coroutineContext.ensureActive()
        val hr = if (present) repo.hrSamplesUnion(activeStrapId, readFrom, end - 1, rawLimit) else emptyList()
        // A concurrent retention delete can remove rows after EXISTS. The fetched union is the witness.
        val hasRawHR = hr.isNotEmpty()
        val rr = if (hasRawHR) repo.rrIntervalsUnion(activeStrapId, readFrom, end - 1, rawLimit) else emptyList()
        coroutineContext.ensureActive()
        val gravity = if (hasRawHR) repo.gravitySamplesUnion(activeStrapId, start, end - 1, rawLimit) else emptyList()
        val input = StressMonitor.DayInput(
            day, start, end, zone.rules.getOffset(Instant.ofEpochSecond(start)).totalSeconds.toLong(),
            hr, rr, gravity, sleeps, main, acts,
        )
        val signature = inputSignature(input, floors, nights, presence)
        val key = MemoKey(activeStrapId, day, zone.id)
        synchronized(memo) { memo[repo]?.get(key)?.takeIf { it.signature == signature } }?.let { return it }
        coroutineContext.ensureActive()
        val analysis = Analysis(StressMonitor.analyzeDay(input, floors, nights), hasRawHR, signature)
        coroutineContext.ensureActive()
        synchronized(memo) {
            val days = memo.getOrPut(repo) { LinkedHashMap(16, 0.75f, true) }
            days[key] = analysis
            while (days.size > memoDays) days.remove(days.keys.first())
        }
        return analysis
    }

    /** Every sleep block survives; imported coverage excludes computed blocks on the same local wake day. */
    suspend fun allSleepSessions(
        repo: WhoopRepository, id: String, from: Long, to: Long, zone: ZoneId = ZoneId.systemDefault(),
    ): List<SleepSession> {
        coroutineContext.ensureActive()
        val imported = repo.sleepSessionsUnion(id, from, to, rawLimit)
        val computed = repo.computedSleepSessionsUnion(id, from, to, rawLimit)
        fun wakeDay(s: SleepSession) = Instant.ofEpochSecond(s.endTs).atZone(zone).toLocalDate()
        val importedDays = imported.mapTo(HashSet(), ::wakeDay)
        coroutineContext.ensureActive()
        return (imported + computed.filter { wakeDay(it) !in importedDays }).sortedBy { it.effectiveStartTs }
    }

    /** The visible workout union without display-only HR reconciliation, used only for activity masks. */
    // Swift twin `Repository.workoutRowsUnreconciled(days:)`.
    suspend fun allWorkouts(repo: WhoopRepository, id: String, from: Long, to: Long): List<WorkoutRow> {
        val rawIds = rawSourceIds(repo, id)
        val sources = (rawIds + rawIds.map { if (it.endsWith("-noop")) it else "$it-noop" } + listOf(
            "apple-health", "health-connect", com.noop.ingest.LiftingImporter.SOURCE_ID,
            com.noop.ingest.ActivityFileImporter.SOURCE_ID,
        )).distinct()
        val rows = ArrayList<WorkoutRow>()
        for (source in sources) {
            coroutineContext.ensureActive()
            rows.addAll(repo.workouts(source, from, to, rawLimit))
        }
        val distinct = rows.distinctBy { WorkoutKey(it.startTs, it.endTs, it.sport, it.source) }
        val visible = WorkoutEditing.filterDismissed(distinct, repo.dismissedDetectedUnion(id))
        coroutineContext.ensureActive()
        return WorkoutEditing.dedupCrossSource(visible).sortedByDescending { it.startTs }
    }

    // Swift twin `Repository.stressStoredValues(keys:from:to:)`.
    suspend fun storedValues(repo: WhoopRepository, id: String, keys: List<String>, from: String, to: String): Map<String, Map<String, Double>> {
        val values = LinkedHashMap<String, MutableMap<String, Double>>()
        // Canonical imported first, active imported next, then canonical/active computed. The last
        // writer wins exactly as Repository.stressStoredValues; missing computed days keep imports.
        val sources = repo.importedSourceIds(id).asReversed() + repo.computedSourceIds(id).asReversed()
        for (key in keys) for (source in sources) {
            coroutineContext.ensureActive()
            for (row in repo.metricSeries(source, key, from, to)) {
                values.getOrPut(row.day) { LinkedHashMap() }[key] = row.value
            }
        }
        return values
    }

    private suspend fun rawSourceIds(repo: WhoopRepository, id: String): List<String> =
        WhoopRepository.rawWhoopSourceIdsFor(id, repo.pairedDevices()
            .filter { it.brand.equals("WHOOP", ignoreCase = true) }.map { it.id })

    private suspend fun inputSignature(
        input: StressMonitor.DayInput, floors: List<Double?>, nights: List<StressMonitor.NightAggregate?>, presence: String,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = ByteArray(8)
        fun number(value: Long) {
            for (i in 0..7) bytes[i] = (value ushr (i * 8)).toByte()
            digest.update(bytes)
        }
        fun string(value: String) { val utf8 = value.toByteArray(Charsets.UTF_8); number(utf8.size.toLong()); digest.update(utf8) }
        fun decimal(value: Double?) { number(if (value == null) 0 else 1); value?.let { number(it.toBits()) } }
        fun intervals(values: List<StressMonitor.Interval>) { number(values.size.toLong()); for (v in values) { number(v.start); number(v.end) } }
        string("stress-analysis-v1")
        string(input.day); string(presence)
        number(input.dayStart); number(input.dayEnd); number(input.tzOffsetSeconds)
        intervals(input.sleepWindows)
        intervals(listOfNotNull(input.mainSleep))
        intervals(input.activityWindows)
        number(floors.size.toLong()); floors.forEach(::decimal)
        number(nights.size.toLong())
        for (night in nights) {
            number(if (night == null) 0 else 1)
            night?.let { decimal(it.hr); decimal(it.hrSpread); decimal(it.lnRMSSD); decimal(it.lnRMSSDSpread) }
        }
        number(input.hr.size.toLong())
        for ((index, row) in input.hr.withIndex()) {
            if (index % 4096 == 0) coroutineContext.ensureActive()
            number(row.ts); number(row.bpm.toLong())
        }
        number(input.rr.size.toLong())
        for ((index, row) in input.rr.withIndex()) {
            if (index % 4096 == 0) coroutineContext.ensureActive()
            number(row.ts); number(row.rrMs.toLong()); number(row.seq.toLong())
            number(row.ord?.toLong() ?: Long.MIN_VALUE); number(row.srcChannel?.toLong() ?: Long.MIN_VALUE)
            number(row.tsSuspect?.toLong() ?: Long.MIN_VALUE)
        }
        number(input.gravity.size.toLong())
        for ((index, row) in input.gravity.withIndex()) {
            if (index % 4096 == 0) coroutineContext.ensureActive()
            number(row.ts); decimal(row.x); decimal(row.y); decimal(row.z); decimal(row.dynAccel)
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
