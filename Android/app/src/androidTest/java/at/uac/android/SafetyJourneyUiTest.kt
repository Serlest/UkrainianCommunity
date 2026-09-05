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
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.PersonalTarget
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.safety.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Full MainActivity safety integration proof, with fresh demo identities and authoritative server
 * confirmations.
 */
@RunWith(AndroidJUnit4::class)
class SafetyJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private val personal
        get() = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]

    private val store
        get() = LocalAuthSession.get(context)

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"

    private val password = "Synthetic-safety-journey-only!"

    private fun ready() {
        compose.waitUntil(30_000) { !browse.state.value.data.loading }
        compose.waitForIdle()
    }

    private fun account(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun detail(tag: String) {
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
    }

    private fun tab(route: String) {
        // News is a Home action, not a fifth persistent tab. A tab switch may restore its
        // previous destination, while a second explicit tap returns to the tab root.
        val primary = if (route == "news") "home" else route
        compose.waitUntil(10_000) { compose.onNodeWithTag("tab-$primary").isDisplayed() }
        compose.onNodeWithTag("tab-$primary").performClick()
        ready()
        if (browse.state.value.route != primary) {
            compose.onNodeWithTag("tab-$primary").performClick()
            ready()
        }
        assertEquals(primary, browse.state.value.route)
        if (route == "news") {
            detail("tab-news")
            compose.onNodeWithTag("tab-news").assertIsDisplayed().performClick()
            ready()
            assertEquals("news", browse.state.value.route)
        }
    }

    private fun openContent(kind: String, id: String, query: String) {
        tab(kind)
        detail("search")
        compose.onNodeWithTag("search").performTextReplacement(query)
        ready()
        detail("card-$id")
        compose.onNodeWithTag("card-$id").performClick()
        ready()
    }

    private fun login(email: String) {
        compose.openGuestLogin()
        account("auth-email")
        compose.onNodeWithTag("auth-email").performTextReplacement(email)
        account("auth-password")
        compose.onNodeWithTag("auth-password").performTextReplacement(password)
        account("auth-login-submit")
        compose.onNodeWithTag("auth-login-submit").performClick()
        compose.waitUntil(30_000) {
            store.state.value.readyForActions && safety.state.value.blocks != null
        }
    }

    private fun logout() {
        account("auth-signout")
        compose.onNodeWithTag("auth-signout").performClick()
        compose.waitUntil(15_000) {
            store.state.value.stage == AuthStage.GUEST &&
                safety.state.value.session == null &&
                personal.state.value.session == null
        }
        assertTrue(safety.state.value.reports.isEmpty())
        assertNull(safety.state.value.blocks)
        assertTrue(personal.state.value.saved.isEmpty())
        assertNull(personal.state.value.subscriptions)
    }

    private fun blockedList() {
        tab("profile")
        account("account-open-blocked")
        compose.onNodeWithTag("account-open-blocked").performClick()
        ready()
        assertEquals("profile/blocked", browse.state.value.route)
    }

    private fun unblock(key: String) {
        compose
            .onNodeWithTag("safety-blocked-list")
            .performScrollToNode(hasTestTag("safety-unblock-$key"))
        compose.onNodeWithTag("safety-unblock-$key").performClick()
        compose.onNodeWithTag("safety-block-confirm").performClick()
        compose.waitUntil(20_000) {
            safety.state.value.pendingBlocks.isEmpty() && safety.state.value.blockErrors.isEmpty()
        }
    }

    @Test
    fun realReportBlockUnblockAndPrivateListsStayWithinCurrentAccount() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("region", "")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        if (!online) {
            account("guest-sign-in")
            compose.onNodeWithTag("guest-sign-in").assertIsDisplayed()
            assertNull(safety.state.value.session)
            return
        }
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val suffix = UUID.randomUUID().toString()
        val prefix = "safetyjourney-$suffix"
        val label = "Safety Reise ${suffix.take(8)}"
        val author = "$prefix-author"
        val org = "$prefix-org"
        val news = "$prefix-news"
        val emailA = "$prefix-a@example.invalid"
        val emailB = "$prefix-b@example.invalid"
        val accounts = mutableListOf<Pair<String, String>>()
        val fixtures = mutableSetOf<String>()
        val reportIds = mutableSetOf<String>()
        val newsTitle = "$label Nachricht"
        val orgTitle = "$label Verein"
        val reportTarget = SafetyReportTarget(SafetyTargetType.NEWS, news, newsTitle, author)
        val now = Instant.now()
        try {
            runBlocking {
                AuthEmulatorFixtures.seedLegalReference()
                accounts += emailA to prepareAccount(emailA)
                accounts += emailB to prepareAccount(emailB)
                admin(
                    "users/$author",
                    mapOf(
                        "id" to author,
                        "displayName" to "Safety Testperson",
                        "globalRole" to "user",
                        "accountStatus" to "active",
                        "blockState" to "active",
                    ),
                )
                fixtures += "users/$author"
                admin(
                    "publicProfiles/$author",
                    mapOf("id" to author, "displayName" to "Safety Testperson", "updatedAt" to now),
                )
                fixtures += "publicProfiles/$author"
                admin(
                    "organizations/$org",
                    mapOf(
                        "id" to org,
                        "name" to orgTitle,
                        "description" to "Synthetic organization",
                        "shortDescription" to "Synthetic organization",
                        "fullDescription" to "Synthetic organization for UI verification",
                        "city" to "Wien",
                        "federalState" to "wien",
                        "ownerId" to author,
                        "adminIds" to emptyList<String>(),
                        "moderatorIds" to emptyList<String>(),
                        "moderationStatus" to "approved",
                        "createdAt" to now,
                        "updatedAt" to now,
                    ),
                )
                fixtures += "organizations/$org"
                admin(
                    "news/$news",
                    mapOf(
                        "id" to news,
                        "title" to newsTitle,
                        "summary" to "Synthetic UI verification",
                        "body" to "Synthetic news for the full safety journey.",
                        "sourceType" to "organization",
                        "organizationId" to org,
                        "authorId" to author,
                        "moderationStatus" to "approved",
                        "category" to "community",
                        "federalState" to "wien",
                        "createdAt" to now,
                        "updatedAt" to now,
                        "publishedAt" to now,
                    ),
                )
                fixtures += "news/$news"
            }
            login(emailA)
            val uid = accounts.first().second
            openContent("news", news, label)
            detail("personal-bookmark")
            compose.onNodeWithTag("personal-bookmark").performClick()
            compose.waitUntil(20_000) {
                personal.state.value.actions[PersonalTarget(ContentKind.NEWS, news)]?.bookmarked ==
                    true
            }
            detail("safety-report")
            compose.onNodeWithTag("safety-report").performClick()
            compose.onNodeWithTag("safety-reason-spam").performScrollTo().performClick()
            compose
                .onNodeWithTag("safety-explanation")
                .performScrollTo()
                .performTextReplacement("Synthetic report from the full Android safety journey.")
            compose.onNodeWithTag("safety-good-faith").performScrollTo().performClick()
            compose.onNodeWithTag("safety-report-submit").performClick()
            compose.waitUntil(30_000) {
                safety.state.value.reports[reportTarget.key]?.receipt != null
            }
            val receipt = safety.state.value.reports[reportTarget.key]!!.receipt!!
            reportIds += receipt.id
            compose.onNodeWithTag("safety-report-confirmed").performScrollTo().assertIsDisplayed()
            runBlocking {
                val stored =
                    LocalFirebase.firestore(context)
                        .document("feedback/${receipt.id}")
                        .get(Source.SERVER)
                        .await()
                assertEquals(uid, stored.getString("userId"))
                assertEquals(news, stored.getString("reportContext.targetId"))
                assertEquals(receipt.caseNumber, stored.getString("dsaCase.caseNumber"))
            }
            screenshot("report")
            compose.onNodeWithTag("safety-report-close").performClick()
            detail("safety-block-user")
            compose.onNodeWithTag("safety-block-user").performClick()
            compose.onNodeWithTag("safety-block-confirm").performClick()
            compose.waitUntil(20_000) { author in safety.state.value.visibility.blockedUserIds }
            detail("safety-hidden-detail")
            compose.onNodeWithTag("safety-hidden-detail").assertIsDisplayed()
            compose.onNodeWithTag("personal-bookmark").assertDoesNotExist()
            assertDocument("users/$uid/blockedUsers/$author", true)
            compose.onNodeWithTag("back").performClick()
            ready()
            compose.onNodeWithTag("card-$news").assertDoesNotExist()
            blockedList()
            screenshot("blocked")
            unblock("user:$author")
            assertDocument("users/$uid/blockedUsers/$author", false)
            compose.waitUntil(15_000) { author !in safety.state.value.visibility.blockedUserIds }
            compose.onNodeWithTag("back").performClick()
            ready()

            openContent("organizations", org, label)
            detail("personal-subscribe")
            compose.onNodeWithTag("personal-subscribe").performClick()
            compose.waitUntil(20_000) {
                personal.state.value.actions[PersonalTarget(ContentKind.ORGANIZATIONS, org)]
                    ?.subscribed == true
            }
            detail("safety-block-organization")
            compose.onNodeWithTag("safety-block-organization").performClick()
            compose.onNodeWithTag("safety-block-confirm").performClick()
            compose.waitUntil(20_000) {
                org in safety.state.value.visibility.blockedOrganizationIds
            }
            detail("safety-hidden-detail")
            compose.onNodeWithTag("safety-hidden-detail").assertIsDisplayed()
            compose.onNodeWithTag("back").performClick()
            ready()
            tab("news")
            compose.onNodeWithTag("card-$news").assertDoesNotExist()
            blockedList()
            unblock("organization:$org")
            compose.waitUntil(20_000) {
                org !in safety.state.value.visibility.blockedOrganizationIds
            }
            compose.onNodeWithTag("back").performClick()
            ready()

            account("account-open-saved")
            compose.onNodeWithTag("account-open-saved").performClick()
            ready()
            compose.waitUntil(20_000) {
                personal.state.value.saved[ContentKind.NEWS]?.items?.any { it.id == news } == true
            }
            compose.onNodeWithTag("personal-saved-list").performScrollToNode(hasText(newsTitle))
            compose.onNodeWithText(newsTitle).assertIsDisplayed()
            compose.onNodeWithTag("back").performClick()
            ready()
            account("account-open-subscriptions")
            compose.onNodeWithTag("account-open-subscriptions").performClick()
            ready()
            compose.waitUntil(20_000) {
                personal.state.value.subscriptions?.items?.any { it.id == org } == true
            }
            compose
                .onNodeWithTag("personal-subscriptions-list")
                .performScrollToNode(hasText(orgTitle))
            compose.onNodeWithText(orgTitle).assertIsDisplayed()
            screenshot("restored")
            compose.onNodeWithTag("back").performClick()
            ready()
            logout()

            login(emailB)
            assertTrue(safety.state.value.blocks!!.users.isEmpty())
            assertTrue(safety.state.value.blocks!!.organizations.isEmpty())
            assertTrue(safety.state.value.reports.isEmpty())
            account("account-open-saved")
            compose.onNodeWithTag("account-open-saved").performClick()
            ready()
            compose.waitUntil(20_000) {
                !personal.state.value.savedLoading && personal.state.value.saved.isNotEmpty()
            }
            assertTrue(personal.state.value.saved.values.all { it.items.isEmpty() })
            compose.onNodeWithText(newsTitle).assertDoesNotExist()
            compose.onNodeWithTag("back").performClick()
            ready()
            account("account-open-subscriptions")
            compose.onNodeWithTag("account-open-subscriptions").performClick()
            ready()
            compose.waitUntil(20_000) {
                personal.state.value.subscriptions != null &&
                    !personal.state.value.subscriptionsLoading
            }
            assertTrue(personal.state.value.subscriptions!!.items.isEmpty())
            compose.onNodeWithText(orgTitle).assertDoesNotExist()
            compose.onNodeWithTag("back").performClick()
            ready()
            logout()
        } finally {
            runBlocking {
                withContext(Dispatchers.Main) { store.signOut() }.join()
                for (id in reportIds) {
                    admin("feedback/$id")
                    admin("dsaCases/$id")
                }
                for ((email, uid) in accounts) {
                    for (path in
                        listOf(
                            "users/$uid/newsBookmarks/$news",
                            "likes/organization_follow_${org}_$uid",
                            "users/$uid/blockedUsers/$author",
                            "users/$uid/blockedOrganizations/$org",
                        )) admin(path)
                    LocalFirebase.auth(context).signInWithEmailAndPassword(email, password).await()
                    LocalFirebase.auth(context).currentUser!!.delete().await()
                    admin("users/$uid")
                    admin("publicProfiles/$uid")
                }
                for (path in fixtures.toList().asReversed()) admin(path)
                withContext(Dispatchers.Main) { store.signOut() }.join()
            }
        }
    }

    private suspend fun prepareAccount(email: String): String {
        val auth = LocalFirebase.auth(context)
        val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
        LocalFirebase.firestore(context)
            .document("users/${user.uid}")
            .set(
                registeredProfileFields(
                    user.uid,
                    AuthRegistration(
                        email,
                        "Safety Journey",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                    FieldValue.serverTimestamp(),
                )
            )
            .await()
        user.sendEmailVerification().await()
        auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
        user.reload().await()
        user.getIdToken(true).await()
        auth.signOut()
        return user.uid
    }

    private fun assertDocument(path: String, exists: Boolean) = runBlocking {
        assertEquals(
            exists,
            LocalFirebase.firestore(context).document(path).get(Source.SERVER).await().exists(),
        )
    }

    private suspend fun admin(path: String, fields: Map<String, Any>? = null) =
        withContext(Dispatchers.IO) {
            val url = "http://10.0.2.2:8088${AuthEmulatorFixtures.documentPath(path)}"
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = if (fields == null) "DELETE" else "PATCH"
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (fields != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    val payload =
                        JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) }))
                    connection.outputStream.use { it.write(payload.toString().toByteArray()) }
                }
                check(
                    connection.responseCode in 200..299 ||
                        (fields == null && connection.responseCode == 404)
                ) {
                    "Synthetic fixture operation failed"
                }
            } finally {
                connection.disconnect()
            }
        }

    private fun value(item: Any): JSONObject =
        when (item) {
            is String -> JSONObject().put("stringValue", item)
            is Boolean -> JSONObject().put("booleanValue", item)
            is Instant -> JSONObject().put("timestampValue", item.toString())
            is List<*> ->
                JSONObject()
                    .put(
                        "arrayValue",
                        JSONObject().put("values", JSONArray(item.map { value(it!!) })),
                    )
            else -> error("Unsupported fixture value")
        }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                ?: error("No screenshot")
        File(context.externalCacheDir, "safety-journey-$name.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
