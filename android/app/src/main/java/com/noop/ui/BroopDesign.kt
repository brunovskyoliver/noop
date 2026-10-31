package com.noop.ui

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.noop.R
import java.util.Locale
import kotlin.math.roundToInt
import kotlin.math.cos
import kotlin.math.sin

/** Presentation tokens mirrored from StrandiOS/Broop/BroopDesign.swift. */
object BroopPalette {
    val bgTop = Color(0xFF283339)
    val bgMid = Color(0xFF13181C)
    val bgBottom = Color(0xFF0D1114)
    val card = Color(0xFF272B2E)
    val tile = Color(0xFF2B2F32)
    val row = Color(0xFF3E4245)
    val pillOuter = Color(0xFF30373F)
    val pillInner = Color(0xFF464A4D)
    val track = Color(0xFF2E353B)
    val hairline = Color.White.copy(alpha = 0.07f)
    val textPrimary = Color.White
    val textBody = Color(0xFFBABEC0)
    val textSecondary = Color(0xFF8F959A)
    val textTertiary = Color(0xFF5E666B)
    val bandHigh = Color(0xFF16EC06)
    val bandMid = Color(0xFFFFDE00)
    val bandLow = Color(0xFFFF0026)
    val effort = Color(0xFF0093E7)
    val rest = Color(0xFF7BA1BB)
    val teal = Color(0xFF5FEBA5)
    val connected = Color(0xFF1DE9A0)
    val warning = Color(0xFFF5A623)
    val avatarStart = Color(0xFF1FB4D1)
    val avatarEnd = Color(0xFF7EE8C0)
    val stageAwake = Color(0xFFE4E8EB)
    val stageREM = Color(0xFFB6CCDD)
    val stageLight = rest
    val stageDeep = Color(0xFF42627F)
    fun band(value: Double): Color = when {
        value >= 67 -> bandHigh
        value >= 34 -> bandMid
        else -> bandLow
    }
    val background: Brush get() = Brush.verticalGradient(
        0f to bgTop, 0.5f to bgMid, 0.85f to bgBottom,
    )
}

object BroopMetrics {
    val page = 16.dp
    val gap = 10.dp
    val section = 32.dp
    val cardRadius = 16.dp
    val tileRadius = 14.dp
    val innerRadius = 12.dp
    val rowRadius = 10.dp
    val tabBarClearance = 110.dp
    val touch = 48.dp
    val icon = 22.dp
    val smallIcon = 16.dp
    val ring = 82.dp
    val ringStroke = 5.3.dp
    val compactGap = 6.dp
    val sectionGap = 24.dp
    val barHeight = 66.dp
    val badge = 32.dp
    val mark = 24.dp
}

