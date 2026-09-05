package at.uac.android

import android.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.*
import at.uac.android.feature.gallery.GalleryContract
import at.uac.android.feature.gallery.GalleryTarget
import at.uac.android.feature.gallery.GalleryViewModel
import at.uac.android.feature.safety.SafetyFailure
import at.uac.android.feature.safety.SafetyViewModel
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageMetadata
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Public UI never uploads/deletes: only this exact synthetic fixture and existing Safety test
 * actions mutate.
 */
@RunWith(AndroidJUnit4::class)
class PublicGalleryJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[GalleryViewModel::class.java]

    private var phase = "setup"

    private fun detail(tag: String) {
        compose.waitUntil(30_000) {
            if (browse.state.value.data.loading) false
            else
                runCatching {
                        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
                        compose.onNodeWithTag(tag).isDisplayed()
                    }
                    .getOrDefault(false)
        }
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    private fun open(target: GalleryTarget) {
        detail("public-gallery-photo-${target.photoId}")
        compose.onNodeWithTag("public-gallery-photo-${target.photoId}").performClick()
        compose.onNodeWithTag("public-gallery-viewer").assertIsDisplayed()
        compose.waitUntil(15_000) {
            compose
                .onAllNodes(
                    hasTestTag("loaded-media") and
                        hasAnyAncestor(hasTestTag("public-gallery-image-${target.photoId}"))
                )
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose
            .onNode(
                hasTestTag("loaded-media") and
                    hasAnyAncestor(hasTestTag("public-gallery-image-${target.photoId}"))
            )
            .assertIsDisplayed()
    }

    private fun navigate(id: String) {
        compose.runOnIdle { browse.navigate("organizations/$id") }
        compose.waitUntil(30_000) {
            browse.state.value.data.let {
                it.detail?.id == id && !it.loading && it.cachedAt == null && it.error == null
            }
        }
        assertEquals(2, browse.state.value.data.photos.size)
        assertTrue(browse.state.value.data.warnings.none { it.first == "photos" })
    }

    private fun signOut() = runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }

    private fun safetyReady() {
        compose.waitUntil(25_000) {
            safety.state.value.visibility.loaded || safety.state.value.error != null
        }
        if (safety.state.value.error == SafetyFailure.OFFLINE) {
            println("PUBLIC_GALLERY_INITIAL_SAFETY_OFFLINE ${safety.state.value.readDiagnostic}")
            detail("safety-availability-retry")
            compose.onNodeWithTag("safety-availability-retry").performClick()
            compose.waitUntil(25_000) { !safety.state.value.loading }
        }
        assertTrue(safety.state.value.visibility.loaded)
        assertNull(safety.state.value.error)
    }

    @Test
    fun guestFullscreenRecreationOrdinaryAccountSafetyAndIdentitySwitchNeverMutatePhotos() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Actual public Gallery journey requires guarded local fixtures and existing Safety callables",
            AccountDeletionFixtures.online(),
        )
        signOut()
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val owner = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-public-gallery-owner")
        }
        val fixture = Fixture(owner)
        var viewer: AccountDeletionFixtures.User? = null
        var primary: Throwable? = null
        try {
            runBlocking { fixture.seed() }
            viewer = runBlocking {
                AccountDeletionFixtures.create("deletion-public-gallery-viewer")
            }
            val reader = requireNotNull(viewer)
            signOut()
            compose.waitUntil(15_000) { auth.state.value.stage == AuthStage.GUEST }
            assertNull(LocalFirebase.auth(context).currentUser)

            phase = "real guest fresh public metadata and selected fullscreen pager"
            navigate(fixture.id)
            assertNull(management.state.value.snapshot)
            assertFalse(management.state.value.visible)
            compose.onNodeWithTag("gallery-open").assertDoesNotExist()
            open(fixture.newer)
            compose.onNodeWithTag("public-gallery-page").assertTextEquals("1 / 2")
            compose
                .onNodeWithTag("public-gallery-caption-${fixture.newer.photoId}")
                .assertTextEquals("Synthetic red photo")
            compose.onNodeWithTag("public-gallery-next").performClick()
            compose.waitUntil {
                compose.onAllNodesWithText("2 / 2").fetchSemanticsNodes().isNotEmpty()
            }
            compose
                .onNodeWithTag("public-gallery-caption-${fixture.older.photoId}")
                .assertTextEquals("Synthetic blue photo")
            compose.onNodeWithTag("public-gallery-done").performClick()
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
            runBlocking { fixture.assertUnchanged() }

            phase = "real Activity recreation discards ephemeral viewer and saved pager position"
            open(fixture.older)
            compose.onNodeWithTag("public-gallery-page").assertTextEquals("2 / 2")
            compose.activityRule.scenario.recreate()
            compose.waitUntil(30_000) {
                auth.state.value.stage == AuthStage.GUEST &&
                    browse.state.value.data.let {
                        it.detail?.id == fixture.id &&
                            !it.loading &&
                            it.cachedAt == null &&
                            it.error == null
                    }
            }
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
            open(fixture.newer)
            compose.onNodeWithTag("public-gallery-page").assertTextEquals("1 / 2")
            phase = "a new public route invalidates the old overlay without its close callback"
            compose.runOnIdle { browse.navigate("organizations") }
            compose.waitUntil(30_000) {
                browse.state.value.route == "organizations" && !browse.state.value.data.loading
            }
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
            compose
                .onNodeWithTag("public-gallery-caption-${fixture.newer.photoId}")
                .assertDoesNotExist()

            phase = "ordinary verified Main login keeps public access separate from management"
            compose.runOnIdle { browse.navigate("profile") }
            compose.openGuestLogin()
            compose
                .onNodeWithTag("auth-email")
                .performScrollTo()
                .performTextReplacement(reader.email)
            compose
                .onNodeWithTag("auth-password")
                .performScrollTo()
                .performTextReplacement(AccountDeletionFixtures.PASSWORD)
            compose
                .onNodeWithTag("auth-login-submit")
                .performScrollTo()
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            assertEquals(reader.uid, auth.state.value.identity?.uid)
            assertEquals("user", auth.state.value.profile?.globalRole)
            navigate(fixture.id)
            safetyReady()
            compose.onNodeWithTag("gallery-open").assertDoesNotExist()
            assertNull(management.state.value.snapshot)
            assertFalse(management.state.value.visible)
            open(fixture.newer)

            phase = "existing callable-backed live organization block closes fullscreen immediately"
            val key = "organization:${fixture.id}"
            val blockPath = "users/${reader.uid}/blockedOrganizations/${fixture.id}"
            // Public gallery has no block controls. Trigger the existing root Safety operation, not
            // injected success state.
            compose.runOnIdle { safety.setOrganization(fixture.id, true) }
            compose.waitUntil(30_000) {
                key !in safety.state.value.pendingBlocks &&
                    fixture.id in safety.state.value.visibility.blockedOrganizationIds
            }
            assertNull(safety.state.value.blockErrors[key])
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
            compose.onNodeWithTag("public-gallery").assertDoesNotExist()
            assertNotNull(runBlocking { AccountDeletionFixtures.document(blockPath) })
            compose.runOnIdle { safety.setOrganization(fixture.id, false) }
            compose.waitUntil(30_000) {
                key !in safety.state.value.pendingBlocks &&
                    safety.state.value.visibility.loaded &&
                    fixture.id !in safety.state.value.visibility.blockedOrganizationIds
            }
            assertNull(safety.state.value.blockErrors[key])
            assertNull(runBlocking { AccountDeletionFixtures.document(blockPath) })
            detail("public-gallery-photo-${fixture.newer.photoId}")
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()

            phase =
                "real account transition invalidates an open viewer and returns to guest public reading"
            open(fixture.older)
            signOut()
            compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
            compose.onNodeWithTag("public-gallery-viewer").assertDoesNotExist()
            assertNull(LocalFirebase.auth(context).currentUser)
            navigate(fixture.id)
            detail("public-gallery-photo-${fixture.newer.photoId}")
            compose.onNodeWithTag("gallery-open").assertDoesNotExist()
            runBlocking { fixture.assertUnchanged() }
        } catch (error: Throwable) {
            val state = browse.state.value
            val failure =
                AssertionError(
                    "Public gallery journey phase=$phase, guest=${auth.state.value.stage == AuthStage.GUEST}, " +
                        "ready=${auth.state.value.readyForActions}, detailMatches=${state.data.detail?.id == fixture.id}, loading=${state.data.loading}, " +
                        "cached=${state.data.cachedAt != null}, browseError=${state.data.error}, photos=${state.data.photos.size}, " +
                        "safetyLoaded=${safety.state.value.visibility.loaded}, safetyError=${safety.state.value.error}",
                    error,
                )
            primary = failure
            throw failure
        } finally {
            var failure = primary
            fun cleanup(action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    val previous = failure
                    if (previous == null) failure = error else previous.addSuppressed(error)
                }
            }
            cleanup { signOut() }
            viewer?.let { actor ->
                cleanup {
                    runBlocking {
                        LocalFirebase.auth(context)
                            .signInWithEmailAndPassword(
                                actor.email,
                                AccountDeletionFixtures.PASSWORD,
                            )
                            .await()
                        AccountDeletionFixtures.clean(
                            actor,
                            listOf(
                                "users/${actor.uid}/blockedOrganizations/${fixture.id}",
                                "users/${actor.uid}/recentViews/organization_${fixture.id}",
                            ),
                        )
                    }
                }
            }
            var resourcesRemoved = false
            cleanup {
                runBlocking {
                    LocalFirebase.auth(context)
                        .signInWithEmailAndPassword(owner.email, AccountDeletionFixtures.PASSWORD)
                        .await()
                    fixture.cleanup()
                    resourcesRemoved = true
                    AccountDeletionFixtures.clean(owner)
                }
            }
            if (resourcesRemoved) cleanup { signOut() }
            else
                println(
                    "PUBLIC_GALLERY_FIXTURE_CLEANUP_PENDING ownerRetained=true exactTargetsRetained=true"
                )
            if (primary == null) failure?.let { throw it }
        }
    }

    private class Fixture(private val owner: AccountDeletionFixtures.User) {
        private val context
            get() = AccountDeletionFixtures.context

        private val delegate = GalleryDeviceTest.Fixture(owner)
        val id
            get() = delegate.organizationId

        val older = delegate.target()
        val newer = delegate.target()
        private val baselines =
            mutableMapOf<GalleryTarget, Triple<Map<String, Any>, String?, String?>>()
        private val hashes = mutableMapOf<GalleryTarget, String>()
        private lateinit var organization: Map<String, Any>

        suspend fun seed() {
            delegate.seed()
            AccountDeletionFixtures.patch(
                "organizations/$id",
                mapOf("moderationStatus" to "approved"),
                merge = true,
            )
            for ((index, target) in listOf(older, newer).withIndex()) {
                val photo = delegate.prepared(if (index == 0) Color.BLUE else Color.RED)
                val ref = LocalStorage.instance(context).reference.child(target.path)
                ref.putBytes(
                        photo.bytes(),
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
                val token =
                    requireNotNull(
                        GalleryContract.token(ref.downloadUrl.await().toString(), target)
                    )
                patch(
                    target.document,
                    mapOf(
                        "id" to target.photoId,
                        "organizationId" to id,
                        "imageURL" to GalleryContract.alias(target, token),
                        "caption" to
                            if (index == 0) "Synthetic blue photo" else "Synthetic red photo",
                        "uploadedBy" to owner.uid,
                        "createdAt" to
                            Instant.parse("2026-09-03T05:00:00Z").plusSeconds(index.toLong()),
                    ),
                )
                val metadata = ref.metadata.await()
                baselines[target] =
                    Triple(
                        requireNotNull(
                            LocalFirebase.firestore(context)
                                .document(target.document)
                                .get(Source.SERVER)
                                .await()
                                .data
                        ),
                        metadata.generation,
                        metadata.metadataGeneration,
                    )
                hashes[target] = photo.hash
            }
            patch("organizations/$id", mapOf("photoCount" to 2), mask = "photoCount")
            organization =
                requireNotNull(
                    LocalFirebase.firestore(context)
                        .document("organizations/$id")
                        .get(Source.SERVER)
                        .await()
                        .data
                )
            val repository =
                ContentRepository(
                    FirestoreContentSource(LocalFirebase.firestore(context)),
                    MemoryContentCache(),
                )
            assertEquals(id, repository.detail(ContentKind.ORGANIZATIONS, id).value.id)
            assertEquals(
                listOf(newer.photoId, older.photoId),
                repository.photos(id).value.map { it.id },
            )
        }

        suspend fun assertUnchanged() {
            val db = LocalFirebase.firestore(context)
            assertEquals(
                organization,
                db.document("organizations/$id").get(Source.SERVER).await().data,
            )
            assertEquals(
                2,
                db.collection("organizations/$id/photos").get(Source.SERVER).await().size(),
            )
            for ((target, baseline) in baselines) {
                assertEquals(
                    baseline.first,
                    db.document(target.document).get(Source.SERVER).await().data,
                )
                val ref = LocalStorage.instance(context).reference.child(target.path)
                val metadata = ref.metadata.await()
                assertEquals(baseline.second, metadata.generation)
                assertEquals(baseline.third, metadata.metadataGeneration)
                assertEquals(hashes[target], GalleryContract.hash(ref.getBytes(3_000_000).await()))
            }
        }

        suspend fun cleanup() = delegate.cleanup()

        private suspend fun patch(path: String, values: Map<String, Any>, mask: String? = null) =
            withContext(Dispatchers.IO) {
                AccountDeletionFixtures.requireLocalAvd()
                check(path in setOf("organizations/$id", older.document, newer.document))
                check(mask == null || path == "organizations/$id" && mask == "photoCount")
                fun field(value: Any): JSONObject =
                    when (value) {
                        is String -> JSONObject().put("stringValue", value)
                        is Int -> JSONObject().put("integerValue", value.toString())
                        is Instant -> JSONObject().put("timestampValue", value.toString())
                        else -> error("Unsupported public gallery fixture value")
                    }
                val connection =
                    URL(
                            "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}" +
                                if (mask == null) "" else "?updateMask.fieldPaths=$mask"
                        )
                        .openConnection() as HttpURLConnection
                try {
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 5_000
                    connection.readTimeout = 5_000
                    connection.requestMethod = "PATCH"
                    connection.doOutput = true
                    connection.setRequestProperty("Authorization", "Bearer owner")
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use {
                        it.write(
                            JSONObject()
                                .put("fields", JSONObject(values.mapValues { field(it.value) }))
                                .toString()
                                .toByteArray()
                        )
                    }
                    check(connection.responseCode in 200..299) {
                        "Public gallery fixture setup HTTP ${connection.responseCode}"
                    }
                    connection.inputStream.use { it.readBytes() }
                } finally {
                    connection.disconnect()
                }
            }
    }
}
