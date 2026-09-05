package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PersonalDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun serverReadBackRulesAndIdempotencyOrOfflineGuestGate() = runBlocking {
        val db = LocalFirebase.firestore(context)
        val source = FirestorePersonalSource(db)
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            val guest = PersonalRepository(source, { null })
            try {
                guest.set(
                    PersonalTarget(ContentKind.NEWS, "synthetic-news-01"),
                    PersonalAction.LIKE,
                    true,
                )
                fail("Guest mutation")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.SIGN_IN, error.reason)
            }
            return@runBlocking
        }

        val auth = LocalFirebase.auth(context)
        // Test-only synthetic credentials are scoped to the fixed demo Auth emulator, never cloud.
        val email = "personal3b-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-local-3B-only!"
        auth.signOut()
        try {
            val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
            val registration =
                AuthRegistration(
                    email,
                    "Personal Demo",
                    "wien",
                    acceptedTerms = true,
                    acceptedPrivacy = true,
                    minimumAgeConfirmed = true,
                )
            db.document("users/${user.uid}")
                .set(registeredProfileFields(user.uid, registration, FieldValue.serverTimestamp()))
                .await()
            var current =
                PersonalSession(user.uid, emailVerified = true, active = true, revision = 1)
            val repository = PersonalRepository(source, { current })
            val news = PersonalTarget(ContentKind.NEWS, "synthetic-news-01")
            // Even a wrongly optimistic client session cannot bypass authoritative email
            // verification Rules.
            try {
                repository.set(news, PersonalAction.LIKE, true)
                fail("Unverified actual token must be denied")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.DENIED, error.reason)
            }

            user.sendEmailVerification().await()
            val code = withContext(Dispatchers.IO) { verificationCode(email) }
            auth.applyActionCode(code).await()
            user.reload().await()
            auth.currentUser!!.getIdToken(true).await()
            assertTrue(auth.currentUser!!.isEmailVerified)
            current = current.copy(revision = 2)

            val original =
                db.document("news/${news.id}").get(Source.SERVER).await().getLong("likeCount")
            for (kind in ContentKind.entries) {
                val target =
                    PersonalTarget(
                        kind,
                        when (kind) {
                            ContentKind.NEWS -> "synthetic-news-01"
                            ContentKind.EVENTS -> "synthetic-event-01"
                            ContentKind.ORGANIZATIONS -> "synthetic-org-01"
                        },
                    )
                assertTrue(repository.set(target, PersonalAction.LIKE, true))
                assertTrue(repository.set(target, PersonalAction.LIKE, true))
                assertTrue(repository.set(target, PersonalAction.BOOKMARK, true))
                assertTrue(repository.set(target, PersonalAction.BOOKMARK, true))
                val actions = repository.actions(target)
                assertTrue(actions.liked)
                assertTrue(actions.bookmarked)
                assertEquals(listOf(target.id), repository.saved(kind).items.map { it.id })
                assertFalse(repository.set(target, PersonalAction.LIKE, false))
                assertFalse(repository.set(target, PersonalAction.LIKE, false))
                assertFalse(repository.set(target, PersonalAction.BOOKMARK, false))
                assertFalse(repository.set(target, PersonalAction.BOOKMARK, false))
            }
            // Functions are not running in this test: client must not adjust any aggregate counter
            // itself.
            assertEquals(
                original,
                db.document("news/${news.id}").get(Source.SERVER).await().getLong("likeCount"),
            )

            val org = PersonalTarget(ContentKind.ORGANIZATIONS, "synthetic-org-01")
            assertTrue(repository.set(org, PersonalAction.SUBSCRIBE, true))
            assertTrue(repository.set(org, PersonalAction.SUBSCRIBE, true))
            assertEquals(listOf(org.id), repository.subscriptions().items.map { it.id })
            val subscription = PersonalMarker(org, user.uid, PersonalAction.SUBSCRIBE)
            val stored = db.document(subscription.path).get(Source.SERVER).await()
            assertEquals(
                setOf("id", "userId", "subscribedOrganizationId", "createdAt"),
                stored.data!!.keys,
            )
            assertNotNull(stored.getTimestamp("createdAt"))
            assertFalse(repository.set(org, PersonalAction.SUBSCRIBE, false))

            val draft =
                ProfileDraft(
                    "  Demo Full  ",
                    "  Нове ім’я  ",
                    " Wien ",
                    "Demo biography",
                    "demo_user",
                    "tirol",
                    "https://example.invalid/demo-avatar.jpg",
                )
            val saved = repository.saveProfile(draft)
            assertEquals(draft.normalized(), saved.draft)
            val privateProfile = db.document("users/${user.uid}").get(Source.SERVER).await()
            val publicProfile = db.document("publicProfiles/${user.uid}").get(Source.SERVER).await()
            assertEquals("user", privateProfile.getString("globalRole"))
            assertEquals("active", privateProfile.getString("accountStatus"))
            assertEquals(email, privateProfile.getString("email"))
            assertEquals("2026.10", privateProfile.getString("acceptedTermsVersion"))
            assertFalse(publicProfile.contains("email"))
            assertFalse(publicProfile.contains("bio"))
            assertFalse(publicProfile.contains("telegramUsername"))
            assertEquals("Нове ім’я", publicProfile.getString("displayName"))
            repository.saveProfile(draft.copy(avatarUrl = "", telegramUsername = ""))
            assertFalse(
                db.document("publicProfiles/${user.uid}")
                    .get(Source.SERVER)
                    .await()
                    .contains("avatarURL")
            )
            assertFalse(
                db.document("users/${user.uid}").get(Source.SERVER).await().contains("avatarURL")
            )

            assertDenied { db.document("users/${user.uid}").update("globalRole", "owner").await() }
            assertDenied {
                db.document("users/synthetic-personal-foreign/newsBookmarks/${news.id}")
                    .get(Source.SERVER)
                    .await()
            }
            try {
                repository.set(
                    PersonalTarget(ContentKind.NEWS, "synthetic-news-private"),
                    PersonalAction.BOOKMARK,
                    true,
                )
                fail("Private target")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.DENIED, error.reason)
            }
            current = current.copy(active = false, revision = 3)
            try {
                repository.saveProfile(draft)
                fail("Client gate")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.NOT_READY, error.reason)
            }
        } finally {
            auth.signOut()
        }
    }

    private suspend fun assertDenied(operation: suspend () -> Unit) {
        try {
            operation()
            fail("Expected Rules denial")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    private fun verificationCode(email: String): String {
        val url = URL("http://10.0.2.2:9098/emulator/v1/projects/demo-uac-android/oobCodes")
        check(url.host == "10.0.2.2" && url.port == 9098)
        val connection = url.openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 5_000
        connection.readTimeout = 5_000
        return try {
            check(connection.responseCode == 200) { "Local Auth fixture lookup failed" }
            val json = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val codes = json.getJSONArray("oobCodes")
            (0 until codes.length())
                .map { codes.getJSONObject(it) }
                .last {
                    it.optString("email") == email && it.optString("requestType") == "VERIFY_EMAIL"
                }
                .getString("oobCode")
        } finally {
            connection.disconnect()
        }
    }
}
