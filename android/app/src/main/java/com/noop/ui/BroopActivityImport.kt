package com.noop.ui

import com.noop.R

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.noop.data.LiftMuscle
import com.noop.ingest.CsvTable
import com.noop.ingest.HeaderNorm
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.w3c.dom.Element
import org.xml.sax.InputSource
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.StringReader
import java.text.Normalizer
import java.util.Locale
import java.util.zip.ZipInputStream
import javax.xml.parsers.DocumentBuilderFactory

/** Same row contracts, aliases, caps and warnings as StrandImport.LiftProgramSheetImporter. */
internal object BroopLiftProgramImporter {
    const val maxFileBytes = 8 * 1024 * 1024
    private const val maxPartBytes = 64 * 1024 * 1024
    data class Line(val exercise: String, val primary: LiftMuscle?, val secondary: List<LiftMuscle>, val sets: Int?,
        val reps: Int?, val weight: Double?, val rpe: Double?, val rest: Int?, val note: String?)
    data class Program(val name: String, val note: String?, val lines: List<Line>)
    data class Result(val programs: List<Program>, val warnings: List<String>)
    class ImportFailure(val reason: String) : IllegalArgumentException(reason)
    private data class Sheet(val headers: Set<String>, val rows: List<Map<String, String>>)
    fun number(raw: String): Double? {
        val clean = StringBuilder(); var separator = false
        for (ch in raw) {
            if (ch.isDigit()) clean.append(ch)
            else if ((ch == '.' || ch == ',') && !separator && clean.isNotEmpty()) { clean.append('.'); separator = true }
            else if (ch == '-' && clean.isEmpty()) clean.append(ch)
        }
        if (clean.none { it.isDigit() }) return null
        return clean.toString().toDoubleOrNull()
    }
    fun muscle(raw: String): LiftMuscle? {
        val normalized = Normalizer.normalize(raw, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
            .lowercase(Locale.US).filter { it.isLetterOrDigit() }
        return LiftMuscle.entries.firstOrNull { it.name.lowercase(Locale.US) == normalized }
    }
    fun parse(data: ByteArray): Result {
        if (data.size > maxFileBytes) throw ImportFailure("That file is too big to be a program sheet.")
        val sheets = if (data.size >= 4 && data[0] == 0x50.toByte() && data[1] == 0x4b.toByte()) xlsx(data)
            else CsvTable.fromData(data).let { listOf(Sheet(it.normalizedHeaders.toSet(), it.rows)) }
        val sheet = sheets.firstOrNull { it.headers.any { h -> h in listOf("exercise", "movement", "lift") } }
            ?: throw ImportFailure("The sheet needs an exercise column. Use the NOOP program template.")
        val programs = mutableListOf<Program>(); val indices = mutableMapOf<String, Int>(); val warnings = mutableListOf<String>()
        var truncated = false
        fun warn(index: Int, message: String) { if (warnings.size < 50) warnings += "Row ${index + 2}: $message" }
        fun value(row: Map<String, String>, vararg aliases: String): String? = aliases.firstNotNullOfOrNull { row[it]?.takeIf { v -> v.trim().isNotEmpty() } }
        fun double(row: Map<String, String>, vararg aliases: String) = value(row, *aliases)?.let(::number)
        fun integer(row: Map<String, String>, vararg aliases: String) = double(row, *aliases)?.let {
            val n = if (it >= 0) kotlin.math.floor(it + 0.5) else kotlin.math.ceil(it - 0.5)
            n.takeIf { v -> v.isFinite() && v >= Int.MIN_VALUE && v <= Int.MAX_VALUE }?.toInt()
        }
        sheet.rows.take(5000).forEachIndexed { i, row ->
            val exercise = value(row, "exercise", "movement", "lift")?.trim().orEmpty()
            if (exercise.isBlank()) { if (row.values.any { it.isNotBlank() }) warn(i, "no exercise name, so the row was skipped"); return@forEachIndexed }
            val name = value(row, "program", "programme", "workout", "routine", "day")?.trim() ?: "Imported program"
            val primaryText = value(row, "primary_muscle", "primary", "muscle")?.trim()
            val primary = primaryText?.let(::muscle)
            if (primaryText != null && primary == null) warn(i, "\"$primaryText\" is not a muscle group, so \"$exercise\" was left unclassified")
            val secondary = mutableListOf<LiftMuscle>()
            value(row, "secondary_muscles", "secondary_muscle", "secondary")?.split(',', ';', '/', '|')?.forEach { raw ->
                val token = raw.trim(); if (token.isNotEmpty()) {
                    val m = muscle(token)
                    if (m == null) warn(i, "\"$token\" is not a muscle group and was ignored")
                    else if (m != primary && m !in secondary) secondary += m
                }
            }
            var rpe = double(row, "target_max_rpe", "max_rpe", "rpe_max", "target_rpe", "rpe")
            if (rpe != null && rpe !in 1.0..10.0) {
                val shown = if (rpe == kotlin.math.floor(rpe)) rpe.toInt().toString() else rpe.toString()
                warn(i, "max RPE $shown is not between 1 and 10, so \"$exercise\" has none"); rpe = null
            }
            val line = Line(exercise, primary, secondary, integer(row, "sets", "working_sets", "target_sets"),
                integer(row, "reps", "rep", "target_reps", "repetitions"), double(row, "weight_kg", "weight", "kg", "load", "load_kg"),
                rpe, integer(row, "rest_sec", "rest_seconds", "rest", "rest_s"), value(row, "note", "technique_note", "notes", "cue")?.trim()?.take(200))
            val note = value(row, "program_note", "programme_note", "workout_note", "routine_note")?.trim()?.take(120)
            val index = indices[name.lowercase(Locale.US)]
            if (index != null) {
                val program = programs[index]
                if (program.lines.size >= 200) truncated = true else programs[index] = program.copy(note = program.note ?: note, lines = program.lines + line)
            } else if (programs.size >= 50) truncated = true
            else { indices[name.lowercase(Locale.US)] = programs.size; programs += Program(name, note, listOf(line)) }
        }
        if (sheet.rows.size > 5000 || truncated) warnings += "The sheet is larger than a program can be, so only the first 50 programs and 200 exercises each were read."
        if (programs.isEmpty()) throw ImportFailure("That sheet has no exercises in it yet.")
        return Result(programs, warnings)
    }

    private fun xml(bytes: ByteArray): org.w3c.dom.Document {
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        runCatching { factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
        runCatching { factory.setFeature("http://xml.org/sax/features/external-general-entities", false) }
        runCatching { factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        val builder = factory.newDocumentBuilder()
        builder.setEntityResolver { _, _ -> InputSource(StringReader("")) }
        return builder.parse(ByteArrayInputStream(bytes))
    }
    private fun org.w3c.dom.Node.elements(name: String): List<Element> {
        val list = when (this) { is Element -> getElementsByTagNameNS("*", name); is org.w3c.dom.Document -> getElementsByTagNameNS("*", name); else -> return emptyList() }
        return (0 until list.length).mapNotNull { list.item(it) as? Element }
    }
    private fun xlsx(data: ByteArray): List<Sheet> {
        val parts = mutableMapOf<String, ByteArray>(); var total = 0L
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val wanted = entry.name == "xl/sharedStrings.xml" || entry.name == "xl/workbook.xml" || entry.name == "xl/_rels/workbook.xml.rels" || entry.name.startsWith("xl/worksheets/") && entry.name.endsWith(".xml")
                val out = if (wanted) ByteArrayOutputStream() else null
                val buffer = ByteArray(64 * 1024); var size = 0
                while (true) {
                    val n = zip.read(buffer); if (n < 0) break
                    size += n; total += n
                    if (size > maxPartBytes || total > 128L * 1024 * 1024) throw ImportFailure("That file is too big to be a program sheet.")
                    out?.write(buffer, 0, n)
                }
                if (out != null) parts[entry.name] = out.toByteArray()
            }
        }
        val shared = parts["xl/sharedStrings.xml"]?.let { xml(it).elements("si").map { si -> si.elements("t").joinToString("") { it.textContent } } }.orEmpty()
        val targets = parts["xl/_rels/workbook.xml.rels"]?.let { xml(it).elements("Relationship").associate { it.getAttribute("Id") to it.getAttribute("Target") } }.orEmpty()
        val ordered = parts["xl/workbook.xml"]?.let { bytes -> xml(bytes).elements("sheet").mapNotNull { sheet ->
            targets[sheet.getAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "id")]?.let { target -> if (target.startsWith('/')) target.drop(1) else "xl/$target" }
        } }.orEmpty().ifEmpty { parts.keys.filter { it.startsWith("xl/worksheets/") }.sorted() }
        if (ordered.isEmpty()) throw ImportFailure("That file is not a spreadsheet this importer can read.")
        return ordered.mapNotNull { path -> parts[path]?.let { bytes ->
            val grid = xml(bytes).elements("row").map { row ->
                val cells = mutableListOf<String>()
                row.elements("c").forEach { cell ->
                    val letters = cell.getAttribute("r").takeWhile { it.uppercaseChar() in 'A'..'Z' }
                    var column = if (letters.isEmpty()) cells.size else letters.fold(0) { index, ch -> index * 26 + (ch.uppercaseChar() - 'A' + 1) } - 1
                    // XFD is Excel's last legal column; retaining it avoids unbounded sparse allocation.
                    if (column > 16_383 || column < 0) throw ImportFailure("That worksheet contains an invalid cell reference.")
                    while (cells.size <= column) cells += ""
                    val raw = (cell.elements("v") + cell.elements("t")).joinToString("") { it.textContent }
                    cells[column] = if (cell.getAttribute("t") == "s") raw.toIntOrNull()?.let { shared.getOrNull(it) } ?: raw else raw
                }
                cells
            }
            val headers = grid.firstOrNull().orEmpty().map(HeaderNorm::normalize)
            Sheet(headers.filter { it.isNotEmpty() }.toSet(), grid.drop(1).filter { row -> row.any { it.isNotBlank() } }.map { cells ->
                val row = linkedMapOf<String, String>()
                headers.forEachIndexed { i, key -> if (key.isNotBlank() && row[key].isNullOrEmpty()) row[key] = cells.getOrNull(i) ?: "" }
                row
            })
        } }
    }
}

