package com.noop.analytics

import com.noop.data.HrSample
import org.junit.Assert.*
import org.junit.Test
import java.util.Locale
import kotlin.math.ln

class BroopStressRestParityTest {
    private fun f(value: Double?): String = value?.let { String.format(Locale.US, "%.9f", it) } ?: "nil"

    @Test fun stressAndRestMatchActualSwiftOracle() {
        val lines = ArrayList<String>()
        for (delta in listOf(-40.0,-15.0,-1.0,0.0,7.5,15.0,30.0,80.0)) {
            lines.add("wake $delta ${f(StressMonitor.wakeLevel(60+delta,60.0))}")
        }
        val night=StressMonitor.NightAggregate(52.0,2.0,ln(60.0),0.2)
        for (z in listOf(-8.0,-2.0,0.0,0.5,1.0,2.0,3.0,8.0)) lines.add("sleep $z ${f(StressMonitor.sleepLevel(z))}")
        for (hr in listOf(48.0,52.0,56.0,70.0)) for (rr in listOf(null,30.0,60.0,90.0)) {
            lines.add("z $hr ${f(rr)} ${f(StressMonitor.sleepZ(hr,rr,night))}")
        }
        for (count in listOf(0,3,4,14,18)) {
            val ref=StressMonitor.wakeReference((0 until count).map { (50+it).toDouble() },70.0)
            lines.add("ref $count ${f(ref?.floorHR)} ${ref?.personal == true} ${ref?.days ?: -1}")
        }
        val day0=1700006400L
        for (bpm in listOf(52,60,68,75,90)) {
            val samples=(0 until 10800).map { HrSample("fixture",day0+it,if (it<3600) 52 else bpm) }
            val main=StressMonitor.Interval(day0,day0+3600)
            val activity=StressMonitor.Interval(day0+7200,day0+7500)
            val input=StressMonitor.DayInput("2023-11-15",day0,day0+10800,0,samples,emptyList(),emptyList(),listOf(main),main,listOf(activity))
            val result=StressMonitor.analyzeDay(input,List(14) { 60.0 },List(14) { night })
            val s=result.summary
            val states=result.epochs.joinToString(",") { when(it.state) {
                StressMonitor.EpochState.WAKING -> "waking"
                StressMonitor.EpochState.SLEEP -> "sleep"
                StressMonitor.EpochState.ACTIVITY -> "activity"
                StressMonitor.EpochState.NO_DATA -> "noData"
            } }
            lines.add("day $bpm ${f(s.meanLevel)} ${s.highMin} ${s.medMin} ${s.lowMin} ${s.scoredMin} ${f(s.sleepStressPct)} $states")
        }
        for (hours in listOf(0.0,5.5,8.0,10.0)) for (c in listOf(null,0.25,0.8,1.0)) for (stress in listOf(null,0.0,5.0,30.0,100.0)) {
            val p=RestPerformanceV2.parts(hours*3600,0.9,8.0,c,stress)
            lines.add("rest $hours ${f(c)} ${f(stress)} ${f(RestPerformanceV2.composite(p))}")
        }
        assertEquals(swiftOracle,lines.joinToString("\n"))
    }

    @Test fun identicalHeartRatePacketsCountAndSilenceClearsTheWindow() {
        val window=StressMonitor.LiveWindow()
        val ref=StressMonitor.WakeReference(60.0,true,14)
        for (second in 0L until 30L) window.receive(60.0,second)
        assertTrue(window.reading(ref) is StressMonitor.LiveReading.Level)
        window.receive(75.0,29L)
        assertEquals(60.5,window.meanHR!!,1e-12)
        window.expire(44)
        assertNull(window.meanHR)
        assertNull(window.reading(ref))
    }

