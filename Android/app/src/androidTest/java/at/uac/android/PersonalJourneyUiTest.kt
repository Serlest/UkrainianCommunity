package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.PersonalAction
import at.uac.android.feature.personal.PersonalMarker
import at.uac.android.feature.personal.PersonalTarget
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.safety.SafetyFailure
import at.uac.android.feature.safety.SafetyViewModel
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real application UI, real demo SDK/Rules and server read-back; no injected successful UI state.
 */
@RunWith(AndroidJUnit4::class)
class PersonalJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val personal
        get() = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private val store
        get() = LocalAuthSession.get(context)

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    private fun ready() {
        compose.waitUntil(30_000) { !browse.state.value.data.loading }
        compose.waitForIdle()
    }

    private fun account(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun detail(tag: String) {
        try {
            compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
            compose.onNodeWithTag(tag).performScrollTo()
        } catch (error: Throwable) {
            val content = browse.state.value
            val safety =
                ViewModelProvider(compose.activity)[SafetyViewModel::class.java].state.value
            throw AssertionError(
                "Personal journey target=$tag, route=${content.route}, mode=${content.mode}, language=${content.language}, region=${content.region}, search01=${content.search == "01"}, category=${content.category}, loading=${content.data.loading}, error=${content.data.error}, count=${content.data.items.size}, targetInSource=${content.data.items.any { "card-${it.id}" == tag }}, hasMore=${content.data.hasMore}, ready=${store.state.value.readyForActions}, safetyLoaded=${safety.visibility.loaded}, safetyLoading=${safety.loading}, safetyError=${safety.error}",
                error,
            )
        }
    }

    private fun tab(route: String) {
        if (route == "news") {
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-home").isDisplayed() }
            compose.onNodeWithTag("tab-home").performClick()
            ready()
            detail("tab-news")
            compose.onNodeWithTag("tab-news").performClick()
            ready()
            return
        }
        if (!browse.state.value.isAccountRoute)
            compose.onNodeWithTag("browse-list").performScrollToIndex(0)
        compose.waitUntil(10_000) { compose.onNodeWithTag("tab-$route").isDisplayed() }
        compose.onNodeWithTag("tab-$route").performClick()
        ready()
    }

    private fun requireSafetyFor(targetTag: String) {
        compose.waitUntil(25_000) {
            safety.state.value.visibility.loaded || safety.state.value.error != null
        }
        if (safety.state.value.error == SafetyFailure.OFFLINE) {
            // The initial failure remains evidence; only this explicit, read-only recovery is
            // attempted once.
            println("PERSONAL_SAFETY_INITIAL_OFFLINE ${safety.state.value.readDiagnostic}")
            compose.onNodeWithTag(targetTag).assertDoesNotExist()
            detail("safety-availability-retry")
            compose.onNodeWithTag("safety-availability-retry").assertIsDisplayed().performClick()
            compose.waitUntil(25_000) { !safety.state.value.loading }
        }
        assertNull(
            "Block policy must be confirmed before content is exposed",
            safety.state.value.error,
        )
        assertTrue(
            "Content visibility must never bypass unknown block policy",
            safety.state.value.visibility.loaded,
        )
    }

    @Test
    fun verifiedAccountJourneyOrOfflineReadOnlyGate() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("region", "")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (!online) {
            account("guest-sign-in")
            compose.onNodeWithTag("guest-sign-in").assertIsDisplayed()
            compose.onNodeWithTag("account-open-saved").assertDoesNotExist()
            assertNull(personal.state.value.profile)
            return
        }

        val email = "personal-journey-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-journey-only-3B!"
        val uid = prepareVerifiedAccount(email, password)
        val news = PersonalTarget(ContentKind.NEWS, "synthetic-news-01")
        val org = PersonalTarget(ContentKind.ORGANIZATIONS, "synthetic-org-01")
        try {
            compose.openGuestLogin()
            account("auth-email")
            compose.onNodeWithTag("auth-email").performTextReplacement(email)
            account("auth-password")
            compose.onNodeWithTag("auth-password").performTextReplacement(password)
            account("auth-login-submit")
            compose.onNodeWithTag("auth-login-submit").performClick()
            compose.waitUntil(20_000) { store.state.value.readyForActions }
            account("account-open-edit")
            compose.onNodeWithTag("account-open-edit").performClick()
            ready()
            compose.waitUntil(15_000) {
                personal.state.value.profile != null && !personal.state.value.profileLoading
            }
            account("profile-display-name")
            compose.onNodeWithTag("profile-display-name").performTextReplacement("Journey Profil")
            account("profile-save")
            compose.onNodeWithTag("profile-save").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.profileSaved && !personal.state.value.profileSaving
            }
            compose.onNodeWithTag("profile-saved").performScrollTo().assertIsDisplayed()
            verifyProfile(uid)
            screenshot("profile")
            compose.onNodeWithTag("back").performClick()
            ready()

            tab("news")
            detail("search")
            compose.onNodeWithTag("search").performTextReplacement("01")
            ready()
            requireSafetyFor("card-${news.id}")
            detail("card-${news.id}")
            compose.onNodeWithTag("card-${news.id}").performClick()
            ready()
            detail("personal-like")
            compose.onNodeWithTag("personal-like").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.actions[news]?.liked == true &&
                    news !in personal.state.value.actionsPending
            }
            detail("personal-bookmark")
            compose.onNodeWithTag("personal-bookmark").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.actions[news]?.bookmarked == true &&
                    news !in personal.state.value.actionsPending
            }
            verifyMarker(PersonalMarker(news, uid, PersonalAction.LIKE))
            verifyMarker(PersonalMarker(news, uid, PersonalAction.BOOKMARK))
            compose.onNodeWithTag("back").performClick()
            ready()
            tab("profile")
            account("account-open-saved")
            compose.onNodeWithTag("account-open-saved").performClick()
            ready()
            compose.waitUntil(15_000) {
                !personal.state.value.savedLoading &&
                    personal.state.value.saved[ContentKind.NEWS]?.items?.any { it.id == news.id } ==
                        true
            }
            compose
                .onNodeWithTag("personal-saved-list")
                .performScrollToNode(hasText("Beispielnachricht 01"))
            screenshot("saved")
            compose.onNodeWithText("Beispielnachricht 01").performClick()
            ready()
            assertEquals("emulator", browse.state.value.mode)
            assertEquals(news.key, browse.state.value.route)
            compose.onNodeWithTag("back").performClick()
            ready()
            assertEquals("profile/saved", browse.state.value.route)
            compose.onNodeWithTag("back").performClick()
            ready()

            tab("organizations")
            detail("search")
            compose.onNodeWithTag("search").performTextReplacement("01")
            ready()
            detail("card-${org.id}")
            compose.onNodeWithTag("card-${org.id}").performClick()
            ready()
            detail("personal-subscribe")
            compose.onNodeWithTag("personal-subscribe").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.actions[org]?.subscribed == true &&
                    org !in personal.state.value.actionsPending
            }
            verifyMarker(PersonalMarker(org, uid, PersonalAction.SUBSCRIBE))
            compose.onNodeWithTag("back").performClick()
            ready()
            tab("profile")
            account("account-open-subscriptions")
            compose.onNodeWithTag("account-open-subscriptions").performClick()
            ready()
            compose.waitUntil(15_000) {
                personal.state.value.subscriptions?.items?.any { it.id == org.id } == true
            }
            compose
                .onNodeWithTag("personal-subscriptions-list")
                .performScrollToNode(hasText("Beispielverein 01"))
            compose.onNodeWithText("Beispielverein 01").assertIsDisplayed()
            screenshot("subscriptions")
            compose.onNodeWithTag("back").performClick()
            ready()
            account("auth-signout")
            compose.onNodeWithTag("auth-signout").performClick()
            compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
            compose.waitUntil(5_000) { personal.state.value.session == null }
            assertNull(personal.state.value.profile)
            assertTrue(personal.state.value.saved.isEmpty())
            assertTrue(personal.state.value.actions.isEmpty())
            compose.onNodeWithTag("account-open-saved").assertDoesNotExist()
            account("guest-sign-in")
            compose.onNodeWithTag("guest-sign-in").assertIsDisplayed()
        } finally {
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        }
    }

    private fun prepareVerifiedAccount(email: String, password: String): String = runBlocking {
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        // These are the same exact versioned local fixtures used by AuthDeviceTest, not published
        // documents.
        val legal = FirestoreAuthProfiles(db).legalDocuments()
        assertEquals(AuthRegistration.TERMS_VERSION, legal.first { it.type == "terms" }.version)
        assertEquals(AuthRegistration.PRIVACY_VERSION, legal.first { it.type == "privacy" }.version)
        val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
        val draft =
            AuthRegistration(
                email,
                "Journey Demo",
                "wien",
                acceptedTerms = true,
                acceptedPrivacy = true,
                minimumAgeConfirmed = true,
            )
        db.document("users/${user.uid}")
            .set(registeredProfileFields(user.uid, draft, FieldValue.serverTimestamp()))
            .await()
        user.sendEmailVerification().await()
        val code =
            withContext(Dispatchers.IO) {
                val connection =
                    URL("http://10.0.2.2:9098/emulator/v1/projects/demo-uac-android/oobCodes")
                        .openConnection() as HttpURLConnection
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                try {
                    check(connection.responseCode == 200)
                    val codes =
                        JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                            .getJSONArray("oobCodes")
                    (0 until codes.length())
                        .map { codes.getJSONObject(it) }
                        .last {
                            it.optString("email") == email &&
                                it.optString("requestType") == "VERIFY_EMAIL"
                        }
                        .getString("oobCode")
                } finally {
                    connection.disconnect()
                }
            }
        auth.applyActionCode(code).await()
        user.reload().await()
        user.getIdToken(true).await()
        assertTrue(user.isEmailVerified)
        auth.signOut()
        user.uid
    }

    private fun verifyProfile(uid: String) = runBlocking {
        val db = LocalFirebase.firestore(context)
        assertEquals(
            "Journey Profil",
            db.document("users/$uid").get(Source.SERVER).await().getString("displayName"),
        )
        val public = db.document("publicProfiles/$uid").get(Source.SERVER).await()
        assertEquals("Journey Profil", public.getString("displayName"))
        assertFalse(public.contains("email"))
    }

    private fun verifyMarker(marker: PersonalMarker) = runBlocking {
        val record =
            LocalFirebase.firestore(context).document(marker.path).get(Source.SERVER).await()
        assertTrue(record.exists())
        marker.identityFields().forEach { (key, value) ->
            assertEquals(value, record.getString(key))
        }
        assertNotNull(record.getTimestamp("createdAt"))
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        check(bitmap != null)
        val directory = context.externalCacheDir ?: error("Test screenshot directory missing")
        File(directory, "personal-journey-$name.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
