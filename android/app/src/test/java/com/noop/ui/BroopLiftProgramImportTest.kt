package com.noop.ui

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BroopLiftProgramImportTest {
    /** Literal output of the Swift LiftProgramSheetImporter over the same CSV fixture. */
    @Test fun csvMatchesSwiftOracleIncludingWarningsAndRowOrder() {
        val bytes = javaClass.getResourceAsStream("/broop_lift_programs.csv")!!.use { it.readBytes() }
        val parsed = BroopLiftProgramImporter.parse(bytes)
        val lines = mutableListOf<String>()
        for (program in parsed.programs) {
            lines += "PROGRAM|${program.name}|${program.note ?: "nil"}"
            for (line in program.lines) lines += listOf(line.exercise, line.primary?.name ?: "nil", line.secondary.joinToString(",") { it.name },
                line.sets?.toString() ?: "nil", line.reps?.toString() ?: "nil", line.weight?.toString() ?: "nil", line.rpe?.toString() ?: "nil",
                line.rest?.toString() ?: "nil", line.note ?: "nil").joinToString("|")
        }
        parsed.warnings.forEach { lines += "WARNING|$it" }
        assertEquals("""
            PROGRAM|Upper A|Build carefully
            Bench press|chest|triceps,frontDelts|3|8|60.5|8.0|90|Pause at chest
            Row|upperBack|lats,biceps|4|10|55.0|nil|120|nil
            Fly|nil|neck|2|12|10.0|7.0|60|nil
            PROGRAM|Lower|nil
            Squat|quads|glutes,hamstrings|4|5|-10.5|2.5|90|nil
            WARNING|Row 3: max RPE 12 is not between 1 and 10, so "Row" has none
            WARNING|Row 5: no exercise name, so the row was skipped
            WARNING|Row 6: "Shoulders" is not a muscle group, so "Fly" was left unclassified
            WARNING|Row 6: "Unknown" is not a muscle group and was ignored
        """.trimIndent(), lines.joinToString("\n"))
    }

    @Test fun xlsxUsesWorkbookOrderSharedRichStringsAndSparseCellColumns() {
        val parts = linkedMapOf(
            "xl/workbook.xml" to """<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Notes" r:id="rId2"/><sheet name="Program" r:id="rId1"/></sheets></workbook>""",
            "xl/_rels/workbook.xml.rels" to """<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>""",
            "xl/sharedStrings.xml" to """<sst><si><r><t>Tra</t></r><r><t>vel</t></r></si><si><t>Deadlift</t></si></sst>""",
            "xl/worksheets/sheet2.xml" to """<worksheet><sheetData><row><c r="A1" t="inlineStr"><is><t>Instructions</t></is></c></row></sheetData></worksheet>""",
            "xl/worksheets/sheet1.xml" to """<worksheet><sheetData><row><c r="B1" t="inlineStr"><is><t>Program</t></is></c><c r="D1" t="inlineStr"><is><t>Exercise</t></is></c><c r="F1" t="inlineStr"><is><t>Weight kg</t></is></c></row><row><c r="B2" t="s"><v>0</v></c><c r="D2" t="s"><v>1</v></c><c r="F2"><f>10*5</f><v>50</v></c></row></sheetData></worksheet>""",
        )
        val bytes = ByteArrayOutputStream().also { out -> ZipOutputStream(out).use { zip -> parts.forEach { (name,xml) ->
            zip.putNextEntry(ZipEntry(name)); zip.write(xml.toByteArray()); zip.closeEntry()
        } } }.toByteArray()
        val program = BroopLiftProgramImporter.parse(bytes).programs.single()
        assertEquals("Travel", program.name)
        assertEquals("Deadlift", program.lines.single().exercise)
        assertEquals(50.0, program.lines.single().weight!!, 0.0)
        assertNull(program.lines.single().reps)
    }

    @Test fun oversizeAndEmptySheetsFailBeforeAnyWrite() {
        assertThrows(BroopLiftProgramImporter.ImportFailure::class.java) { BroopLiftProgramImporter.parse(ByteArray(BroopLiftProgramImporter.maxFileBytes + 1)) }
        assertThrows(BroopLiftProgramImporter.ImportFailure::class.java) { BroopLiftProgramImporter.parse("Exercise,Sets\n".toByteArray()) }
        assertThrows(BroopLiftProgramImporter.ImportFailure::class.java) { BroopLiftProgramImporter.parse("Not a program\nanything".toByteArray()) }
    }
}