/** Android uses the system sans family in place of Apple's bundled Avenir Next and DIN. */
object BroopType {
    private val base = TextStyle(fontFamily = FontFamily.SansSerif)
    val title = base.copy(fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
    val section = base.copy(fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
    val body = base.copy(fontSize = 15.sp, lineHeight = 22.sp)
    val demi = body.copy(fontWeight = FontWeight.SemiBold)
    val caption = base.copy(fontSize = 12.sp, lineHeight = 17.sp)
    val caps = base.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.1.sp)
    val number = base.copy(fontSize = 30.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")
    val largeNumber = number.copy(fontSize = 52.sp)
    val wordmark = base.copy(fontSize = 17.sp, letterSpacing = 4.sp)
    val tab = base.copy(fontSize = 11.sp, fontWeight = FontWeight.Medium)
}

object BroopPrefs {
    const val ENABLED_KEY = "broop.uiEnabled"
    var enabled by mutableStateOf(true)
        private set
    fun load(context: Context) {
        enabled = NoopPrefs.of(context).getBoolean(ENABLED_KEY, true)
    }
    fun setEnabled(context: Context, value: Boolean) {
        enabled = value
        NoopPrefs.of(context).edit().putBoolean(ENABLED_KEY, value).apply()
    }
}

/** The same tokens also colour existing editors, charts and system integration screens. */
val BroopTokens = DarkTokens.copy(
    surfaceBase = BroopPalette.bgBottom,
    surfaceRaised = BroopPalette.card,
    surfaceOverlay = BroopPalette.tile,
    surfaceInset = BroopPalette.track,
    hairline = BroopPalette.hairline,
    hairlineStrong = BroopPalette.row,
    textPrimary = BroopPalette.textPrimary,
    textSecondary = BroopPalette.textBody,
    textTertiary = BroopPalette.textSecondary,
    accent = BroopPalette.textPrimary,
    accentHover = BroopPalette.textBody,
    accentMuted = BroopPalette.pillOuter,
    focusRing = BroopPalette.teal,
    recovery000 = BroopPalette.bandLow,
    recovery030 = BroopPalette.bandLow,
    recovery055 = BroopPalette.bandMid,
    recovery078 = BroopPalette.bandHigh,
    recovery100 = BroopPalette.bandHigh,
    strain000 = BroopPalette.effort,
    strain033 = BroopPalette.effort,
    strain066 = BroopPalette.effort,
    strain100 = BroopPalette.effort,
    sleepAwake = BroopPalette.stageAwake,
    sleepLight = BroopPalette.stageLight,
    sleepDeep = BroopPalette.stageDeep,
    sleepREM = BroopPalette.stageREM,
    statusPositive = BroopPalette.teal,
    statusWarning = BroopPalette.warning,
    statusCritical = BroopPalette.bandLow,
    chargeColor = BroopPalette.bandHigh,
    chargeDeep = BroopPalette.bandHigh,
    chargeBright = BroopPalette.bandHigh,
    chargeGlow = BroopPalette.bandHigh,
    effortColor = BroopPalette.effort,
    effortDeep = BroopPalette.effort,
    effortBright = BroopPalette.effort,
    effortGlow = BroopPalette.effort,
    restColor = BroopPalette.rest,
    restDeep = BroopPalette.stageDeep,
    restBright = BroopPalette.stageREM,
    restGlow = BroopPalette.rest,
    scenicCenter = BroopPalette.bgTop,
    scenicEdge = BroopPalette.bgBottom,
    cardFillTop = BroopPalette.card,
    cardFillBottom = BroopPalette.card,
    heroFill = BroopPalette.card,
    heroBorder = BroopPalette.hairline,
)

@Composable
fun BroopPage(
    title: String,
    onBack: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(Modifier.fillMaxSize().background(BroopPalette.background)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = BroopMetrics.page)
                .padding(top = BroopMetrics.gap, bottom = BroopMetrics.tabBarClearance),
            verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
        ) {
            if (title.isNotEmpty()) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = BroopMetrics.touch),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (onBack != null) {
                        IconButton(onClick = onBack, modifier = Modifier.size(BroopMetrics.touch)) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.broop_back), tint = BroopPalette.textPrimary)
                        }
                    }
                    Text(title, style = BroopType.title, color = BroopPalette.textPrimary)
                }
            }
            content()
        }
    }
}

@Composable
fun BroopCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(BroopMetrics.cardRadius)
    Column(
        modifier.fillMaxWidth().clip(shape).background(BroopPalette.card)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(BroopMetrics.page),
        verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
        content = content,
    )
}

@Composable
fun BroopSection(title: String) {
    Text(
        title, style = BroopType.section, color = BroopPalette.textPrimary,
        modifier = Modifier.padding(top = BroopMetrics.sectionGap, bottom = BroopMetrics.compactGap),
    )
}

@Composable
fun BroopRow(title: String, subtitle: String? = null, icon: ImageVector? = null, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(BroopMetrics.tileRadius))
            .background(BroopPalette.tile).clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = BroopMetrics.touch)
            .padding(BroopMetrics.page),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
    ) {
        if (icon != null) Icon(icon, null, tint = BroopPalette.textBody, modifier = Modifier.size(BroopMetrics.icon))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(BroopMetrics.compactGap)) {
            Text(title, style = BroopType.demi, color = BroopPalette.textPrimary)
            if (subtitle != null) Text(subtitle, style = BroopType.caption, color = BroopPalette.textBody)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = BroopPalette.textBody, modifier = Modifier.size(BroopMetrics.smallIcon))
    }
}

