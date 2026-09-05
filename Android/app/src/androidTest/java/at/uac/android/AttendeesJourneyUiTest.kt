package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.attendees.*
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Main routing and server-confirmed detail → role-only entry → private list. No fake attendee
 * state is injected.
 */
@RunWith(AndroidJUnit4::class)
class AttendeesJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val attendees
        get() = ViewModelProvider(compose.activity)[AttendeesViewModel::class.java]

    private val access
        get() = ViewModelProvider(compose.activity)[AttendeesAccessViewModel::class.java]

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun detail(tag: String) =
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))

    private fun list(tag: String) {
        // A live listener may invalidate the first completed page before the next UI action.
        // As in the subscriber journey, wait for the rendered target, not only a state sample.
        // Only read-only scrolling is retried; taps, role changes and count assertions are not.
        compose.waitUntil(30_000) {
            val state = attendees.state.value
            if (state.loading || (state.page == null && tag != "attendees-back")) false
            else
                runCatching {
                        compose.onNodeWithTag("attendees-list").performScrollToNode(hasTestTag(tag))
                        compose.onNodeWithTag(tag).isDisplayed()
                    }
                    .getOrDefault(false)
        }
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    private var phase = "setup"

    @Test
    fun mainEntryReadsOnlyWhenAuthorizedAndRoleChangesHideThenRestoreTheList() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Offline guard is not an actual attendee Main journey",
            AccountDeletionFixtures.online(),
        )
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-attendee-journey")
        }
        val fixture = AttendeesDeviceFixtures("attendees-${UUID.randomUUID()}", user.uid)
        var primaryFailure: Throwable? = null
        try {
            runBlocking {
                fixture.seedEventAndOrganization(31)
                for (index in 0..30) fixture.seedPerson(
                    index,
                    dated = index != 30,
                    publicProfile = index != 30,
                )
            }
            LocalFirebase.auth(context).signOut()
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(user.email)
            control("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            control("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }

            phase = "server-confirmed public event and fresh role-only entry"
            // Exercise the same public route used by a deep link; the browse repository must
            // actually fetch it.
            compose.runOnIdle { browse.navigate("events/${fixture.eventId}") }
            compose.waitUntil(30_000) {
                browse.state.value.data.detail?.id == fixture.eventId &&
                    !browse.state.value.data.loading &&
                    browse.state.value.data.cachedAt == null &&
                    access.canOpen(fixture.eventId, auth.state.value.attendeesScope())
            }
            assertNull(
                "The entry eligibility must not prefetch a private attendee page",
                attendees.state.value.page,
            )
            detail("attendees-open")
            compose.onNodeWithTag("attendees-open").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                attendees.state.value.page?.people?.size == 25 && !attendees.state.value.loading
            }
            assertEquals("profile/attendees/${fixture.eventId}", browse.state.value.route)
            list("attendees-partial")
            compose.onNodeWithTag("attendees-partial").assertIsDisplayed()
            list("attendees-more")
            compose.onNodeWithTag("attendees-more").performClick()
            compose.waitUntil(30_000) {
                attendees.state.value.page?.people?.size == 31 && !attendees.state.value.loading
            }
            assertNull(attendees.state.value.page!!.next)
            list("attendees-search")
            compose.onNodeWithTag("attendees-search").performTextReplacement("attendee 00")
            val rowId = fixture.registrationPath(0).substringAfter('/')
            list("attendee-$rowId")
            compose.onNodeWithText("Synthetic public attendee 00").assertIsDisplayed()
            compose.onNodeWithText(fixture.personId(0)).assertDoesNotExist()

            phase = "actual organization role removed while private list is visible"
            runBlocking {
                fixture.patch(
                    "organizations/${fixture.organizationId}",
                    mapOf("ownerId" to "synthetic-foreign-owner"),
                )
            }
            compose.waitUntil(30_000) {
                attendees.state.value.page == null &&
                    attendees.state.value.error == AttendeesFailure.DENIED
            }
            compose.onNodeWithText("Synthetic public attendee 00").assertDoesNotExist()
            list("attendees-back")
            compose.onNodeWithTag("attendees-back").performClick()
            compose.waitUntil(30_000) {
                browse.state.value.route == "events/${fixture.eventId}" &&
                    !browse.state.value.data.loading
            }
            compose.waitUntil(30_000) {
                access.state.value.error == AttendeesFailure.DENIED && !access.state.value.checking
            }
            compose.onNodeWithTag("attendees-open").assertDoesNotExist()

            phase = "actual organization moderator grant revalidates the public entry"
            runBlocking {
                fixture.patch(
                    "organizations/${fixture.organizationId}",
                    mapOf("moderatorIds" to listOf(user.uid)),
                )
            }
            compose.waitUntil(30_000) {
                access.canOpen(fixture.eventId, auth.state.value.attendeesScope())
            }
            detail("attendees-open")
            compose.onNodeWithTag("attendees-open").performClick()
            compose.waitUntil(30_000) {
                attendees.state.value.page?.people?.size == 25 && !attendees.state.value.loading
            }
            assertEquals("", attendees.state.value.search)
            list("attendees-back")
            compose.onNodeWithTag("attendees-back").performClick()
            compose.waitUntil(30_000) {
                browse.state.value.route == "events/${fixture.eventId}" &&
                    !browse.state.value.data.loading
            }
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            control("auth-signout").performClick()
            compose.waitUntil(30_000) {
                auth.state.value.stage == AuthStage.GUEST &&
                    attendees.state.value.session == null &&
                    access.state.value.session == null
            }
            assertNull(attendees.state.value.page)
            assertFalse(access.state.value.permitted)
            runBlocking {
                for (index in 0..30) assertEquals(
                    fixture.personId(index),
                    fixture
                        .read(fixture.registrationPath(index))
                        .getJSONObject("fields")
                        .getJSONObject("userId")
                        .getString("stringValue"),
                )
                assertEquals(
                    "31",
                    fixture
                        .read("events/${fixture.eventId}")
                        .getJSONObject("fields")
                        .getJSONObject("registeredCount")
                        .getString("integerValue"),
                )
            }
        } catch (error: Throwable) {
            val safe =
                "Attendee journey phase=$phase, ready=${auth.state.value.readyForActions}, " +
                    "accessPermitted=${access.state.value.permitted}, accessChecking=${access.state.value.checking}, accessError=${access.state.value.error}, " +
                    "listLoading=${attendees.state.value.loading}, listError=${attendees.state.value.error}, rows=${attendees.state.value.page?.people?.size}"
            val failure = AssertionError(safe, error)
            primaryFailure = failure
            throw failure
        } finally {
            var cleanupFailure = primaryFailure
            fun clean(action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    if (cleanupFailure == null) cleanupFailure = error
                    else cleanupFailure!!.addSuppressed(error)
                }
            }
            clean { runBlocking { fixture.cleanup() } }
            clean {
                runBlocking {
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    AccountDeletionFixtures.clean(user)
                }
            }
            clean { runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() } }
            if (primaryFailure == null) cleanupFailure?.let { throw it }
        }
    }
}
