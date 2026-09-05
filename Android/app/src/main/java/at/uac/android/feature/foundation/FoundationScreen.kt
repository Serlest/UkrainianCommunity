package at.uac.android.feature.foundation

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun FoundationScreen(
    state: FoundationState,
    onLanguage: (String) -> Unit,
    onMode: (DataMode) -> Unit,
    onRetry: () -> Unit,
) {
    fun text(de: String, uk: String) = if (state.language == "uk") uk else de
    val colors =
        if (isSystemInDarkTheme())
            darkColorScheme(
                primary = Color(0xFFA7C8FF),
                secondary = Color(0xFFFFDF7C),
                secondaryContainer = Color(0xFF554200),
                onSecondaryContainer = Color(0xFFFFEDAA),
                surfaceContainerHighest = Color(0xFF253244),
            )
        else
            lightColorScheme(
                primary = Color(0xFF1756A2),
                secondary = Color(0xFF755B00),
                background = Color(0xFFF8F9FD),
                secondaryContainer = Color(0xFFFFEDAA),
                onSecondaryContainer = Color(0xFF302300),
                surfaceContainerHighest = Color(0xFFE9EFF9),
            )
    MaterialTheme(colorScheme = colors) {
        Scaffold { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
                Column(
                    Modifier.widthIn(max = 640.dp)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        "UAC",
                        style = MaterialTheme.typography.displaySmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text(
                            "Ukrainische Community in Österreich",
                            "Українська спільнота в Австрії",
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        FilterChip(
                            state.language == "de",
                            { onLanguage("de") },
                            label = { Text("Deutsch") },
                            modifier = Modifier.testTag("language-de"),
                        )
                        FilterChip(
                            state.language == "uk",
                            { onLanguage("uk") },
                            label = { Text("Українська") },
                            modifier = Modifier.testTag("language-uk"),
                        )
                    }
                    Card(
                        colors =
                            CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.secondaryContainer
                            )
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text("Lokale Testversion", "Локальна тестова версія"),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                text(
                                    "Nur erfundene Daten. Keine Verbindung zu echten Konten oder Inhalten.",
                                    "Лише вигадані дані. Без підключення до справжніх акаунтів або матеріалів.",
                                )
                            )
                        }
                    }
                    Text(
                        text("Datenquelle", "Джерело даних"),
                        modifier = Modifier.semantics { heading() },
                    )
                    Column {
                        FilterChip(
                            state.mode == DataMode.SYNTHETIC,
                            { onMode(DataMode.SYNTHETIC) },
                            label = { Text(text("Lokale Beispieldaten", "Локальні приклади")) },
                            modifier = Modifier.testTag("mode-synthetic"),
                        )
                        FilterChip(
                            state.mode == DataMode.EMULATOR,
                            { onMode(DataMode.EMULATOR) },
                            label = { Text("Firebase Emulator · demo-uac-android") },
                            modifier = Modifier.testTag("mode-emulator"),
                        )
                    }
                    when (val load = state.load) {
                        LoadState.Loading -> {
                            LinearProgressIndicator(Modifier.fillMaxWidth().testTag("loading"))
                            Text(text("Wird geladen…", "Завантаження…"))
                        }
                        is LoadState.Ready ->
                            Card(Modifier.fillMaxWidth().testTag("content")) {
                                Column(
                                    Modifier.padding(20.dp),
                                    verticalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Text(
                                        load.content.title.resolve(state.language),
                                        style = MaterialTheme.typography.headlineSmall,
                                        modifier = Modifier.semantics { heading() },
                                    )
                                    Text(load.content.body.resolve(state.language))
                                }
                            }
                        LoadState.Unavailable,
                        LoadState.InvalidData,
                        LoadState.AccessDenied -> {
                            Text(
                                if (load == LoadState.AccessDenied)
                                    text(
                                        "Die lokalen Regeln erlauben diesen Zugriff nicht.",
                                        "Локальні правила не дозволяють цей доступ.",
                                    )
                                else if (load == LoadState.InvalidData)
                                    text(
                                        "Testdaten fehlen oder sind ungültig.",
                                        "Тестові дані відсутні або некоректні.",
                                    )
                                else
                                    text(
                                        "Der lokale Emulator ist nicht erreichbar. Beispieldaten funktionieren auch offline.",
                                        "Локальний емулятор недоступний. Локальні приклади працюють і без мережі.",
                                    ),
                                modifier = Modifier.testTag("error"),
                            )
                            Button(onRetry, modifier = Modifier.testTag("retry")) {
                                Text(text("Erneut versuchen", "Спробувати ще раз"))
                            }
                        }
                    }
                    Text(
                        text(
                            "Paket 1: technische Grundlage. Nachrichten, Konto und Verwaltung folgen in getrennten Paketen.",
                            "Пакет 1: технічна основа. Новини, акаунт і керування з’являться в окремих пакетах.",
                        ),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}