@Composable
fun BroopEmpty(title: String, detail: String) {
    BroopCard {
        Text(title, style = BroopType.demi, color = BroopPalette.textPrimary)
        Text(detail, style = BroopType.body, color = BroopPalette.textBody)
    }
}

@Composable
fun BroopCaps(text: String, color: Color = BroopPalette.textPrimary) {
    Text(text.uppercase(Locale.getDefault()), style = BroopType.caps, color = color)
}

@Composable
fun BroopRing(
    value: Double?,
    max: Double = 100.0,
    color: Color,
    label: String,
    unit: String = "%",
    target: ClosedFloatingPointRange<Double>? = null,
    onClick: () -> Unit,
) {
    val reading = value?.takeIf { it.isFinite() && max.isFinite() && max > 0 }
    val formatted = reading?.let {
        if (unit.isEmpty()) String.format(Locale.getDefault(), "%.1f", it) else it.roundToInt().toString()
    } ?: "—"
    val description = stringResource(R.string.broop_ring_description, label, formatted, if (reading != null) unit else "")
    Column(
        Modifier.clip(RoundedCornerShape(BroopMetrics.innerRadius))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(BroopMetrics.compactGap),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap),
    ) {
        Box(Modifier.size(BroopMetrics.ring), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = BroopMetrics.ringStroke.toPx()
                val inset = stroke / 2
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(BroopPalette.track, -90f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(stroke))
                if (target != null && reading != null && target.start.isFinite() && target.endInclusive.isFinite()) {
                    val lo = (target.start / max).coerceIn(0.0, 1.0)
                    val hi = (target.endInclusive / max).coerceIn(lo, 1.0)
                    drawArc(color.copy(alpha = 0.28f), (lo * 360 - 90).toFloat(), ((hi - lo) * 360).toFloat(), false,
                        Offset(inset, inset), arcSize, style = Stroke(stroke * 1.7f))
                    val angle = ((lo + hi) / 2 * 360 - 90) * Math.PI / 180
                    val radius = (size.width - stroke) / 2
                    val centre = Offset(size.width / 2, size.height / 2)
                    drawLine(BroopPalette.textPrimary,
                        centre + Offset(cos(angle).toFloat(), sin(angle).toFloat()) * (radius - stroke),
                        centre + Offset(cos(angle).toFloat(), sin(angle).toFloat()) * (radius + stroke / 2), stroke / 3)
                }
                if (reading != null) drawArc(
                    color, -90f, (reading / max).coerceIn(0.0, 1.0).toFloat() * 360f, false,
                    Offset(inset, inset), arcSize, style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(formatted, style = BroopType.number, color = BroopPalette.textPrimary)
                if (reading != null && unit.isNotEmpty()) Text(unit, style = BroopType.caption, color = BroopPalette.textPrimary)
            }
        }
        BroopCaps(label)
    }
}

@Composable
fun BroopMark(modifier: Modifier = Modifier) {
    Canvas(modifier.size(BroopMetrics.mark)) {
        val shape = Path().apply {
            fillType = PathFillType.EvenOdd
            listOf(
                listOf(24 to 14, 62 to 14, 74 to 26, 74 to 40, 67 to 49, 78 to 60, 78 to 74, 66 to 86, 24 to 86),
                listOf(40 to 28, 56 to 28, 58 to 30, 58 to 38, 54 to 42, 40 to 42),
                listOf(40 to 56, 58 to 56, 62 to 60, 62 to 69, 59 to 72, 40 to 72),
            ).forEach { points ->
                points.forEachIndexed { index, (x, y) ->
                    val px = x * size.width / 100
                    val py = y * size.height / 100
                    if (index == 0) moveTo(px, py) else lineTo(px, py)
                }
                close()
            }
        }
        drawPath(shape, BroopPalette.textPrimary)
    }
}
