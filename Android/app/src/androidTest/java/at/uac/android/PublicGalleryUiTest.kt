package at.uac.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.WindowPrivacy
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.ReadFailure
import at.uac.android.feature.publicgallery.PublicOrganizationGallery
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PublicGalleryUiTest {
    @get:Rule val compose = createComposeRule()
    private val at = Instant.parse("2026-09-03T05:00:00Z")

    private fun row(
        id: String,
        caption: String = "Caption $id",
        url: String = "https://example.invalid/media/community.png",
    ) =
        RawDocument(
            id,
            mapOf(
                "caption" to caption,
                "imageURL" to url,
                "uploadedBy" to "not-displayed-user",
                "createdAt" to at,
            ),
        )

    private fun open(id: String) = compose.onNodeWithTag("public-gallery-photo-$id").performClick()

    @Test
    fun guestOpensSelectedPhotoPagesBothDirectionsAndClosesWithoutManagement() {
        compose.setContent {
            MaterialTheme {
                PublicOrganizationGallery(
                    "org",
                    listOf(row("one"), row("two")),
                    "de",
                    null,
                    null,
                    {},
                    { true },
                    "guest",
                )
            }
        }
        compose.onNodeWithTag("public-gallery-count").assertTextEquals("2 / 30")
        open("two")
        compose.onNodeWithTag("public-gallery-page").assertTextEquals("2 / 2")
        compose.onNodeWithTag("public-gallery-caption-two").assertTextEquals("Caption two")
        compose.onNodeWithTag("public-gallery-next").assertIsNotEnabled()
        compose.onNodeWithTag("public-gallery-previous").performClick()
        compose.waitUntil { compose.onAllNodesWithText("1 / 2").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("public-gallery-previous").assertIsNotEnabled()
        compose.onNodeWithTag("public-gallery-next").performClick()
        compose.waitUntil { compose.onAllNodesWithText("2 / 2").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("gallery-choose").assertDoesNotExist()
        compose.onNodeWithTag("gallery-remove-two").assertDoesNotExist()
        compose.onNodeWithText("not-displayed-user").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-done").assertIsDisplayed().performClick()
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
    }

    @Test
    fun safetyAndInteractionDenialCloseBeforeReturnAndNeverReopenStaleSelection() {
        val visible = mutableStateOf(true)
        compose.setContent {
            MaterialTheme {
                PublicOrganizationGallery(
                    "org",
                    listOf(row("one")),
                    "uk",
                    null,
                    null,
                    {},
                    { visible.value },
                    "current",
                )
            }
        }
        open("one")
        compose.onNodeWithTag("public-gallery-viewer").assertIsDisplayed()
        compose.runOnIdle { visible.value = false }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery").assertDoesNotExist()
        compose.runOnIdle { visible.value = true }
        compose.onNodeWithTag("public-gallery-photo-one").assertIsDisplayed()
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
    }

    @Test
    fun accountRevisionAndOrganizationScopeChangesDiscardSelection() {
        val scope = mutableStateOf("account-revision-1")
        val org = mutableStateOf("first")
        compose.setContent {
            MaterialTheme {
                PublicOrganizationGallery(
                    org.value,
                    listOf(row("one")),
                    "de",
                    null,
                    null,
                    {},
                    { true },
                    scope.value,
                )
            }
        }
        open("one")
        compose.runOnIdle { scope.value = "account-revision-2" }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        open("one")
        compose.runOnIdle { org.value = "second" }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
    }

    @Test
    fun selectedRemovalAndDeniedFreshReadCannotKeepOldCaptionOrUrl() {
        val photos = mutableStateOf(listOf(row("one"), row("two")))
        val error = mutableStateOf<ReadFailure?>(null)
        compose.setContent {
            MaterialTheme {
                PublicOrganizationGallery(
                    "org",
                    photos.value,
                    "de",
                    null,
                    error.value,
                    {},
                    { true },
                    "scope",
                )
            }
        }
        open("one")
        compose.runOnIdle { photos.value = listOf(row("two")) }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-photo-one").assertDoesNotExist()
        open("two")
        compose.runOnIdle { error.value = ReadFailure.DENIED }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-photo-two").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-error").assertIsDisplayed()
    }

    @Test
    fun cachedCopyIsLabelledInGridAndViewerAndExplicitRefreshIsGuarded() {
        var refreshes = 0
        compose.setContent {
            MaterialTheme {
                PublicOrganizationGallery(
                    "org",
                    listOf(row("one")),
                    "uk",
                    at,
                    null,
                    { refreshes++ },
                    { true },
                    "guest",
                )
            }
        }
        compose.onNodeWithTag("public-gallery-cached").assertIsDisplayed()
        open("one")
        compose
            .onNode(
                hasTestTag("public-gallery-cached") and
                    hasAnyAncestor(hasTestTag("public-gallery-viewer"))
            )
            .assertIsDisplayed()
        compose.onNodeWithTag("public-gallery-done").performClick()
        compose.onNodeWithTag("public-gallery-refresh").performClick()
        compose.runOnIdle { assertEquals(1, refreshes) }
    }

    @Test
    fun boundedGridHasTwoOrThreeColumnsInsideExistingLazyColumnAndNoDuplicateKeys() {
        val width = mutableStateOf(300.dp)
        compose.setContent {
            MaterialTheme {
                LazyColumn(Modifier.fillMaxSize().testTag("test-gallery-host")) {
                    item {
                        Box(Modifier.width(width.value)) {
                            PublicOrganizationGallery(
                                "org",
                                (1..31).map { row("photo-$it") },
                                "de",
                                null,
                                null,
                                {},
                                { true },
                                "guest",
                            )
                        }
                    }
                }
            }
        }
        fun y(id: Int) =
            compose
                .onNodeWithTag("public-gallery-photo-photo-$id")
                .getUnclippedBoundsInRoot()
                .top
                .value
        assertEquals(y(1), y(2), 1f)
        assertTrue(y(3) > y(1))
        compose.runOnIdle { width.value = 360.dp }
        assertEquals(y(1), y(3), 1f)
        assertTrue(y(4) > y(1))
        compose.onNodeWithTag("public-gallery-photo-photo-31").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-count").assertTextEquals("30 / 30")
    }

    @Test
    fun largeTextLongCaptionFallbackAndBackKeepFullscreenControlsReachable() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    PublicOrganizationGallery(
                        "org",
                        listOf(row("one", "Довгий підпис ".repeat(35), "file:///must-never-load")),
                        "uk",
                        null,
                        null,
                        {},
                        { true },
                        "guest",
                    )
                }
            }
        }
        open("one")
        compose.onNodeWithTag("public-gallery-done").assertIsDisplayed()
        compose.onNodeWithTag("public-gallery-previous").assertIsDisplayed()
        compose.onNodeWithTag("public-gallery-next").assertIsDisplayed()
        val done = compose.onNodeWithTag("public-gallery-done").getUnclippedBoundsInRoot()
        val image = compose.onNodeWithTag("public-gallery-image-one").getUnclippedBoundsInRoot()
        assertTrue(done.bottom.value - done.top.value >= 48f)
        assertTrue(image.bottom.value - image.top.value > 0f)
        compose
            .onNode(
                hasTestTag("public-media-unavailable") and
                    hasAnyAncestor(hasTestTag("public-gallery-viewer"))
            )
            .assertIsDisplayed()
        // Ordinary dialog Back dispatch, without any system-setting change.
        androidx.test.espresso.Espresso.pressBack()
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
    }

    @Test
    fun existingPrivacyRegistryClosesPublicDialogOnLocalLockWithoutReopening() {
        val privacy = WindowPrivacy()
        compose.setContent {
            DisposableEffect(privacy) { onDispose { privacy.close() } }
            CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                MaterialTheme {
                    PublicOrganizationGallery(
                        "org",
                        listOf(row("one")),
                        "de",
                        null,
                        null,
                        {},
                        { true },
                        "authenticated",
                    )
                }
            }
        }
        open("one")
        compose.onNodeWithTag("public-gallery-viewer").assertIsDisplayed()
        compose.runOnIdle { privacy.update(secure = true, blocked = true) }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.runOnIdle { privacy.update(secure = true, blocked = false) }
        compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
        compose.onNodeWithTag("public-gallery-photo-one").assertIsDisplayed()
    }
}