@Composable
internal fun BroopLiftImportSheet(store: BroopLiftStore, onClose: () -> Unit, onImported: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var result by remember { mutableStateOf<BroopLiftProgramImporter.Result?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) { busy = true; scope.launch { try {
            result = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    val out = ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (true) { val n = input.read(buffer); if (n < 0) break
                        if (out.size() + n > BroopLiftProgramImporter.maxFileBytes) throw BroopLiftProgramImporter.ImportFailure(uiString(R.string.broop_body_that_file_is_too_big_to_be_a_program_sheet_4b84d8f))
                        out.write(buffer, 0, n)
                    }
                    BroopLiftProgramImporter.parse(out.toByteArray())
                } ?: throw BroopLiftProgramImporter.ImportFailure(uiString(R.string.broop_body_the_selected_file_could_not_be_opened_87d1ed4))
            }
            error = null
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: BroopLiftProgramImporter.ImportFailure) { error = failure.reason }
        catch (_: Exception) { error = uiString(R.string.broop_body_that_file_could_not_be_read_choose_a_csv_or_x_92bde33) }
        finally { busy = false } } }
    }
    Dialog(onDismissRequest = { if (!busy) onClose() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BroopPage(uiString(R.string.broop_body_import_programs_3ea1d93), { if (!busy) onClose() }) {
            Text(uiString(R.string.broop_body_fill_the_noop_program_template_in_excel_numbe_b136453), style = BroopType.body, color = BroopPalette.textBody)
            Text(uiString(R.string.broop_body_nothing_is_saved_until_you_review_the_file_be_82d847a), style = BroopType.caption, color = BroopPalette.textSecondary)
            BroopBodyButton(if (busy) uiString(R.string.broop_body_reading_ae18b70) else uiString(R.string.broop_body_choose_a_file_74b1d89), !busy) { picker.launch(arrayOf("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "text/*", "application/octet-stream")) }
            result?.let { parsed ->
                BroopSection(uiString(R.string.broop_body_what_the_file_will_create_07b81c9))
                parsed.programs.forEach { program -> BroopCard {
                    BroopCaps(program.name)
                    program.lines.forEach { line -> BroopBodyValue(line.exercise, listOfNotNull(line.sets?.let { uiString(R.string.broop_body_1_s_sets_75c7fc6, (it).toString()) }, line.reps?.let { uiString(R.string.broop_body_1_s_reps_043529a, (it).toString()) }, line.weight?.let { "${broopOne(it)} kg" }).joinToString(" · ")) }
                } }
                if (parsed.warnings.isNotEmpty()) { BroopSection(uiString(R.string.broop_body_worth_checking_59cd52e)); parsed.warnings.forEach { Text(it, style = BroopType.body, color = BroopPalette.warning) } }
                BroopBodyButton(if (busy) uiString(R.string.onboarding_importing) else uiString(R.string.broop_body_import_1_s_programs_55844f7, (parsed.programs.size).toString()), !busy) {
                    busy = true; scope.launch { try { store.importPrograms(parsed); onImported() }
                        catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
                        catch (_: Exception) { error = uiString(R.string.broop_body_the_programs_were_not_imported_please_try_aga_49f7331) }
                        finally { busy = false } }
                }
            }
            error?.let { Text(it, style = BroopType.body, color = BroopPalette.warning) }
        }
    }
}
