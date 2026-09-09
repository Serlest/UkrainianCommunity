package at.uac.android.feature.translation

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.backend.AppBackend
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

data class TranslationField(
    val key: String,
    val label: String,
    val source: String,
    val target: String,
    val maximumLength: Int,
)

interface ContentTranslationSource {
    suspend fun translate(kind: String, texts: List<String>, sourceLanguage: String = "uk"): List<String>
}

private class FirebaseContentTranslationSource(context: Context) : ContentTranslationSource {
    private val calls = AppBackend.callables(context.applicationContext)

    override suspend fun translate(kind: String, texts: List<String>, sourceLanguage: String): List<String> {
        require(kind in setOf("news", "event", "organization", "banner", "announcement"))
        require(sourceLanguage == "uk" || kind == "announcement" && sourceLanguage == "de")
        require(texts.isNotEmpty() && texts.size <= 12 && texts.all { it.isNotBlank() })
        val raw =
            calls.getHttpsCallable("translateContent")
                .withTimeout(20, TimeUnit.SECONDS)
                .call(mapOf("kind" to kind, "texts" to texts, "source" to sourceLanguage))
                .await()
                .data as? Map<*, *> ?: error("INVALID_TRANSLATION_RESPONSE")
        val translated = raw["texts"] as? List<*> ?: error("INVALID_TRANSLATION_RESPONSE")
        if (translated.size != texts.size) error("INVALID_TRANSLATION_RESPONSE")
        return translated.map { (it as? String)?.takeIf(String::isNotBlank) ?: error("INVALID_TRANSLATION_RESPONSE") }
    }
}

private data class TranslationReview(
    val input: List<TranslationField>,
    val translated: Map<String, String>,
)

@Composable
fun ContentTranslationButton(
    kind: String,
    language: String,
    fields: List<TranslationField>,
    enabled: Boolean,
    sourceLanguage: String = "uk",
    translationSource: ContentTranslationSource? = null,
    onApply: (Map<String, String>) -> Unit,
) {
    val source = rememberTranslationSource(translationSource)
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var review by remember { mutableStateOf<TranslationReview?>(null) }
    val eligible = fields.filter { it.source.isNotBlank() }
    OutlinedButton(
        onClick = {
            val captured = fields
            loading = true
            failed = false
            scope.launch {
                try {
                    val values = captured.filter { it.source.isNotBlank() }
                    val translated = source.translate(kind, values.map { it.source }, sourceLanguage)
                    if (translated.zip(values).any { (text, field) -> text.length > field.maximumLength }) {
                        failed = true
                    } else {
                        review = TranslationReview(captured, values.mapIndexed { index, field -> field.key to translated[index] }.toMap())
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    failed = true
                } finally {
                    loading = false
                }
            }
        },
        enabled = enabled && eligible.isNotEmpty() && !loading,
        modifier = Modifier.fillMaxWidth().testTag("translate-$kind"),
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.width(18.dp).height(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(
            if (sourceLanguage == "de")
                if (language == "uk") "Перекласти німецьку українською" else "Deutsch ins Ukrainische übersetzen"
            else if (language == "uk") "Перекласти українську німецькою"
            else "Ukrainisch ins Deutsche übersetzen"
        )
    }
    if (failed) {
        Text(
            if (language == "uk") "Переклад недоступний або перевищує ліміт поля. Текст можна ввести вручну."
            else "Übersetzung nicht verfügbar oder Feldlimit überschritten. Der Text kann manuell eingegeben werden.",
            Modifier.testTag("translation-error"),
        )
    }
    review?.let { proposal ->
        val stale = fields != proposal.input
        val overwrites = proposal.input.any { field ->
            field.target.isNotBlank() && proposal.translated[field.key]?.let { it != field.target } == true
        }
        var confirmed by remember(proposal) { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { review = null },
            title = { Text(if (language == "uk") "Перевірка перекладу" else "Übersetzung prüfen") },
            text = {
                Column {
                    proposal.input.filter { it.key in proposal.translated }.forEach { field ->
                        Text(field.label)
                        Text(proposal.translated.getValue(field.key), Modifier.padding(bottom = 10.dp))
                    }
                    if (overwrites) {
                        Row {
                            Checkbox(confirmed, { confirmed = it }, modifier = Modifier.testTag("translation-overwrite"))
                            Text(if (language == "uk") "Замінити заповнений німецький текст" else "Vorhandenen deutschen Text ersetzen")
                        }
                    }
                    if (stale) Text(if (language == "uk") "Чернетка змінилася. Запустіть переклад ще раз." else "Der Entwurf wurde geändert. Übersetzung erneut starten.")
                }
            },
            confirmButton = {
                Button(
                    onClick = { onApply(proposal.translated); review = null; failed = false },
                    enabled = !stale && (!overwrites || confirmed),
                    modifier = Modifier.testTag("translation-apply"),
                ) { Text(if (language == "uk") "Застосувати" else "Übernehmen") }
            },
            dismissButton = {
                OutlinedButton({ review = null }) { Text(if (language == "uk") "Скасувати" else "Abbrechen") }
            },
        )
    }
}

@Composable
private fun rememberTranslationSource(provided: ContentTranslationSource?): ContentTranslationSource {
    val context = LocalContext.current.applicationContext
    return remember(context, provided) { provided ?: FirebaseContentTranslationSource(context) }
}
