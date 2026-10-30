package com.noop.data

import com.noop.analytics.StressMonitor
import java.lang.reflect.Proxy
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class StressAnalysisStoreTest {
    private val utc = ZoneId.of("UTC")
    private val day = "2026-03-08"
    private val start = LocalDate.parse(day).atStartOfDay(utc).toEpochSecond()

    private class Fixture {
        val calls = ArrayList<Pair<String, String>>()
        val sleep = HashMap<String, List<SleepSession>>()
        val workouts = HashMap<String, List<WorkoutRow>>()
        val metrics = HashMap<String, List<MetricSeriesRow>>()
        val hr = HashMap<String, List<HrSample>>()
        val rr = HashMap<String, List<RrInterval>>()
        val gravity = HashMap<String, List<GravitySample>>()
        val markers = HashMap<String, List<DismissedWorkout>>()
        val devices = listOf(device("whoop-old", "archived", 1), device("whoop-new", "active", 2),
            device("unrelated-ring", "paired", 3, "Oura"))
        val dao = Proxy.newProxyInstance(WhoopDao::class.java.classLoader, arrayOf(WhoopDao::class.java)) { _, method, args ->
            val id = args?.firstOrNull() as? String ?: ""
            calls += method.name to id
            when (method.name) {
                "pairedDevices" -> devices
                "pairedDevice", "activeDeviceId" -> null
                "hasWhoop5RrSource", "hasWhoop4HistoricalRrSource" -> false
                "sleepSessions" -> sleep[id].orEmpty()
                "workouts" -> workouts[id].orEmpty()
                "dismissedWorkouts" -> markers[id].orEmpty()
                "metricSeries" -> metrics[id].orEmpty().filter { it.key == args[1] && it.day >= args[2] as String && it.day <= args[3] as String }
                // This is the measured + PPG EXISTS witness. A COUNT/MAX probe is deliberately absent.
                "hasHrInWindow" -> hr[id].orEmpty().any { it.ts >= args[1] as Long && it.ts <= args[2] as Long }
                "hrSamples" -> hr[id].orEmpty()
                "rrIntervals" -> rr[id].orEmpty()
                "gravitySamples" -> gravity[id].orEmpty()
                else -> throw AssertionError("Unexpected DAO read ${method.name}")
            }
        } as WhoopDao
        val repo = WhoopRepository(dao)

        companion object {
            private fun device(id: String, status: String, added: Long, brand: String = "WHOOP") =
                PairedDeviceRow(id, brand, "unknown", null, null, "strap", "hr", status, added, added)
        }
    }

    @Test fun allBlocksUseLocalWakeDayPrecedenceAndRetainNaps() = runBlocking {
        val f = Fixture()
        fun ts(value: String) = Instant.parse(value).epochSecond
        val imported = SleepSession("whoop-old", ts("2026-03-07T16:30:00Z"), ts("2026-03-08T00:30:00Z"))
        val nap = SleepSession("whoop-old", ts("2026-03-08T01:00:00Z"), ts("2026-03-08T01:30:00Z"))
        val blocked = SleepSession("whoop-new-noop", ts("2026-03-07T22:30:00Z"), ts("2026-03-07T23:30:00Z"))
        val fill = SleepSession("whoop-new-noop", ts("2026-03-08T10:30:00Z"), ts("2026-03-08T12:30:00Z"))
        f.sleep["whoop-old"] = listOf(nap, imported)
        f.sleep["whoop-new-noop"] = listOf(fill, blocked)
        val result = StressAnalysisStore.allSleepSessions(f.repo, "whoop-new", start - 2 * 86_400, start + 2 * 86_400, ZoneId.of("America/New_York"))
        assertEquals(listOf(imported, nap, fill), result)
        assertFalse(f.calls.any { it.second == "unrelated-ring" })
    }

    @Test fun storedValuesKeepImportedFallbackAndPreferActiveComputed() = runBlocking {
        val f = Fixture()
        fun metric(id: String, day: String, value: Double) = MetricSeriesRow(id, day, StressMonitor.wakeFloorKey, value)
        f.metrics["my-whoop"] = listOf(metric("my-whoop", day, 45.0), metric("my-whoop", "2026-03-07", 42.0))
        f.metrics["whoop-new"] = listOf(metric("whoop-new", day, 47.0))
        f.metrics["my-whoop-noop"] = listOf(metric("my-whoop-noop", day, 49.0))
        f.metrics["whoop-new-noop"] = listOf(metric("whoop-new-noop", day, 51.0))
        val result = StressAnalysisStore.storedValues(f.repo, "whoop-new", listOf(StressMonitor.wakeFloorKey), "2026-03-01", day)
        assertEquals(51.0, result[day]?.get(StressMonitor.wakeFloorKey))
        assertEquals(42.0, result["2026-03-07"]?.get(StressMonitor.wakeFloorKey))
    }

    @Test fun allWorkoutSourcesMaskActivityWithoutAnyHRReadAndHonorDismissal() = runBlocking {
        val f = Fixture()
        val sources = listOf("whoop-new", "whoop-old", "my-whoop", "whoop-new-noop", "whoop-old-noop", "my-whoop-noop",
            "apple-health", "health-connect", "lifting", "activity-file")
        val expected = sources.mapIndexed { index, source ->
            WorkoutRow(source, start + index * 1000, start + index * 1000 + 100, "sport-$index", source)
        }
        for (row in expected) f.workouts[row.deviceId] = listOf(row)
        val dismissed = expected[4]
        f.markers["whoop-old-noop"] = listOf(DismissedWorkout("whoop-old-noop", dismissed.startTs, dismissed.endTs))
        val result = StressAnalysisStore.allWorkouts(f.repo, "whoop-new", start, start + 86_400)
        assertEquals(expected.filter { it != dismissed }.reversed(), result)
        assertEquals(sources, f.calls.filter { it.first == "workouts" }.map { it.second })
        assertFalse(f.calls.any { it.first.contains("hr", ignoreCase = true) })
    }

    @Test fun noHRSkipsAllRawFetchesButKeepsPersonalReferencesForEnergyCarry() = runBlocking {
        val f = Fixture()
        val floors = listOf<Double?>(50.0, 51.0, 52.0, 53.0)
        val night = StressMonitor.NightAggregate(49.0, 2.0, 3.7, 0.1)
        val result = StressAnalysisStore.analyzeDayWithWitness(f.repo, "whoop-new", day, start + 86_400,
            emptyList(), emptyList(), floors, List(4) { night }, utc)
        assertFalse(result.hasRawHR)
        assertNotNull(result.result)
        val analysis = requireNotNull(result.result)
        assertTrue(analysis.wake!!.personal)
        assertTrue(analysis.sleep!!.personal)
        assertEquals(288, analysis.epochs.size)
        assertEquals(listOf("whoop-new", "whoop-old", "my-whoop"), f.calls.filter { it.first == "hasHrInWindow" }.map { it.second })
        assertFalse(f.calls.any { it.first in setOf("hrSamples", "rrIntervals", "gravitySamples") })
        val again = StressAnalysisStore.analyzeDayWithWitness(f.repo, "whoop-new", day, start + 86_400,
            emptyList(), emptyList(), floors, List(4) { night }, utc)
        assertSame(result, again)
    }

    @Test fun workoutNaturalKeyIncludesEndAndSourceBeforeCrossSourceDedup() = runBlocking {
        val f = Fixture()
        val first = WorkoutRow("whoop-new", start, start + 100, "Walk", "manual")
        val longer = first.copy(deviceId = "whoop-old", endTs = start + 200)
        val exactAlias = first.copy(deviceId = "my-whoop")
        f.workouts["whoop-new"] = listOf(first)
        f.workouts["whoop-old"] = listOf(longer)
        f.workouts["my-whoop"] = listOf(exactAlias)
        val result = StressAnalysisStore.allWorkouts(f.repo, "whoop-new", start, start + 86_400)
        // Swift's final overlap collapse chooses the longer row. A premature (start,sport)
        // collapse would lose it and leave the shorter activity mask instead.
        assertEquals(listOf(longer), result)
    }

    @Test fun unchangedDayReusesAnalysisButSameTimestampRrAndGravityCorrectionsInvalidate() = runBlocking {
        val f = Fixture()
        f.hr["whoop-old"] = (0..299).map { HrSample("whoop-old", start + it, 70) }
        f.rr["whoop-old"] = listOf(RrInterval("whoop-old", start + 1, 800))
        f.gravity["whoop-old"] = listOf(GravitySample("whoop-old", start + 1, 0.0, 0.0, 1.0))
        suspend fun analyze() = StressAnalysisStore.analyzeDayWithWitness(f.repo, "whoop-new", day, start + 86_400,
            emptyList(), emptyList(), emptyList(), emptyList(), utc)
        val before = analyze()
        assertTrue(before.hasRawHR)
        assertSame(before, analyze())
        f.rr["whoop-old"] = listOf(f.rr["whoop-old"]!!.single().copy(rrMs = 850))
        val afterRR = analyze()
        assertNotEquals(before.signature, afterRR.signature)
        f.gravity["whoop-old"] = listOf(f.gravity["whoop-old"]!!.single().copy(x = 0.5))
        val afterMotion = analyze()
        assertNotEquals(afterRR.signature, afterMotion.signature)
        f.hr["whoop-old"] = f.hr["whoop-old"]!!.map { it.copy(bpm = 75) }
        assertNotEquals(afterMotion.signature, analyze().signature)
    }

    @Test fun windowsNightSpreadPriorsAndAdvancingDayEndInvalidateMemo() = runBlocking {
        val f = Fixture()
        val night = StressMonitor.NightAggregate(50.0, 2.0, 3.6, 0.1)
        suspend fun analyze(end: Long = start + 3600, sleeps: List<SleepSession> = emptyList(),
            activity: List<WorkoutRow> = emptyList(), nights: List<StressMonitor.NightAggregate?> = listOf(night),
            floors: List<Double?> = listOf(50.0)) =
            StressAnalysisStore.analyzeDayWithWitness(f.repo, "whoop-new", day, end, sleeps, activity, floors, nights, utc)
        val base = analyze()
        assertNotEquals(base.signature, analyze(end = start + 7200).signature)
        assertNotEquals(base.signature, analyze(sleeps = listOf(SleepSession("whoop-new", start - 3600, start + 60))).signature)
        assertNotEquals(base.signature, analyze(activity = listOf(WorkoutRow("whoop-new", start, start + 60, "walk", "manual"))).signature)
        assertNotEquals(base.signature, analyze(nights = listOf(night.copy(lnRMSSDSpread = 0.2))).signature)
        assertNotEquals(base.signature, analyze(floors = listOf(51.0)).signature)
    }

    @Test fun cancellationStopsBeforeRepositoryQueries() = runBlocking {
        val f = Fixture()
        try {
            withContext(Job().apply { cancel() }) {
                StressAnalysisStore.analyzeDayWithWitness(f.repo, "whoop-new", day, start + 86_400)
            }
            throw AssertionError("Expected cancellation")
        } catch (_: CancellationException) { }
        assertTrue(f.calls.isEmpty())
    }
}
