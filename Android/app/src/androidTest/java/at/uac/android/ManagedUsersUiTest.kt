package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic presentation tests: never evidence of a real Firebase TOTP authentication. */
@RunWith(AndroidJUnit4::class)
class ManagedUsersUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = ModerationSession("synthetic-ui-actor", 1, "admin", true)
    private val person =
        ManagedUsersContract.user(
            "synthetic-private-target",
            mapOf(
                "displayName" to "Synthetic Private Name",
                "fullName" to "Synthetic full name",
                "email" to "private@example.invalid",
                "globalRole" to "user",
                "accountStatus" to "active",
                "blockState" to "active",
                "selectedFederalState" to "wien",
                "city" to "Wien",
                "createdAt" to Instant.parse("2026-09-03T10:00:00Z"),
            ),
        )

    private fun initial() =
        ManagedUsersState(session = actor, visible = true, users = listOf(person), consumed = 1)

    private fun scroll(tag: String) {
        compose.onNodeWithTag("managed-users-list").performScrollToNode(hasTestTag(tag))
    }

    @Test
    fun deniedStateNeverRendersSuppliedPrivateRowsOrSearch() {
        compose.setContent {
            MaterialTheme {
                ManagedUsersContent(
                    initial().copy(session = actor.copy(role = "user")),
                    "de",
                    ManagedUsersActions(),
                )
            }
        }
        compose.onNodeWithTag("managed-users-access").assertIsDisplayed()
        compose.onNodeWithText("private@example.invalid").assertDoesNotExist()
        compose.onNodeWithTag("managed-users-search").assertDoesNotExist()
        compose.onNodeWithTag("managed-user-row-${person.id}").assertDoesNotExist()
    }

    @Test
    fun cappedWindowAndSearchTotalsAreExplicitAndDoNotClaimAllUsers() {
        compose.setContent {
            MaterialTheme {
                ManagedUsersContent(
                    initial().copy(capped = true, consumed = 200),
                    "uk",
                    ManagedUsersActions(),
                )
            }
        }
        scroll("managed-users-cap")
        compose
            .onNodeWithTag("managed-users-cap")
            .assertTextContains("це не повний список користувачів", substring = true)
        compose
            .onNodeWithTag("managed-users-count")
            .assertTextEquals("Профілів у завантаженій частині: 1")
        compose.onNodeWithTag("managed-users-more").assertDoesNotExist()
    }

    @Test
    fun searchEditsReachStateAndExplicitSearchAndRowTapEachRunOnce() {
        val edits = mutableListOf<String>()
        var refreshes = 0
        var opens = 0
        compose.setContent {
            var state by remember { mutableStateOf(initial()) }
            MaterialTheme {
                ManagedUsersContent(
                    state,
                    "de",
                    ManagedUsersActions(
                        search = {
                            edits += it
                            state = state.copy(query = it)
                        },
                        refresh = { refreshes++ },
                        open = {
                            check(it == person.id)
                            opens++
                        },
                    ),
                )
            }
        }
        scroll("managed-users-search")
        compose.onNodeWithTag("managed-users-search").performTextInput("Müller")
        compose.onNodeWithTag("managed-users-search").assertTextContains("Müller")
        compose.runOnIdle {
            // Text edits are a state-feedback contract, not an exactly-once IME protocol.
            assertEquals("Müller", edits.lastOrNull())
            assertEquals(0, refreshes)
            assertEquals(0, opens)
        }
        compose.onNodeWithTag("managed-users-search").performImeAction()
        compose.runOnIdle { assertEquals(1, refreshes) }
        scroll("managed-user-row-${person.id}")
        compose.onNodeWithTag("managed-user-row-${person.id}").performClick()
        compose.runOnIdle {
            assertEquals(1, opens)
            assertEquals(1, refreshes)
        }
    }

    @Test
    fun freshDetailUsesTranslatedRoleStatusRegionAndProviderLabels() {
        compose.setContent {
            MaterialTheme {
                ManagedUsersContent(
                    initial()
                        .copy(
                            selectedId = person.id,
                            detail = person,
                            security =
                                ManagedUserSecurity(
                                    person.id,
                                    true,
                                    false,
                                    null,
                                    null,
                                    listOf("password"),
                                ),
                        ),
                    "uk",
                    ManagedUsersActions(),
                )
            }
        }
        scroll("managed-user-detail")
        compose.onNodeWithText("Користувач").assertExists()
        compose.onNodeWithText("Wien · Відень").assertExists()
        compose.onNodeWithText("user").assertDoesNotExist()
        scroll("managed-user-security")
        compose.onNodeWithText("Email і пароль").assertExists()
        compose.onNodeWithText("password").assertDoesNotExist()
    }

    @Test
    fun missingAuthAccountIsNotShownAsUnverifiedOrMissingProfile() {
        compose.setContent {
            MaterialTheme {
                ManagedUsersContent(
                    initial()
                        .copy(
                            selectedId = person.id,
                            detail = person,
                            securityError = ManagedUsersFailure.MISSING,
                        ),
                    "de",
                    ManagedUsersActions(),
                )
            }
        }
        scroll("managed-user-detail")
        compose.onNodeWithText("Synthetic Private Name").assertExists()
        scroll("managed-user-security-error")
        compose
            .onNodeWithTag("managed-user-security-error")
            .assertTextContains("Auth-Konto wurde nicht gefunden", substring = true)
        compose.onNodeWithText("Nein").assertDoesNotExist()
    }

    @Test
    fun loadingOrRoleLossRemovesDetailAndMetadataImmediately() {
        var current by
            mutableStateOf(
                initial()
                    .copy(
                        selectedId = person.id,
                        detail = person,
                        security =
                            ManagedUserSecurity(
                                person.id,
                                true,
                                false,
                                null,
                                null,
                                listOf("password"),
                            ),
                    )
            )
        compose.setContent {
            MaterialTheme { ManagedUsersContent(current, "de", ManagedUsersActions()) }
        }
        scroll("managed-user-detail")
        compose.onNodeWithText("Synthetic Private Name").assertExists()
        compose.runOnIdle { current = current.copy(loading = true) }
        compose.onNodeWithTag("managed-user-detail").assertDoesNotExist()
        compose.onNodeWithTag("managed-user-security").assertDoesNotExist()
        compose.runOnIdle {
            current = current.copy(loading = false, session = actor.copy(ready = false))
        }
        compose.onNodeWithTag("managed-user-detail").assertDoesNotExist()
        scroll("managed-users-account")
        compose.onNodeWithTag("managed-users-account").assertIsEnabled()
    }

    @Test
    fun largeTextUkAndDeKeepReadActionAndLongRowsReachable() {
        var language by mutableStateOf("uk")
        var refresh = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    ManagedUsersContent(
                        initial()
                            .copy(
                                users =
                                    listOf(
                                        person.copy(
                                            displayName = "Synthetic " + "Довге ім’я ".repeat(10)
                                        )
                                    )
                            ),
                        language,
                        ManagedUsersActions(refresh = { refresh++ }),
                    )
                }
            }
        }
        for (selected in listOf("uk", "de")) {
            compose.runOnIdle { language = selected }
            scroll("managed-users-refresh")
            compose.onNodeWithTag("managed-users-refresh").assertIsDisplayed().performClick()
            val bounds = compose.onNodeWithTag("managed-users-refresh").getUnclippedBoundsInRoot()
            assertTrue((bounds.bottom - bounds.top).value >= 48f)
            scroll("managed-user-row-${person.id}")
            compose.onNodeWithTag("managed-user-row-${person.id}").assertIsDisplayed()
            val rowBounds =
                compose.onNodeWithTag("managed-user-row-${person.id}").getUnclippedBoundsInRoot()
            assertTrue((rowBounds.bottom - rowBounds.top).value >= 48f)
        }
        compose.runOnIdle { assertEquals(2, refresh) }
    }
}
