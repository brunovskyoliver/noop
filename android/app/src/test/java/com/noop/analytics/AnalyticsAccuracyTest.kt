package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.WorkoutRow
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class AnalyticsAccuracyTest {
    private val profile = UserProfile(66.0, 170.0, 19.0, "male")
    private fun number(value: Double) = String.format(Locale.US, "%.9f", value)
    private fun hr(ts: Long, bpm: Int = 50) = HrSample("strap", ts, bpm)

    @Test fun matchesSwiftProductionOracle() {
        // Verbatim stdout from accuracy_oracle.swift, compiled with swiftc -O against production packages.
        val expected = """
            energy|82800|50|0.000000000|1610.508875000|82800.000000000|0|40992a0916872b00
            energy|82800|140|14940.981564785|16551.490439785|82800.000000000|40cd2e7da3ea358c|40d029df635d8d76
            energy|82800|170|21183.634528456|22794.143403456|82800.000000000|40d4afe89c1d3e13|40d642892d85b0c3
            energy|86400|50|0.000000000|1680.531000000|86400.000000000|0|409a421fbe76c8b3
            energy|86400|140|15590.589458907|17271.120458907|86400.000000000|40ce734b7363b30c|40d0ddc7b5994611
            energy|86400|170|22104.662116650|23785.193116650|86400.000000000|40d5962a601e83a3|40d73a4c5c05f02e
            energy|90000|50|0.000000000|1750.553125000|90000.000000000|0|409b5a3666666665
            energy|90000|140|16240.197353028|17990.750478028|90000.000000000|40cfb81942dd308c|40d191b007d4feac
            energy|90000|170|23025.689704844|24776.242829844|90000.000000000|40d67c6c241fc933|40d8320f8a862f99
            coverage|hourInDay|3600|86400|82800|0.041666667|false|3fa5555555555555
            coverage|elapsedHour|3600|3600|0|1.000000000|true|3ff0000000000000
            coverage|gaps|4|1000|898|0.004000000|false|3f70624dd2f1a9fc
            wake|false|0,1|510.000000000
            wake|true|0|420.000000000
            workout|1300|1000|1600|nil|nil
            workout|1600|1000|1600|9.500000000|80.000000000
        """.trimIndent()
        val rows = mutableListOf<String>()
        for (duration in listOf(82800, 86400, 90000)) { for (bpm in listOf(50,140,170)) {
            val e = Calories.estimateDayEnergy((0 until duration).map { hr(it.toLong(),bpm) }, profile,
                194.7, null, duration.toDouble())
            rows += "energy|$duration|$bpm|${number(e.activeKcal)}|${number(e.totalKcal)}|${number(e.observedSeconds)}|${java.lang.Long.toHexString(e.activeKcal.toRawBits())}|${java.lang.Long.toHexString(e.totalKcal.toRawBits())}"
        }}
        for ((name, values, length) in listOf(Triple("hourInDay", (0L until 3600).toList(), 86400L),
            Triple("elapsedHour", (0L until 3600).toList(), 3600L), Triple("gaps", listOf(0L,0,10,100,999), 1000L))) {
            val c = HRInputCoverage.measure(values.map { hr(it, 100) }, 0, length)
            rows += "coverage|$name|${c.recordedSeconds}|${c.expectedSeconds}|${c.longestGapSeconds}|${number(c.fraction)}|${c.isComplete}|${java.lang.Long.toHexString(c.fraction.toRawBits())}"
        }
        val start = -10800L; val wake = 14400L
        for (confirmed in listOf(false, true)) {
            val blocks = listOf(SleepStageTotals.NightBlock(start, wake, confirmed), SleepStageTotals.NightBlock(wake+1800, wake+7200))
            val group = SleepStageTotals.mainNightGroupIndices(blocks, 0).orEmpty()
            val agg = SleepStageTotals.dailyAggregateHonoringEdits(
                listOf(start to "{\"light\":420}", wake+1800 to "{\"light\":90}"), mapOf(start to "{\"light\":420}"),
                onsetByStart = mapOf(start to start, wake+1800 to wake+1800), confirmedBounds = if (confirmed) setOf(start) else emptySet())!!
            rows += "wake|$confirmed|${group.joinToString(",")}|${number(agg.sleep.totalSleepMin!!)}"
        }
        for (end in listOf(1300L, 1600L)) {
            val real = WorkoutRow("strap", 1000, 1600, "Strength Training", "manual", durationS=600.0)
            val r = IntelligenceEngine.backfillWorkoutFromDetectedBout(real,150,170,80.0,9.5,boutBounds=1000L to end)
            rows += "workout|$end|${r.startTs}|${r.endTs}|${r.strain?.let(::number) ?: "nil"}|${r.energyKcal?.let(::number) ?: "nil"}"
        }
        assertEquals(expected, rows.joinToString("\n"))
    }

    @Test fun oneHourDoesNotMakeWholeDayConfidenceSolid() {
        val start = AnalyticsEngine.dayStartUtcSeconds("2026-10-28")
        val samples = (0L until 3600L).map { hr(start+it, 120) }
        val r = AnalyticsEngine.analyzeDay("2026-10-28", hr=samples, dayHr=samples, profile=profile,
            dayBounds=start to start+86400)
        assertEquals(ScoreConfidence.BUILDING, r.effortConfidence)
        assertEquals(82800, r.hrCoverage!!.longestGapSeconds)
        val elapsed = AnalyticsEngine.analyzeDay("2026-10-28", hr=samples, dayHr=samples, profile=profile,
            dayBounds=start to start+3600)
        assertEquals(ScoreConfidence.SOLID, elapsed.effortConfidence)
    }

    @Test fun calendarEnergyExcludesNeighbouringSamplesOnFallBackDay() {
        val w = LocalDayWindows(java.time.ZoneId.of("Europe/Copenhagen")).window(LocalCalendarDate(2026,10,25))!!
        val a = w.start.epochSecond; val b = w.nextStart.epochSecond
        val samples = listOf(hr(a-1,170)) + (a until b).map { hr(it) } + listOf(hr(b,170))
        val r = AnalyticsEngine.analyzeDay("2026-10-25", dayHr=samples, profile=profile, dayBounds=a to b)
        assertEquals(0.0, r.activeEnergyKcal!!, 0.0)
        assertEquals(90000, r.hrCoverage!!.expectedSeconds)
        assertEquals(1750.553125, r.daily.activeKcalEst!!, 1e-8)
    }

    @Test fun confirmedEarlyWakeFlowsThroughScoringSelection() {
        val m = AnalyticsEngine.dayStartUtcSeconds("2026-10-28")
        val a = m-10800; val b = m+14400
        fun session(start: Long, end: Long) = DetectedSleep(start,end,1.0,listOf(StageSegment(start,end,"light")),null,null)
        val r = AnalyticsEngine.analyzeDay("2026-10-28", profile=profile,
            providedSleep=listOf(session(b+1800,b+7200),session(a,b)), confirmedSleepStarts=setOf(a))
        assertEquals(420.0, r.daily.totalSleepMin!!, 0.0)
        assertEquals(listOf(b), r.mainNightBlocks.map { it.end })
    }

    @Test fun fragmentsRemainSuggestionsAndCannotBackfillWholeSession() {
        val bouts = (0..2).map { i -> ExerciseSession(i*600L,(i+1)*600L,150.0,170,9.5,600.0,
            emptyMap(),null,194.7,"tanaka",80.0,334.72) }
        val backfills = mutableListOf<WorkoutRow>()
        val whole = WorkoutRow("strap",0,1800,"Strength Training","manual")
        IntelligenceEngine.routeDetectedBouts("2026-10-28",null,bouts,listOf(whole),{},null,backfills)
        assertTrue(backfills.isEmpty())
        assertTrue(backfills.isEmpty())
        IntelligenceEngine.routeDetectedBouts("2026-10-28",null,bouts,emptyList(),{},null,backfills)
        assertTrue(backfills.isEmpty())
    }
    @Test fun storedTimeEditWitnessControlsGrouping() {
        val row = com.noop.data.SleepSession(deviceId="strap", startTs=0, endTs=25200,
            efficiency=1.0, restingHr=null, avgHrv=null, stagesJSON=null, userEdited=true, startTsAdjusted=0)
        val tail = SleepStageTotals.NightBlock(27000,32400)
        val confirmed = SleepStageTotals.NightBlock.fromSession(row)
        assertEquals(listOf(0), SleepStageTotals.mainNightGroupIndices(listOf(confirmed,tail),0))
        val stageOnly = SleepStageTotals.NightBlock.fromSession(row.copy(startTsAdjusted=null))
        assertEquals(listOf(0,1), SleepStageTotals.mainNightGroupIndices(listOf(stageOnly,tail),0))
    }

    @Test fun activeCaloriesCannotUseLegacyTotalEnergy() {
        val day = com.noop.data.DailyMetric("strap", "2026-10-28", activeKcalEst=1200.0)
        assertNull(com.noop.data.WhoopRepository.dailyColumn("active_kcal",day))
        assertEquals(1200.0, com.noop.data.WhoopRepository.dailyColumn("energy_kcal",day)!!,0.0)
        assertEquals(listOf("apple-health|active_kcal","health-connect|active_kcal","strap-noop|active_energy_kcal"),
            com.noop.data.WhoopRepository.sourceCandidates("active_kcal","apple-health","strap").map { it.source+"|"+it.key })
    }

}
