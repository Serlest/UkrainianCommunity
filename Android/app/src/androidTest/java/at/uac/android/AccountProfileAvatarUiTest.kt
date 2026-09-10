package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.auth.AccountProfileAvatar
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountProfileAvatarUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun validAvatarUrlFetchesAndDecodesRealImage() = withLocalImageFixture { url ->
        compose.setContent { MaterialTheme { AccountProfileAvatar(url, "de") } }
        compose.waitUntil(10_000) {
            compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("loaded-media").assertIsDisplayed()
        compose
            .onNodeWithTag("auth-profile-avatar")
            .assertIsDisplayed()
            .assertWidthIsEqualTo(80.dp)
            .assertHeightIsEqualTo(80.dp)
    }

    @Test
    fun missingAvatarKeepsAccessiblePortraitSlotAcrossLanguageChange() {
        val language = mutableStateOf("de")
        compose.setContent { MaterialTheme { AccountProfileAvatar("", language.value) } }
        compose
            .onNodeWithTag("auth-profile-avatar")
            .assertIsDisplayed()
            .assertWidthIsEqualTo(80.dp)
            .assertHeightIsEqualTo(80.dp)
            .assertContentDescriptionEquals("Profilfoto")
        compose.runOnIdle { language.value = "uk" }
        compose
            .onNodeWithTag("auth-profile-avatar")
            .assertIsDisplayed()
            .assertContentDescriptionEquals("Фото профілю")
    }
}
