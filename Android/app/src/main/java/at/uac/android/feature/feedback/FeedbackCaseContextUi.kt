package at.uac.android.feature.feedback

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.WindowSecurity
import at.uac.android.feature.browse.tr

@Composable
internal fun ProtectFeedbackCaseWindow(enabled: Boolean) {
    val context = LocalContext.current
    DisposableEffect(context, enabled) {
        val lease =
            if (enabled) context.feedbackActivity()?.window?.let(WindowSecurity::acquire) else null
        onDispose { lease?.close() }
    }
}

private fun Context.feedbackActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.takeIf { it !== this }?.feedbackActivity()
        else -> null
    }

@Composable
fun FeedbackCaseContextCard(state: FeedbackState, language: String) {
    if (!state.canReadCaseContext()) return
    val context = state.conversation?.item?.caseContext
    Card(Modifier.fillMaxWidth().testTag("feedback-case-context")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                tr(language, "Angaben zur Meldung", "Відомості про скаргу"),
                style = MaterialTheme.typography.titleMedium,
            )
            if (context == null) {
                Text(
                    tr(
                        language,
                        "Die zusätzlichen Falldaten fehlen oder konnten nicht vollständig gelesen werden. Der Nachrichtenverlauf bleibt verfügbar.",
                        "Додаткові дані справи відсутні або їх не вдалося повністю прочитати. Історія повідомлень залишається доступною.",
                    ),
                    Modifier.testTag("feedback-case-invalid"),
                )
            } else {
                CaseField(
                    tr(language, "Genauer Fundort", "Точне розташування"),
                    context.exactLocation,
                    "location",
                )
                CaseField(
                    tr(language, "Begründung der Meldung", "Обґрунтування скарги"),
                    context.illegalExplanation,
                    "explanation",
                )
                context.legalBasis?.takeIf(String::isNotBlank)?.let {
                    CaseField(tr(language, "Rechtsgrundlage", "Правова підстава"), it, "basis")
                }
                context.evidence?.takeIf(String::isNotBlank)?.let {
                    CaseField(tr(language, "Nachweise", "Докази"), it, "evidence")
                }
                context.appeal?.let {
                    CaseField(
                        tr(
                            language,
                            "Begründung des Einspruchs / der Überprüfung",
                            "Обґрунтування оскарження / перегляду",
                        ),
                        it.reason,
                        "appeal",
                    )
                }
                Text(
                    if (context.goodFaithConfirmed)
                        tr(
                            language,
                            "Die meldende Person hat die Abgabe nach bestem Wissen und Gewissen bestätigt.",
                            "Заявник підтвердив добросовісність подання.",
                        )
                    else
                        tr(
                            language,
                            "Eine Bestätigung der Gutgläubigkeit liegt hier nicht vor.",
                            "Підтвердження добросовісності тут відсутнє.",
                        ),
                    Modifier.testTag("feedback-case-good-faith"),
                )
            }
        }
    }
}

@Composable
private fun CaseField(label: String, value: String, tag: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge)
        // Deliberately plain selectable text: no automatic links or external evidence fetches.
        SelectionContainer { Text(value, Modifier.testTag("feedback-case-$tag")) }
    }
}
