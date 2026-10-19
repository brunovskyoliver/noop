package com.noop.data

import com.noop.protocol.FUTURE_MARGIN
import com.noop.protocol.MIN_PLAUSIBLE_UNIX
import java.io.File
import java.lang.reflect.Proxy
import java.sql.Connection
import java.sql.DriverManager
import java.time.Instant
import java.time.ZoneOffset
import java.util.TimeZone
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** Exercises repository pruning against the production DAO SQL, rather than a Kotlin predicate copy.
 *  Only SQL binding is adapted for JDBC; KSP/schema-oracle tests cover the full Room schema. */
class RepositoryPruningSqliteTest {
    private lateinit var db: Connection
    private lateinit var repo: WhoopRepository
    private lateinit var daoSource: String
    private val now = 1_780_916_150L
    private val minTs = MIN_PLAUSIBLE_UNIX
    private val maxTs = now + FUTURE_MARGIN
    private val today = "2026-06-08"
    private val minDay = Instant.ofEpochSecond(minTs).atZone(ZoneOffset.UTC).toLocalDate()
    private val owners = listOf("my-whoop", "my-whoop-noop")
    private val rawTables = listOf(
        "hrSample", "ppgHrSample", "rrInterval", "skinTempSample", "stepSample", "respSample",
        "gravitySample", "spo2Sample", "sleepStateSample", "ppgWaveformSample", "v18AuxSample",
        "event", "battery",
    )

    @Before fun open() {
        val root = File(System.getProperty("user.dir") ?: ".")
        val rel = "src/main/java/com/noop/data/WhoopDao.kt"
        val sourceFile = listOf(File(root, rel), File(root, "app/$rel"), File(root, "android/app/$rel"))
            .firstOrNull { it.isFile } ?: error("WhoopDao.kt not found from $root")
        daoSource = sourceFile.readText()
        db = DriverManager.getConnection("jdbc:sqlite::memory:")
        for (table in rawTables) sql("CREATE TABLE `$table` (deviceId TEXT NOT NULL, ts INTEGER NOT NULL)")
        sql("CREATE TABLE dailyMetric (deviceId TEXT NOT NULL, day TEXT NOT NULL)")
        sql("CREATE TABLE sleepSession (deviceId TEXT NOT NULL, startTs INTEGER NOT NULL)")
        val dao = Proxy.newProxyInstance(WhoopDao::class.java.classLoader, arrayOf(WhoopDao::class.java)) { _, method, args ->
            val deleted = executeDaoDelete(method.name, args!!.dropLast(1))
            if (method.name == "deleteDailyMetricsInRange") Unit else deleted
        } as WhoopDao
        repo = WhoopRepository(dao)
    }

    @After fun close() { if (::db.isInitialized) db.close() }

    @Test fun healRawStreamsDeletesBadClockRowsAcrossOwnersAndKeepsInclusiveBounds() = runBlocking {
        val timestamps = listOf(0L, minTs - 1, minTs, now, maxTs, maxTs + 1, now + 30 * 86_400)
        for (table in rawTables) for (owner in owners) for (ts in timestamps) insert(table, owner, ts)

        assertEquals(rawTables.size * owners.size * 4, repo.healImplausibleTimestamps(nowSec = now, today = today))
        val expected = owners.flatMap { owner ->
            listOf(minTs, now, maxTs).map { owner to it.toString() }
        }.sortedBy { it.first + it.second }
        for (table in rawTables) assertEquals(table, expected, rows(table, "ts"))
        assertEquals(
            "a second heal must leave every surviving row intact", 0,
            repo.healImplausibleTimestamps(nowSec = now, today = today),
        )
    }

    @Test fun healDailyMetricsPreservesOldImportsAndInclusiveDayBounds() = runBlocking {
        val days = listOf(minDay.minusDays(1).toString(), minDay.toString(), today, "2026-06-09")
        for (owner in owners) for (day in days) insert("dailyMetric", owner, day)

        assertEquals(3, repo.healImplausibleTimestamps(nowSec = now, today = today))
        assertEquals(
            listOf(
                "my-whoop" to days[0], "my-whoop" to days[1], "my-whoop" to today,
                "my-whoop-noop" to days[1], "my-whoop-noop" to today,
            ).sortedBy { it.first + it.second },
            rows("dailyMetric", "day"),
        )
        assertEquals(0, repo.healImplausibleTimestamps(nowSec = now, today = today))
    }

    @Test fun healSleepSessionsPreservesOldImportsAndInclusiveTimestampBounds() = runBlocking {
        val timestamps = listOf(0L, minTs - 1, minTs, now, maxTs, maxTs + 1)
        for (owner in owners) for (ts in timestamps) insert("sleepSession", owner, ts)

        assertEquals(4, repo.healImplausibleTimestamps(nowSec = now, today = today))
        val expected = timestamps.dropLast(1).map { "my-whoop" to it.toString() } +
            listOf(minTs, now, maxTs).map { "my-whoop-noop" to it.toString() }
        assertEquals(expected.sortedBy { it.first + it.second }, rows("sleepSession", "startTs"))
        assertEquals(0, repo.healImplausibleTimestamps(nowSec = now, today = today))
    }

