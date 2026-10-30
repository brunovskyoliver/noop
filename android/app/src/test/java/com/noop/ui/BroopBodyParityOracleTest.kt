package com.noop.ui

import com.noop.analytics.BroopEnergyEngine
import com.noop.analytics.BroopMindDay
import com.noop.analytics.BroopMindEngine
import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.util.Locale

/** Expected literal is stdout from swiftc -O over the repository's unmodified Swift engine sources.
 * Reproduce with test/resources/broop_body_oracle_{types,main}.swift and EnergyReservoir, MindEngine,
 * MindCheckIn, CorrelationEngine, CircadianEngine, plus Strand/Data/JetLagTrip.swift's value type.
 * Type scaffolding supplies only the external Epoch/Reference shapes and existing calendar/zone helpers.
 */
class BroopBodyParityOracleTest {
    private fun f(x: Double?): String = x?.let { String.format(Locale.US, "%.12f", it) } ?: "nil"
    @Test fun energyMindAndTravelMatchSwiftStdout() {
        val lines = mutableListOf<String>()
        val heart = BroopEnergyEngine.HeartProfile(50.0, 190.0)
        data class Case(val state: BroopEnergyEngine.State, val level: Double, val hr: Double, val run: Int)
        val cases = listOf(Case(BroopEnergyEngine.State.SLEEP, 0.4, 60.0, 0), Case(BroopEnergyEngine.State.SLEEP, 1.2, 60.0, 0),
            Case(BroopEnergyEngine.State.WAKING, 0.5, 60.0, 2), Case(BroopEnergyEngine.State.WAKING, 2.5, 60.0, 0),
            Case(BroopEnergyEngine.State.ACTIVITY, 0.0, 148.0, 0), Case(BroopEnergyEngine.State.NO_DATA, 0.0, 60.0, 0))
        for (start in listOf(0.0, 30.0, 50.0, 99.0, 100.0)) for (c in cases) {
            val ep = BroopEnergyEngine.Epoch(0, c.state, c.level, c.hr, false)
            val s = BroopEnergyEngine.step(start, ep, c.run, heart)
            lines += listOf(f(s.level), s.kind.name.lowercase(), f(s.charge), f(s.stress), f(s.activity), f(s.baseline)).joinToString("|")
        }
        val epochs = (0 until 288).map { i ->
            val state = when { i < 96 -> BroopEnergyEngine.State.SLEEP; i < 108 -> BroopEnergyEngine.State.ACTIVITY
                i % 17 == 0 -> BroopEnergyEngine.State.NO_DATA; else -> BroopEnergyEngine.State.WAKING }
            BroopEnergyEngine.Epoch(i * 300L, state, if (state == BroopEnergyEngine.State.SLEEP) 0.6 else if (i % 3 == 0) 0.5 else 1.5, 148.0, i < 96)
        }
        val result = BroopEnergyEngine.day(BroopEnergyEngine.DayInput("2026-10-19", epochs, true, true), 40.0, heart)!!
        lines += "DAY|" + result.summary.storedPairs().joinToString("|") { (k,v) -> "$k=${f(v)}" }
        lines += "PROJECT|" + f(BroopEnergyEngine.projectNow(50.0, 100.0, 2.5, heart))
        val pss = mutableListOf<String>()
        for (a in 0..4) for (b in 0..4) for (c in 0..4) for (d in 0..4)
            pss += BroopMindEngine.score(BroopMindEngine.Form.PSS4, listOf(a,b,c,d)).toString()
        lines += "PSS|" + pss.joinToString(",")
        val days = (0 until 40).map { i -> BroopMindDay(LocalDate.parse("2026-09-10").plusDays(i.toLong()).toString(),
            (10 + i * 3).toDouble(), (250 - i * 2).toDouble(), 600.0, if (i % 5 == 0) null else (i % 30).toDouble(),
            (55 + i % 20).toDouble(), (30 + i % 40).toDouble()) }
        for (date in listOf("2026-09-15", "2026-09-23", "2026-10-01", "2026-10-19")) {
            val r = BroopMindEngine.resilience(days, date); val c = BroopMindEngine.cumulative(days, date)
            lines += listOf("MIND", date, f(r?.score), f(r?.highShare), f(r?.lowShare), f(r?.nightRecovery), r?.trend?.name?.lowercase() ?: "nil",
                f(c?.score), f(c?.daytimeLoad), f(c?.sleepLoad), f(c?.recoveryLoad), c?.trend?.name?.lowercase() ?: "nil").joinToString("|")
        }
        val scores = (0 until 6).map { LocalDate.parse("2026-03-01").plusDays(it * 28L).toString() to it.toDouble() }
        val signal = (0 until 180).map { LocalDate.parse("2026-02-01").plusDays(it.toLong()).toString() to (it * 2 + 13).toDouble() }
        val corr = BroopMindEngine.correlate(scores, signal, 30)
        lines += "CORR|${f(corr?.r)}|${corr?.n ?: 0}"
        for ((zone,date,offset) in listOf(Triple("Europe/Bratislava","2026-10-24",-240), Triple("America/Los_Angeles","2026-07-01",120), Triple("Pacific/Auckland","2026-10-19",-720))) {
            val plan = BroopJetLagTrip(LocalDate.parse(date),zone,offset,1410,450).resolve()
            lines += if (plan == null) "TRIP|nil" else "TRIP|${plan.direction.raw}|" + plan.days.joinToString(";") { day ->
                day.date.toString() + "|" + listOf(day.timing.targetSleepHour,day.timing.targetWakeHour,day.timing.brightLightStartHour,
                    day.timing.brightLightEndHour,day.timing.dimFromHour).joinToString("|") { f(it) }
            }
        }
        assertEquals(SWIFT_STDOUT, lines.joinToString("\n"))
    }

