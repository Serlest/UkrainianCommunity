package at.uac.android.feature.auth

import android.content.Context
import android.view.Window
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import at.uac.android.core.ProtectedDialog
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import org.json.JSONObject

/** Unchanged iOS build 65 reference, not newly published Android legal terms. */
fun bundledReferenceLegal(context: Context): List<AuthLegalDocument> {
    val json =
        context.assets.open("ios65-reference-legal-documents.json").bufferedReader().use {
            JSONObject(it.readText())
        }
    return listOf("terms", "privacy", "organizationRules").map { type ->
        val entry = json.getJSONObject(type)
        val locales = entry.getJSONObject("locales")
        val titles = mutableMapOf<String, String>()
        val texts = mutableMapOf<String, String>()
        for (locale in listOf("de", "uk")) {
            val content = locales.getJSONObject(locale)
            titles[locale] = content.getString("title")
            texts[locale] =
                content.optString("contentText").takeIf { it.isNotBlank() && it != "null" }
                    ?: content.getString("contentMarkdown")
        }
        AuthLegalDocument(
            type,
            entry.getString("version"),
            entry.getBoolean("requiresAcceptance"),
            titles,
            texts,
        )
    }
}

@Composable
fun AuthLegalReader(
    document: AuthLegalDocument,
    language: String,
    reference: Boolean,
    dismiss: () -> Unit,
) {
    at.uac.android.core.PreserveAuthRemediationSurface()
    val body = document.text(language)
    val blocks = remember(body) { formatLegalText(body) }
    val title = document.title(language)
    val locale = remember(language) { LocaleList(if (language == "uk") "uk" else "de") }
    ProtectedDialog(
        onDismissRequest = dismiss,
        properties =
            DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
                windowTitle = title,
            ),
    ) {
        ReaderSystemBarAppearance()
        Surface(
            Modifier.fillMaxSize().testTag("legal-reader"),
            color = MaterialTheme.colorScheme.background,
        ) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(dismiss, Modifier.size(48.dp).testTag("legal-close")) {
                        UacSymbol(UacIcon.BACK, authText(language, "Schließen", "Закрити"))
                    }
                    Text(
                        authText(language, "Rechtliches", "Правові документи"),
                        Modifier.weight(1f).padding(horizontal = 8.dp),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                // Match the separate document screen on iPhone; reading space scales with the
                // window.
                // The full title belongs to the scroll content, never a fixed large-text header.
                Column(
                    Modifier.weight(1f)
                        .align(Alignment.CenterHorizontally)
                        .widthIn(max = 720.dp)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 20.dp, vertical = 20.dp)
                        .testTag("legal-content")
                        .semantics { paneTitle = title },
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    if (blocks.firstOrNull()?.text?.trim() != title.trim()) {
                        Text(
                            title,
                            Modifier.testTag("legal-document-title").semantics { heading() },
                            style =
                                MaterialTheme.typography.titleLarge.copy(
                                    localeList = locale,
                                    hyphens = Hyphens.Auto,
                                    lineBreak = LineBreak.Heading,
                                ),
                        )
                    }
                    Text(
                        authText(language, "Version ", "Версія ") + document.version,
                        style = MaterialTheme.typography.labelLarge,
                    )
                    if (reference)
                        Text(
                            authText(
                                language,
                                "Unveränderte iOS-Referenz für lokale Tests. Die Freigabe für Android steht noch aus.",
                                "Незмінений текст iOS для локальних тестів. Юридичне погодження Android ще не завершено.",
                            ),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    SelectionContainer {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            blocks.forEachIndexed { index, block ->
                                val text =
                                    remember(block) {
                                        buildAnnotatedString {
                                            block.runs.forEach { run ->
                                                if (run.strong)
                                                    withStyle(
                                                        SpanStyle(fontWeight = FontWeight.SemiBold)
                                                    ) {
                                                        append(run.text)
                                                    }
                                                else append(run.text)
                                            }
                                        }
                                    }
                                val style =
                                    when (block.headingLevel) {
                                        1 -> MaterialTheme.typography.titleLarge
                                        2 -> MaterialTheme.typography.titleMedium
                                        in 3..6 -> MaterialTheme.typography.titleSmall
                                        else -> MaterialTheme.typography.bodyMedium
                                    }
                                Text(
                                    text,
                                    Modifier.testTag("legal-block-$index")
                                        .then(
                                            if (block.headingLevel > 0)
                                                Modifier.semantics { heading() }
                                            else Modifier
                                        ),
                                    style =
                                        style.copy(
                                            localeList = locale,
                                            hyphens = Hyphens.Auto,
                                            lineBreak =
                                                if (block.headingLevel > 0) LineBreak.Heading
                                                else LineBreak.Paragraph,
                                        ),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * This full-screen document has its own background; it must not inherit the photo header's icons.
 */
@Composable
private fun ReaderSystemBarAppearance() {
    val view = LocalView.current
    val darkIcons = MaterialTheme.colorScheme.background.luminance() > 0.5f
    DisposableEffect(view, darkIcons) {
        var ancestor = view.parent
        var window: Window? = null
        while (ancestor != null && window == null) {
            window = (ancestor as? DialogWindowProvider)?.window
            ancestor = ancestor.parent
        }
        val controller = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        val previousStatus = controller?.isAppearanceLightStatusBars
        val previousNavigation = controller?.isAppearanceLightNavigationBars
        controller?.isAppearanceLightStatusBars = darkIcons
        controller?.isAppearanceLightNavigationBars = darkIcons
        onDispose {
            controller?.let { target ->
                previousStatus?.let { target.isAppearanceLightStatusBars = it }
                previousNavigation?.let { target.isAppearanceLightNavigationBars = it }
            }
        }
    }
}
