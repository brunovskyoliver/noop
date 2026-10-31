package com.noop.analytics

import android.app.Application
import androidx.room.Room
import com.noop.data.DailyMetric
import com.noop.data.MetricSeriesRow
import com.noop.data.ScoreInputProvenanceRow
import com.noop.data.WhoopDatabase
import com.noop.data.WhoopRepository
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Verifies waking-only score writes against the real Room schema and transaction implementation. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, application = Application::class)
class BroopStressPersistenceTest {
    private lateinit var db: WhoopDatabase
    private lateinit var repo: WhoopRepository
    private val computed = "computed:active-strap"
    private val legacy = "computed:legacy-strap"
    private val day = "2026-10-18"
    private val next = "2026-10-19"

    @Before fun createDatabase() {
        db = Room.inMemoryDatabaseBuilder(RuntimeEnvironment.getApplication(), WhoopDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = WhoopRepository(db)
    }
    @After fun closeDatabase() { db.close() }

    private fun point(key: String, value: Double, on: String = day, source: String = computed) =
        MetricSeriesRow(source, on, key, value)
    private fun window(
        metrics: List<MetricSeriesRow>,
        dailies: List<DailyMetric> = emptyList(),
        provenance: List<ScoreInputProvenanceRow> = emptyList(),
        replaceDays: List<String> = emptyList(),
    ) = IntelligencePersistence.ComputedWindow(
        computed, day, next, dailies, metrics, provenance, listOf(computed, legacy), replaceDays,
    )
    private suspend fun value(key: String, on: String = day, source: String = computed): Double? =
        repo.metricSeries(source, key, on, on).singleOrNull()?.value

    @Test fun wakingOnlyMetricsReplaceTheirOwnKeysWithoutTouchingDailyScoresOrProvenance() = runBlocking {
        val dao = db.whoopDao()
        val oldDaily = DailyMetric(computed, day, recovery = 74.0, strain = 8.2, avgHrv = 53.0)
        dao.upsertDailyMetrics(listOf(oldDaily))
        dao.upsertScoreInputProvenance(listOf(ScoreInputProvenanceRow(computed, day, "recovery", "imported-owner")))
        dao.upsertMetricSeries(listOf(
            point("stress_high_min", 30.0), point("energy_end", 22.0), point("sleep_consistency", 82.0),
            point("stress_high_min", 99.0, source = legacy), point("sleep_consistency", 83.0, source = legacy),
            point("stress_high_min", 41.0, source = "other-strap"), point("stress_high_min", 42.0, on = "2026-10-17"),
        ))

        IntelligencePersistence.persistComputedWindow(repo, window(
            listOf(point("stress_high_min", 15.0), point("energy_end", 61.25), point("sleep_consistency", 1.0)),
            provenance = listOf(ScoreInputProvenanceRow(computed, day, "recovery", "new-owner")),
        ), preserveUnscoredHistory = true)

        assertEquals(listOf(oldDaily), repo.dailyMetrics(computed, day, day))
        assertEquals("imported-owner", repo.scoreInputSource(computed, day, "recovery"))
        assertEquals(15.0, value("stress_high_min")!!, 0.0)
        assertEquals(61.25, value("energy_end")!!, 0.0)
        assertEquals(82.0, value("sleep_consistency")!!, 0.0)
        assertNull(value("stress_high_min", source = legacy))
        assertEquals(83.0, value("sleep_consistency", source = legacy)!!, 0.0)
        assertEquals(41.0, value("stress_high_min", source = "other-strap")!!, 0.0)
        assertEquals(42.0, value("stress_high_min", on = "2026-10-17")!!, 0.0)
    }

    @Test fun explicitEmptyMetricDayClearsInvalidatedStressAndEnergyButKeepsOtherHistory() = runBlocking {
        val dao = db.whoopDao()
        val oldDaily = DailyMetric(computed, day, recovery = 74.0)
        dao.upsertDailyMetrics(listOf(oldDaily))
        dao.upsertScoreInputProvenance(listOf(ScoreInputProvenanceRow(computed, day, "recovery", "owner")))
        dao.upsertMetricSeries(StressRestPass.independentKeys.flatMapIndexed { index, key ->
            listOf(point(key, index + 1.0), point(key, index + 1.0, source = legacy))
        } + listOf(point("sleep_consistency", 80.0), point("energy_end", 70.0, on = next)))

        IntelligencePersistence.persistComputedWindow(repo, window(emptyList(), replaceDays = listOf(day)),
            preserveUnscoredHistory = true)

        for (key in StressRestPass.independentKeys) {
            assertNull("Stale $key survived for active source", value(key))
            assertNull("Stale $key survived for legacy source", value(key, source = legacy))
        }
        assertEquals(listOf(oldDaily), repo.dailyMetrics(computed, day, day))
        assertEquals("owner", repo.scoreInputSource(computed, day, "recovery"))
        assertEquals(80.0, value("sleep_consistency")!!, 0.0)
        assertEquals(70.0, value("energy_end", on = next)!!, 0.0)
    }

    @Test fun failureOnLaterWakingOnlyDayRollsBackEarlierDailyAndMetricWrites() = runBlocking {
        val dao = db.whoopDao()
        val oldDailies = listOf(DailyMetric(computed, day, recovery = 74.0), DailyMetric(computed, next, recovery = 66.0))
        dao.upsertDailyMetrics(oldDailies)
        dao.upsertScoreInputProvenance(listOf(ScoreInputProvenanceRow(computed, day, "recovery", "old-owner")))
        dao.upsertMetricSeries(listOf(point("stress_high_min", 30.0), point("energy_end", 20.0, on = next)))
        db.openHelper.writableDatabase.execSQL("""
            CREATE TRIGGER reject_later_energy BEFORE INSERT ON metricSeries
            WHEN NEW.day = '$next' AND NEW.`key` = 'energy_end'
            BEGIN SELECT RAISE(ABORT, 'deliberate test failure'); END
        """.trimIndent())

        var failed = false
        try {
            IntelligencePersistence.persistComputedWindow(repo, window(
                listOf(point("stress_high_min", 12.0), point("energy_end", 60.0, on = next)),
                dailies = listOf(DailyMetric(computed, day, recovery = 95.0)),
                provenance = listOf(ScoreInputProvenanceRow(computed, day, "recovery", "new-owner")),
            ), preserveUnscoredHistory = true)
        } catch (_: android.database.sqlite.SQLiteException) { failed = true }

        assertTrue("Injected Room write failure must propagate", failed)
        assertEquals(oldDailies, repo.dailyMetrics(computed, day, next))
        assertEquals("old-owner", repo.scoreInputSource(computed, day, "recovery"))
        assertEquals(30.0, value("stress_high_min")!!, 0.0)
        assertEquals(20.0, value("energy_end", on = next)!!, 0.0)
    }
}
