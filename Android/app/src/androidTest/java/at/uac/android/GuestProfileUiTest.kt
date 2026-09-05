package at.uac.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacTheme
import at.uac.android.feature.personal.GuestProfileContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class GuestProfileUiTest {
    @get:Rule val compose = createComposeRule()

    private fun show(language: String, theme: String, scale: Float) {
        val actions = mutableListOf<String>()
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, scale)
            ) {
                UacTheme(theme) {
                    UacPageBackground(Modifier.fillMaxSize()) {
                        Column(
                            Modifier.fillMaxSize()
                                .safeDrawingPadding()
                                .verticalScroll(rememberScrollState())
                                .padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            GuestProfileContent(
                                language,
                                { actions += "login" },
                                { actions += "register" },
                                actions::add,
                            )
                        }
                    }
                }
            }
        }
        for (tag in
            listOf(
                "guest-sign-in",
                "guest-create-account",
                "guest-browse-news",
                "guest-browse-events",
                "guest-browse-organizations",
                "guest-settings",
            )) {
            compose
                .onNodeWithTag(tag)
                .performScrollTo()
                .assertIsDisplayed()
                .assertIsEnabled()
                .assertHeightIsAtLeast(48.dp)
                .performClick()
        }
        assertEquals(
            listOf("login", "register", "home", "events", "organizations", "settings"),
            actions,
        )
        compose.onNodeWithTag("auth-email").assertDoesNotExist()
        compose.onNodeWithTag("auth-password").assertDoesNotExist()
    }

    @Test fun germanLightWelcomeKeepsAllActionsAccessible() = show("de", "light", 1f)

    @Test
    fun ukrainianDarkTwoHundredPercentWelcomeKeepsAllActionsAccessible() = show("uk", "dark", 2f)
}