    @Test fun healFloorDayMatchesSwiftOracleAcrossDefaultZones() = runBlocking {
        val originalZone = TimeZone.getDefault()
        val actual = mutableListOf<String>()
        try {
            for (zone in listOf("UTC", "Asia/Tokyo", "Asia/Kathmandu", "America/New_York")) {
                TimeZone.setDefault(TimeZone.getTimeZone(zone))
                for (probe in listOf(1_699_913_599L, 1_699_999_999L, minTs, 1_700_000_001L, 1_700_006_400L)) {
                    sql("DELETE FROM dailyMetric")
                    val day = Instant.ofEpochSecond(probe).atZone(ZoneOffset.UTC).toLocalDate()
                    for (offset in -1L..1L) insert("dailyMetric", "my-whoop-noop", day.plusDays(offset).toString())
                    repo.healImplausibleTimestamps(nowSec = now, today = today, minTs = probe)
                    actual += "$zone|$probe|${rows("dailyMetric", "day").first().second}"
                }
            }
        } finally {
            TimeZone.setDefault(originalZone)
        }
        // Verbatim stdout from swiftc -O running the production TimestampHeal.utcDayKey helper.
        assertEquals(
            """
            UTC|1699913599|2023-11-13
            UTC|1699999999|2023-11-14
            UTC|1700000000|2023-11-14
            UTC|1700000001|2023-11-14
            UTC|1700006400|2023-11-15
            Asia/Tokyo|1699913599|2023-11-13
            Asia/Tokyo|1699999999|2023-11-14
            Asia/Tokyo|1700000000|2023-11-14
            Asia/Tokyo|1700000001|2023-11-14
            Asia/Tokyo|1700006400|2023-11-15
            Asia/Kathmandu|1699913599|2023-11-13
            Asia/Kathmandu|1699999999|2023-11-14
            Asia/Kathmandu|1700000000|2023-11-14
            Asia/Kathmandu|1700000001|2023-11-14
            Asia/Kathmandu|1700006400|2023-11-15
            America/New_York|1699913599|2023-11-13
            America/New_York|1699999999|2023-11-14
            America/New_York|1700000000|2023-11-14
            America/New_York|1700000001|2023-11-14
            America/New_York|1700006400|2023-11-15
            """.trimIndent(),
            actual.joinToString("\n"),
        )
    }

    @Test fun windowedDeleteKeepsImportsOtherStrapsAndOutOfRangeDays() = runBlocking {
        val computed = "my-whoop-noop"
        for (day in 9..13) insert("dailyMetric", computed, "2026-05-%02d".format(day))
        insert("dailyMetric", "my-whoop", "2026-05-11")
        insert("dailyMetric", "other-noop", "2026-05-11")

        repo.deleteComputedDailyInRange(computed, "2026-05-10", "2026-05-12")

        assertEquals(
            listOf(
                "my-whoop" to "2026-05-11", computed to "2026-05-09", computed to "2026-05-13",
                "other-noop" to "2026-05-11",
            ).sortedBy { it.first + it.second },
            rows("dailyMetric", "day"),
        )
    }

    @Test fun windowedDeleteDoesNotWipeOlderBleOnlyHistory() = runBlocking {
        val computed = "my-whoop-noop"
        for (day in 1..20) insert("dailyMetric", computed, "2026-05-%02d".format(day))

        repo.deleteComputedDailyInRange(computed, "2026-05-10", "2026-05-20")

        assertEquals((1..9).map { computed to "2026-05-%02d".format(it) }, rows("dailyMetric", "day"))
    }

    private fun insert(table: String, owner: String, value: Any) {
        db.prepareStatement("INSERT INTO `$table` VALUES (?, ?)").use {
            it.setString(1, owner)
            it.setObject(2, value)
            it.executeUpdate()
        }
    }

    private fun sql(query: String) { db.createStatement().use { it.execute(query) } }

    private fun rows(table: String, key: String): List<Pair<String, String>> =
        db.createStatement().use { statement ->
            statement.executeQuery("SELECT deviceId, `$key` FROM `$table`").use { cursor ->
                buildList { while (cursor.next()) add(cursor.getString(1) to cursor.getString(2)) }
                    .sortedBy { it.first + it.second }
            }
        }

    private fun executeDaoDelete(name: String, args: List<Any?>): Int {
        val declaration = Regex("suspend fun ${Regex.escape(name)}\\(([^)]*)\\)").find(daoSource)
            ?: error("DAO declaration $name not found")
        val parameters = declaration.groupValues[1].split(',').map { it.substringBefore(':').trim() }
        assertEquals("DAO argument count for $name", parameters.size, args.size)
        val annotationStart = daoSource.lastIndexOf("@Query(", declaration.range.first)
        check(annotationStart >= 0) { "No @Query for $name" }
        val annotation = daoSource.substring(annotationStart, declaration.range.first)
        val query = Regex("\"([^\"]*)\"").findAll(annotation).joinToString("") { it.groupValues[1] }
        check(query.startsWith("DELETE FROM ")) { "Expected literal production DELETE query for $name" }
        val bound = parameters.zip(args).toMap()
        val orderedArgs = mutableListOf<Any?>()
        val jdbcQuery = Regex(":([A-Za-z][A-Za-z0-9_]*)").replace(query) {
            val parameter = it.groupValues[1]
            check(bound.containsKey(parameter)) { "Unknown SQL parameter $parameter for $name" }
            orderedArgs += bound.getValue(parameter)
            "?"
        }
        return db.prepareStatement(jdbcQuery).use { statement ->
            orderedArgs.forEachIndexed { index, value -> statement.setObject(index + 1, value) }
            statement.executeUpdate()
        }
    }
}
