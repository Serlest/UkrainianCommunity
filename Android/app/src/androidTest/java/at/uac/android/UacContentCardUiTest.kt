package at.uac.android

import android.graphics.Bitmap
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.*
import java.io.File
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class UacContentCardUiTest {
    @get:Rule val compose = createComposeRule()

    private fun runMatrix(language: String, theme: String, scale: Float) {
        val title =
            tr(
                language,
                "Gemeinschaftszentrum startet wöchentliche Rechtsberatung für neue Nachbarn",
                "Громадський центр запрошує на щотижневу консультацію для нових сусідів",
            )
        val rows =
            ContentKind.entries.map { kind ->
                Content(
                    kind,
                    "card-${kind.collection}",
                    mapOf(
                        "title" to title,
                        "name" to title,
                        "summary" to "Synthetische Vorschau · Лише тестовий приклад",
                        "shortDescription" to "Synthetischer Verein",
                        "city" to "Wien",
                        "organizationName" to "Synthetic Community",
                        "createdAt" to Instant.parse("2026-09-03T09:00:00Z"),
                        "startDate" to Instant.parse("2026-09-07T15:00:00Z"),
                        "cancellationState" to
                            if (kind == ContentKind.EVENTS) "cancelled" else "active",
                    ),
                )
            }
        var opened: String? = null
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, scale)) {
                UacTheme(theme) {
                    val window = LocalActivity.current?.window
                    SideEffect {
                        window?.let {
                            WindowCompat.getInsetsController(it, it.decorView)
                                .isAppearanceLightStatusBars = theme == "light"
                        }
                    }
                    UacPageBackground(Modifier.fillMaxSize()) {
                        LazyColumn(
                            Modifier.fillMaxSize().safeDrawingPadding().testTag("card-matrix"),
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            items(rows, key = { it.id }) { row ->
                                ContentCard(row, language) { opened = row.id }
                            }
                        }
                    }
                }
            }
        }
        rows.forEach { row ->
            compose.onNodeWithTag("card-matrix").performScrollToNode(hasTestTag("card-${row.id}"))
            compose
                .onNodeWithTag("card-${row.id}")
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
                .performClick()
            assertEquals(row.id, opened)
            if (scale > 1.3f) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose
                    .onNodeWithTag("card-title-${row.id}", useUnmergedTree = true)
                    .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertEquals(1, layouts.size)
                assertFalse(
                    "Large title width must remain readable",
                    layouts.single().didOverflowWidth,
                )
                assertFalse(
                    "Large title height must remain readable",
                    layouts.single().didOverflowHeight,
                )
                assertEquals(title, layouts.single().layoutInput.text.text)
            }
            if (row.kind == ContentKind.EVENTS)
                compose
                    .onNodeWithTag("card-cancelled-${row.id}", useUnmergedTree = true)
                    .assertExists()
        }
        compose.onNodeWithTag("card-matrix").performScrollToIndex(0)
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        File(instrumentation.targetContext.cacheDir, "cards-$language-$theme-$scale.png")
            .outputStream()
            .use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        bitmap.recycle()
    }

    @Test
    fun germanLightCompactCardsPreserveNavigationAndCancelledState() = runMatrix("de", "light", 1f)

    @Test fun germanDarkLargeTextIsCompleteAndClickable() = runMatrix("de", "dark", 2f)

    @Test fun ukrainianLightLargeTextIsCompleteAndClickable() = runMatrix("uk", "light", 2f)

    @Test
    fun ukrainianDarkCompactCardsPreserveNavigationAndCancelledState() = runMatrix("uk", "dark", 1f)
}
