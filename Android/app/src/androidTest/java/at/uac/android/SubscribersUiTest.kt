package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.subscribers.*
import java.time.Instant
import kotlinx.coroutines.flow.emptyFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubscribersUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = SubscriberSession("private-reader", 1, true)
    private val id = "synthetic-community"
    private val org =
        SubscribersContract.organization(
            RawDocument(
                id,
                mapOf(
                    "id" to id,
                    "name" to "Public community",
                    "moderationStatus" to "approved",
                    "ownerId" to "official-owner",
                ),
            ),
            session,
        )
    private val member =
        SubscriberMember(
            "private-person",
            SubscriberRole.SUBSCRIBER,
            SubscriberProfile(
                "private-person",
                "Public Name / Публічне ім’я",
                null,
                "Wien",
                "wien",
            ),
            Instant.EPOCH,
        )
    private val owner = SubscriberMember("official-owner", SubscriberRole.OWNER, null, null)
    private val cursor =
        SubscriberCursor(id, Instant.EPOCH, "organization_follow_${id}_private-person", 50)
    private val page =
        SubscribersSnapshot(
            session,
            org,
            listOf(SubscriberReference(member.userId, Instant.EPOCH, cursor.documentId)),
            listOf(owner, member),
            cursor,
            false,
            1,
        )

    private fun state() = SubscribersState(session, id, true, page = page)

    private fun scroll(tag: String) =
        compose.onNodeWithTag("subscribers-list").performScrollToNode(hasTestTag(tag))

    @Test
    fun capMissingOfficialProfileAndPublicFieldsAreReachableAtLargeText() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    SubscribersContent(
                        state().copy(page = page.copy(next = null, capped = true)),
                        "uk",
                        SubscribersActions(),
                        { true },
                        { true },
                    )
                }
            }
        }
        scroll("subscribers-cap")
        compose.onNodeWithTag("subscribers-cap").assertIsDisplayed()
        scroll("subscriber-${owner.userId}")
        compose.onNodeWithText("Профіль недоступний").assertIsDisplayed()
        scroll("subscriber-${member.userId}")
        compose.onNodeWithText(member.profile!!.displayName).assertIsDisplayed()
        compose.onNodeWithText(member.userId).assertDoesNotExist()
        compose.onNodeWithText(session.uid).assertDoesNotExist()
        compose.onNodeWithTag("subscribers-more").assertDoesNotExist()
    }

    @Test
    fun searchUsesLoadedPublicNamesAndMoreIsExplicit() {
        val state = mutableStateOf(state())
        var more = 0
        compose.setContent {
            MaterialTheme {
                SubscribersContent(
                    state.value,
                    "de",
                    SubscribersActions(
                        more = { more++ },
                        search = { state.value = state.value.copy(search = it) },
                    ),
                    { true },
                    { true },
                )
            }
        }
        scroll("subscribers-search")
        compose.onNodeWithTag("subscribers-search").performTextReplacement(member.userId)
        scroll("subscribers-empty")
        compose.onNodeWithTag("subscribers-empty").assertIsDisplayed()
        scroll("subscribers-more")
        compose.onNodeWithTag("subscribers-more").performClick()
        compose.runOnIdle { assertEquals(1, more) }
        scroll("subscribers-search")
        compose.onNodeWithTag("subscribers-search").performTextReplacement("Public Name")
        scroll("subscriber-${member.userId}")
        compose.onNodeWithTag("subscriber-${member.userId}").assertIsDisplayed()
        compose.onNodeWithTag("subscriber-${owner.userId}").assertDoesNotExist()
    }

    @Test
    fun sessionAndPolicyMaskBeforeReloadEffectAndOfflineOffersRetry() {
        val state = mutableStateOf(state())
        val visible = mutableStateOf(true)
        var retry = false
        compose.setContent {
            MaterialTheme {
                SubscribersContent(
                    state.value,
                    "de",
                    SubscribersActions(refresh = { retry = true }),
                    { visible.value },
                    { true },
                )
            }
        }
        scroll("subscriber-${member.userId}")
        compose.onNodeWithTag("subscriber-${member.userId}").assertExists()
        compose.runOnIdle { visible.value = false }
        compose.onNodeWithTag("subscriber-${member.userId}").assertDoesNotExist()
        scroll("subscribers-policy")
        compose.runOnIdle {
            visible.value = true
            state.value = state().copy(error = SubscribersFailure.OFFLINE)
        }
        scroll("subscribers-retry")
        compose.onNodeWithTag("subscribers-retry").performClick()
        compose.runOnIdle {
            assertTrue(retry)
            state.value = state().forSession(null, id)
        }
        scroll("subscribers-account")
        compose.onNodeWithTag("subscribers-account").assertIsEnabled()
        compose.onNodeWithTag("subscriber-${member.userId}").assertDoesNotExist()
    }

    @Test
    fun blockedProfileDisappearsWithoutExposingItsIdentifier() {
        val blocked = mutableStateOf(false)
        compose.setContent {
            MaterialTheme {
                SubscribersContent(
                    state(),
                    "uk",
                    SubscribersActions(),
                    { true },
                    { !blocked.value || it != member.userId },
                )
            }
        }
        scroll("subscriber-${member.userId}")
        compose.runOnIdle { blocked.value = true }
        compose.onNodeWithTag("subscriber-${member.userId}").assertDoesNotExist()
        compose.onNodeWithText(member.profile!!.displayName).assertDoesNotExist()
        compose.onNodeWithText(member.userId).assertDoesNotExist()
    }

    @Test
    fun accessRequiresFreshTargetAndSessionButNoManagementRole() {
        val fresh = mutableStateOf(true)
        val current = mutableStateOf<SubscriberSession?>(session)
        var opened: String? = null
        var account = false
        compose.setContent {
            MaterialTheme {
                SubscribersAccessPanel(
                    org.content,
                    current.value,
                    "de",
                    { opened = it },
                    { account = true },
                    { fresh.value },
                )
            }
        }
        compose.onNodeWithTag("subscribers-open").performClick()
        compose.runOnIdle {
            assertEquals(id, opened)
            fresh.value = false
        }
        compose.onNodeWithTag("subscribers-open").assertDoesNotExist()
        compose.runOnIdle {
            fresh.value = true
            current.value = session.copy(ready = false)
        }
        compose.onNodeWithTag("subscribers-open-account").performClick()
        compose.runOnIdle { assertTrue(account) }
    }

    @Test
    fun realScreenClearsRetainedPageBeforeInvokingBackNavigation() {
        val source =
            object : SubscribersSource {
                override suspend fun organization(id: String, session: SubscriberSession) =
                    RawDocument(id, org.content.fields)

                override suspend fun page(
                    id: String,
                    after: SubscriberCursor?,
                    session: SubscriberSession,
                ) = emptyList<RawDocument>()

                override suspend fun profiles(ids: List<String>, session: SubscriberSession) =
                    emptyList<RawDocument>()

                override fun changes(id: String, session: SubscriberSession) =
                    emptyFlow<Result<Unit>>()
            }
        val model = SubscribersViewModel(source, { session }, { true }, { true })
        var navigated = false
        compose.setContent {
            MaterialTheme {
                SubscribersScreen(
                    model,
                    id,
                    session,
                    "de",
                    {
                        // This assertion runs inside the callback, before Compose can dispose the
                        // old route.
                        assertNull(model.state.value.page)
                        assertFalse(model.state.value.visible)
                        navigated = true
                    },
                    {},
                    { true },
                    { true },
                )
            }
        }
        compose.waitUntil(10_000) { model.state.value.page != null && !model.state.value.loading }
        scroll("subscribers-back")
        compose.onNodeWithTag("subscribers-back").performClick()
        compose.runOnIdle {
            assertTrue(navigated)
            assertNull(model.state.value.page)
        }
    }
}