    @Test fun sparseSleepDoesNotClaimWholeNightCoverage() {
        val main=StressMonitor.Interval(0,8*3600)
        val samples=(0 until 3600).map { HrSample("fixture",it.toLong(),70) }
        val result=StressMonitor.analyzeDay(StressMonitor.DayInput("2026-10-19",0,8*3600,0,
            samples,emptyList(),emptyList(),listOf(main),main,emptyList()), emptyList(), emptyList())
        assertNull(result.summary.sleepStressPct)
        assertEquals(StressMonitor.EpochState.SLEEP,result.epochs.last().state)
        assertNull(result.epochs.last().level)
    }

    companion object {
        // Verbatim stdout from actual Swift StressMonitor + AnalyticsEngine.RestV2, generated 2026-10-19.
        // Reproduce: swift run --package-path Tools/BroopParity Oracle
        private val swiftOracle = """
            wake -40.0 0.036748967
            wake -15.0 0.333333333
            wake -1.0 0.939364062
            wake 0.0 1.000000000
            wake 7.5 1.500000000
            wake 15.0 2.000000000
            wake 30.0 2.666666667
            wake 80.0 2.996313361
            sleep -8.0 0.000493879
            sleep -2.0 0.081219294
            sleep 0.0 0.400000000
            sleep 0.5 0.572636137
            sleep 1.0 0.796942417
            sleep 2.0 1.378887268
            sleep 3.0 2.000000000
            sleep 8.0 2.979274346
            z 48.0 nil -2.000000000
            z 48.0 30.000000000 1.036431796
            z 48.0 60.000000000 -1.414213562
            z 48.0 90.000000000 -2.847749200
            z 52.0 nil 0.000000000
            z 52.0 30.000000000 2.450645359
            z 52.0 60.000000000 0.000000000
            z 52.0 90.000000000 -1.433535637
            z 56.0 nil 2.000000000
            z 56.0 30.000000000 3.864858921
            z 56.0 60.000000000 1.414213562
            z 56.0 90.000000000 -0.019322075
            z 70.0 nil 9.000000000
            z 70.0 30.000000000 8.814606389
            z 70.0 60.000000000 6.363961031
            z 70.0 90.000000000 4.930425393
            ref 0 70.000000000 false 0
            ref 3 70.000000000 false 0
            ref 4 51.500000000 true 4
            ref 14 56.500000000 true 14
            ref 18 60.500000000 true 14
            day 52 0.578126415 0 0 115 115 0.000000000 sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,activity,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking
            day 60 1.000000000 0 115 0 115 0.000000000 sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,activity,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking
            day 68 1.534651193 0 115 0 115 0.000000000 sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,activity,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking
            day 75 2.000000000 100 0 0 100 0.000000000 sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,activity,activity,activity,activity,waking,waking,waking,waking,waking,waking,waking,waking
            day 90 2.666666667 100 0 0 100 0.000000000 sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,sleep,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,waking,activity,activity,activity,activity,waking,waking,waking,waking,waking,waking,waking,waking
            rest 0.0 nil nil 19.290000000
            rest 0.0 nil 0.000000000 33.530000000
            rest 0.0 nil 5.000000000 30.590000000
            rest 0.0 nil 30.000000000 15.880000000
            rest 0.0 nil 100.000000000 15.880000000
            rest 0.0 0.250000000 nil 20.290000000
            rest 0.0 0.250000000 0.000000000 32.250000000
            rest 0.0 0.250000000 5.000000000 29.750000000
            rest 0.0 0.250000000 30.000000000 17.250000000
            rest 0.0 0.250000000 100.000000000 17.250000000
            rest 0.0 0.800000000 nil 30.000000000
            rest 0.0 0.800000000 0.000000000 40.500000000
            rest 0.0 0.800000000 5.000000000 38.000000000
            rest 0.0 0.800000000 30.000000000 25.500000000
            rest 0.0 0.800000000 100.000000000 25.500000000
            rest 0.0 1.000000000 nil 33.530000000
            rest 0.0 1.000000000 0.000000000 43.500000000
            rest 0.0 1.000000000 5.000000000 41.000000000
            rest 0.0 1.000000000 30.000000000 28.500000000
            rest 0.0 1.000000000 100.000000000 28.500000000
            rest 5.5 nil nil 73.300000000
            rest 5.5 nil 0.000000000 78.010000000
            rest 5.5 nil 5.000000000 75.070000000
            rest 5.5 nil 30.000000000 60.370000000
            rest 5.5 nil 100.000000000 60.370000000
            rest 5.5 0.250000000 nil 64.780000000
            rest 5.5 0.250000000 0.000000000 70.060000000
            rest 5.5 0.250000000 5.000000000 67.560000000
            rest 5.5 0.250000000 30.000000000 55.060000000
            rest 5.5 0.250000000 100.000000000 55.060000000
            rest 5.5 0.800000000 nil 74.490000000
            rest 5.5 0.800000000 0.000000000 78.310000000
            rest 5.5 0.800000000 5.000000000 75.810000000
            rest 5.5 0.800000000 30.000000000 63.310000000
            rest 5.5 0.800000000 100.000000000 63.310000000
            rest 5.5 1.000000000 nil 78.010000000
            rest 5.5 1.000000000 0.000000000 81.310000000
            rest 5.5 1.000000000 5.000000000 78.810000000
            rest 5.5 1.000000000 30.000000000 66.310000000
            rest 5.5 1.000000000 100.000000000 66.310000000
            rest 8.0 nil nil 97.860000000
            rest 8.0 nil 0.000000000 98.240000000
            rest 8.0 nil 5.000000000 95.290000000
            rest 8.0 nil 30.000000000 80.590000000
            rest 8.0 nil 100.000000000 80.590000000
            rest 8.0 0.250000000 nil 85.000000000
            rest 8.0 0.250000000 0.000000000 87.250000000
            rest 8.0 0.250000000 5.000000000 84.750000000
            rest 8.0 0.250000000 30.000000000 72.250000000
            rest 8.0 0.250000000 100.000000000 72.250000000
            rest 8.0 0.800000000 nil 94.710000000
            rest 8.0 0.800000000 0.000000000 95.500000000
            rest 8.0 0.800000000 5.000000000 93.000000000
            rest 8.0 0.800000000 30.000000000 80.500000000
            rest 8.0 0.800000000 100.000000000 80.500000000
            rest 8.0 1.000000000 nil 98.240000000
            rest 8.0 1.000000000 0.000000000 98.500000000
            rest 8.0 1.000000000 5.000000000 96.000000000
            rest 8.0 1.000000000 30.000000000 83.500000000
            rest 8.0 1.000000000 100.000000000 83.500000000
            rest 10.0 nil nil 97.860000000
            rest 10.0 nil 0.000000000 98.240000000
            rest 10.0 nil 5.000000000 95.290000000
            rest 10.0 nil 30.000000000 80.590000000
            rest 10.0 nil 100.000000000 80.590000000
            rest 10.0 0.250000000 nil 85.000000000
            rest 10.0 0.250000000 0.000000000 87.250000000
            rest 10.0 0.250000000 5.000000000 84.750000000
            rest 10.0 0.250000000 30.000000000 72.250000000
            rest 10.0 0.250000000 100.000000000 72.250000000
            rest 10.0 0.800000000 nil 94.710000000
            rest 10.0 0.800000000 0.000000000 95.500000000
            rest 10.0 0.800000000 5.000000000 93.000000000
            rest 10.0 0.800000000 30.000000000 80.500000000
            rest 10.0 0.800000000 100.000000000 80.500000000
            rest 10.0 1.000000000 nil 98.240000000
            rest 10.0 1.000000000 0.000000000 98.500000000
            rest 10.0 1.000000000 5.000000000 96.000000000
            rest 10.0 1.000000000 30.000000000 83.500000000
            rest 10.0 1.000000000 100.000000000 83.500000000
        """.trimIndent()
    }
}
