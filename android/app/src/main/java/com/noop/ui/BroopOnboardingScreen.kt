package com.noop.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.noop.R

internal val LocalBroopOnboarding = staticCompositionLocalOf { false }

/** The twelve existing steps retain the same scanning, profile, import and permission actions. */
@Composable
fun BroopOnboardingScreen(vm: AppViewModel, onFinished: () -> Unit) {
    OnboardingScreen(viewModel = vm, onFinished = onFinished, broop = true)
}

@Composable
internal fun BroopOnboardingTopBar(page: Int, total: Int, onBack: (() -> Unit)?) {
    Column(verticalArrangement = Arrangement.spacedBy(BroopMetrics.gap)) {
        Row(Modifier.fillMaxWidth().heightIn(min = BroopMetrics.touch), verticalAlignment = Alignment.CenterVertically) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.size(BroopMetrics.touch)) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = stringResource(R.string.l10n_onboarding_screen_back_b52b36b7),
                        tint = BroopPalette.textPrimary)
                }
            } else Spacer(Modifier.size(BroopMetrics.touch))
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.l10n_onboarding_screen_page_total_50b38f9a, page, total),
                style = BroopType.caps, color = BroopPalette.textBody)
        }
        Box(Modifier.fillMaxWidth().height(BroopMetrics.compactGap).clip(RoundedCornerShape(50)).background(BroopPalette.track)) {
            val progress = ((page - 1).toFloat() / (total - 1).coerceAtLeast(1)).coerceIn(0f, 1f)
            Box(Modifier.fillMaxWidth(progress).height(BroopMetrics.compactGap).background(BroopPalette.textPrimary))
        }
    }
}

@Composable
internal fun BroopOnboardingFooter(cta: String, onNext: () -> Unit) {
    Button(onClick = onNext, shape = RoundedCornerShape(50),
        modifier = Modifier.fillMaxWidth().padding(top = BroopMetrics.page).heightIn(min = BroopMetrics.touch),
        colors = ButtonDefaults.buttonColors(containerColor = BroopPalette.textPrimary, contentColor = BroopPalette.bgBottom)) {
        Text(cta, style = BroopType.demi)
    }
}

@Composable
internal fun BroopOnboardingWelcome() {
    Column(Modifier.fillMaxWidth().padding(vertical = BroopMetrics.section),
        verticalArrangement = Arrangement.spacedBy(BroopMetrics.section)) {
        Spacer(Modifier.height(BroopMetrics.section))
        BroopMark(Modifier.size(BroopMetrics.ring))
        Text(stringResource(R.string.broop_onboarding_brand), style = BroopType.wordmark, color = BroopPalette.textPrimary)
        Text(stringResource(R.string.l10n_onboarding_screen_all_your_data_none_of_the_6fc6f26d),
            style = BroopType.title, color = BroopPalette.textPrimary)
        Text(stringResource(R.string.l10n_onboarding_screen_a_private_window_into_your_recovery_b8dd2ff2),
            style = BroopType.body, color = BroopPalette.textBody)
    }
}