    @Test fun missingAndInvalidInputsNeverInventScores() {
        assertNull(BroopMindEngine.score(BroopMindEngine.Form.GAD2, listOf(3)))
        assertNull(BroopMindEngine.score(BroopMindEngine.Form.GAD2, listOf(3,4)))
        assertNull(BroopMindEngine.resilience(emptyList(), "2026-10-19"))
        assertNull(BroopMindEngine.cumulative((0..30).map { BroopMindDay("2026-10-19", charge=90.0) }, "2026-10-19"))
        assertNull(BroopEnergyEngine.day(BroopEnergyEngine.DayInput("2026-10-19", emptyList(),true,false), null, BroopEnergyEngine.HeartProfile(50.0,190.0)))
        assertNull(BroopEnergyEngine.fromStored("2026-10-19", mapOf("energy_end" to 80.0)))
        assertTrue(BroopMindEngine.isDue("2026-09-21", "2026-10-19"))
        assertFalse(BroopMindEngine.isDue("2026-09-22", "2026-10-19"))
    }

    companion object {
        private val SWIFT_STDOUT = """
            2.083333333333|sleep|2.083333333333|0.000000000000|0.000000000000|0.000000000000
            1.041666666667|sleep|1.041666666667|0.000000000000|0.000000000000|0.000000000000
            0.500000000000|rest|0.666666666667|0.000000000000|0.000000000000|0.166666666667
            0.000000000000|stress|0.000000000000|0.750000000000|0.000000000000|0.166666666667
            0.000000000000|activity|0.000000000000|0.000000000000|1.500000000000|0.166666666667
            0.000000000000|gap|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            31.458333333333|sleep|1.458333333333|0.000000000000|0.000000000000|0.000000000000
            30.729166666667|sleep|0.729166666667|0.000000000000|0.000000000000|0.000000000000
            30.300000000000|rest|0.466666666667|0.000000000000|0.000000000000|0.166666666667
            29.083333333333|stress|0.000000000000|0.750000000000|0.000000000000|0.166666666667
            28.333333333333|activity|0.000000000000|0.000000000000|1.500000000000|0.166666666667
            30.000000000000|gap|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            51.041666666667|sleep|1.041666666667|0.000000000000|0.000000000000|0.000000000000
            50.520833333333|sleep|0.520833333333|0.000000000000|0.000000000000|0.000000000000
            50.166666666667|rest|0.333333333333|0.000000000000|0.000000000000|0.166666666667
            49.083333333333|stress|0.000000000000|0.750000000000|0.000000000000|0.166666666667
            48.333333333333|activity|0.000000000000|0.000000000000|1.500000000000|0.166666666667
            50.000000000000|gap|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            99.020833333333|sleep|0.020833333333|0.000000000000|0.000000000000|0.000000000000
            99.010416666667|sleep|0.010416666667|0.000000000000|0.000000000000|0.000000000000
            98.840000000000|rest|0.006666666667|0.000000000000|0.000000000000|0.166666666667
            98.083333333333|stress|0.000000000000|0.750000000000|0.000000000000|0.166666666667
            97.333333333333|activity|0.000000000000|0.000000000000|1.500000000000|0.166666666667
            99.000000000000|gap|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            100.000000000000|sleep|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            100.000000000000|sleep|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            99.833333333333|awake|0.000000000000|0.000000000000|0.000000000000|0.166666666667
            99.083333333333|stress|0.000000000000|0.750000000000|0.000000000000|0.166666666667
            98.333333333333|activity|0.000000000000|0.000000000000|1.500000000000|0.166666666667
            100.000000000000|gap|0.000000000000|0.000000000000|0.000000000000|0.000000000000
            DAY|energy_start=40.000000000000|energy_end=13.160000000000|energy_peak=89.740000000000|energy_low=13.160000000000|energy_charged=49.740000000000|energy_drain_stress=28.250000000000|energy_drain_activity=18.000000000000|energy_drain_baseline=30.330000000000|energy_seeded=0.000000000000|energy_wake=89.740000000000
            PROJECT|44.500000000000
            PSS|8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,1,2,3,4,5,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,1,2,3,4,5,0,1,2,3,4,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,1,2,3,4,5,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,2,3,4,5,6,11,12,13,14,15,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8,3,4,5,6,7,12,13,14,15,16,11,12,13,14,15,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,11,12,13,14,15,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,10,11,12,13,14,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,9,10,11,12,13,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,8,9,10,11,12,7,8,9,10,11,6,7,8,9,10,5,6,7,8,9,4,5,6,7,8
            MIND|2026-09-15|nil|nil|nil|nil|nil|nil|nil|nil|nil|nil
            MIND|2026-09-23|63.303896103896|0.049166666667|0.395000000000|0.490000000000|steady|nil|nil|nil|nil|nil
            MIND|2026-10-01|63.054545454545|0.089166666667|0.368333333333|0.555714285714|steady|30.305555555556|0.172916666667|0.266176470588|0.590000000000|nil
            MIND|2026-10-19|58.597402597403|0.179166666667|0.308333333333|0.650000000000|steady|34.129032258065|0.341666666667|0.369000000000|0.320000000000|steady
            CORR|0.999995639338|6
            TRIP|delay|2026-10-18|0.500000000000|8.500000000000|21.500000000000|23.500000000000|8.500000000000;2026-10-19|1.500000000000|9.500000000000|22.500000000000|0.500000000000|9.500000000000;2026-10-20|2.500000000000|10.500000000000|23.500000000000|1.500000000000|10.500000000000;2026-10-21|3.500000000000|11.500000000000|0.500000000000|2.500000000000|11.500000000000;2026-10-22|4.500000000000|12.500000000000|1.500000000000|3.500000000000|12.500000000000;2026-10-23|5.500000000000|13.500000000000|2.500000000000|4.500000000000|13.500000000000
            TRIP|advance|2026-06-22|22.500000000000|6.500000000000|6.500000000000|8.500000000000|20.500000000000;2026-06-23|21.500000000000|5.500000000000|5.500000000000|7.500000000000|19.500000000000;2026-06-24|20.500000000000|4.500000000000|4.500000000000|6.500000000000|18.500000000000;2026-06-25|19.500000000000|3.500000000000|3.500000000000|5.500000000000|17.500000000000;2026-06-26|18.500000000000|2.500000000000|2.500000000000|4.500000000000|16.500000000000;2026-06-27|17.500000000000|1.500000000000|1.500000000000|3.500000000000|15.500000000000;2026-06-28|16.500000000000|0.500000000000|0.500000000000|2.500000000000|14.500000000000;2026-06-29|15.500000000000|23.500000000000|23.500000000000|1.500000000000|13.500000000000;2026-06-30|14.500000000000|22.500000000000|22.500000000000|0.500000000000|12.500000000000
            TRIP|nil
        """.trimIndent()
    }
}
