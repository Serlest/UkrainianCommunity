package at.uac.android

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageException
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContentCoverDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private var phase = "setup"

    @Test
    fun guestNeverLoadsPrivateCoverOrReachesMutationGate() = runBlocking {
        val gate =
            object : OrganizationMutationGate {
                override suspend fun <T> withSession(
                    session: OrganizationSession,
                    operation: suspend () -> T,
                ): T = error("Guest gate")
            }
        expect(ContentCoverFailure.SIGN_IN) {
            ContentCoverRepository(localContentCoverSource(context), { null }, gate)
                .load(ContentCoverTarget("synthetic", ContentKind.NEWS, "synthetic"))
        }
    }

    @Test
    fun actualCoverCallableRolesCanonicalBytesReplacementAndNewsReferenceRemoval() = runBlocking {
        assumeTrue(
            InstrumentationRegistry.getArguments().getString("expectEmulator") == "true" &&
                InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"
        )
        val fixture = ContentCoverFixtures("author4ccover-${UUID.randomUUID()}")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val storage = LocalStorage.instance(context)
        val source = localContentCoverSource(context)
        val functions = LocalFunctions.instance(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val gate = AuthOrganizationMutationGate(store)
        val repo = ContentCoverRepository(source, { store.state.value.organizationScope() }, gate)
        val authoring =
            AuthoringRepository(
                localAuthoringSource(context),
                { store.state.value.organizationScope() },
                gate,
            )
        var failure: Throwable? = null
        suspend fun signIn(account: ContentCoverFixtures.Account, ready: Boolean = true) {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            withContext(Dispatchers.Main) { store.signIn(account.email, fixture.password)!! }.join()
            assertEquals("$phase ready", ready, store.state.value.readyForActions)
        }
        suspend fun create(target: ContentCoverTarget) {
            val actor = requireNotNull(store.state.value.organizationScope())
            val org =
                requireNotNull(
                    localAuthoringSource(context).organization(target.organizationId, actor)
                )
            val draft =
                AuthoringContract.newDraft(target.kind, org)
                    .copy(
                        id = target.contentId,
                        title = "Synthetic cover ${target.kind.collection}",
                        summary = "Synthetic summary",
                        body = "Synthetic content only",
                    )
                    .let {
                        if (target.kind == ContentKind.EVENTS)
                            it.copy(event = it.event.copy(venue = "Synthetic hall"))
                        else it
                    }
            authoring.submit(AuthoringContract.submission(draft, org, actor, null))
        }
        suspend fun call(target: ContentCoverTarget, bytes: ByteArray) =
            withContext(Dispatchers.IO) {
                functions
                    .getHttpsCallable("uploadOrganizationContentCover")
                    .withTimeout(120_000, TimeUnit.MILLISECONDS)
                    .call(
                        mapOf(
                            "kind" to target.wireKind,
                            "contentId" to target.contentId,
                            "imageBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
                        )
                    )
                    .await()
            }
        try {
            AuthEmulatorFixtures.seedLegalReference()
            phase = "new real verified identities and scoped organization roles"
            val owner = fixture.account("owner")
            val admin = fixture.account("admin")
            val moderator = fixture.account("moderator")
            val stranger = fixture.account("stranger")
            val unverified = fixture.account("unverified", false)
            fixture.organization(owner, listOf(admin, unverified), listOf(moderator))
            fixture.organization(stranger, foreign = true)
            val news = fixture.register(ContentKind.NEWS)
            val event = fixture.register(ContentKind.EVENTS)
            val foreign = fixture.register(ContentKind.NEWS, true)
            signIn(stranger)
            create(foreign)
            signIn(owner)
            create(news)
            create(event)
            val photo = ContentCoverFixtures.noisyPhoto(4169)
            val second = ContentCoverFixtures.noisyPhoto(9173)
            assertTrue(
                "Exercise the cover-specific envelope beyond ordinary64KiB",
                Base64.encodeToString(photo.jpeg, Base64.NO_WRAP).length >
                    LocalCallableProtocol.MAX_REQUEST_BYTES,
            )
            assertNotEquals(photo.digest, second.digest)

            phase = "owner cover upload actual callable object URL token and exact bytes"
            val original = repo.load(news)
            val saved = repo.execute(ContentCoverIntent.Upload(original, photo))
            assertEquals(photo.byteCount, saved.asset!!.bytes.size)
            assertArrayEquals(photo.jpeg, saved.asset.bytes)
            assertTrue(
                saved.snapshot.imageUrl!!.startsWith("https://firebasestorage.googleapis.com/")
            )
            assertNotNull(ContentCoverContract.token(saved.snapshot.imageUrl!!, news))
            assertTrue(ContentCoverContract.preserved(original, saved.snapshot))
            assertEquals(
                "image/jpeg",
                storage.reference.child(news.path).metadata.await().contentType,
            )
            assertArrayEquals(
                photo.jpeg,
                storage.reference.child(news.path).getBytes(3_000_000).await(),
            )
            phase =
                "canonical foreign organization and malformed JPEG are denied without altering own cover"
            expect(ContentCoverFailure.DENIED) { repo.load(foreign) }
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(foreign, photo.jpeg) }
            expectCallable(LocalCallableFailure.INVALID_ARGUMENT) {
                call(news, byteArrayOf(0, 1, 2))
            }
            val missing = fixture.register(ContentKind.NEWS)
            expectCallable(LocalCallableFailure.NOT_FOUND) { call(missing, photo.jpeg) }
            assertArrayEquals(
                photo.jpeg,
                storage.reference.child(news.path).getBytes(3_000_000).await(),
            )
            try {
                storage.reference.child(news.path).delete().await()
                fail("Direct cover deletion")
            } catch (error: StorageException) {
                assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
            }

            phase =
                "fresh approved organization admin replaces news cover preserving text counters and metadata"
            signIn(admin)
            val adminBase = repo.load(news)
            val replacement = repo.execute(ContentCoverIntent.Upload(adminBase, second))
            assertArrayEquals(second.jpeg, replacement.asset!!.bytes)
            assertNotEquals(saved.snapshot.imageUrl, replacement.snapshot.imageUrl)
            assertTrue(ContentCoverContract.preserved(adminBase, replacement.snapshot))
            assertEquals(owner.uid, replacement.snapshot.item.fields["authorId"])
            phase = "organization moderator uploads event cover through singular event wire kind"
            signIn(moderator)
            val eventBase = repo.load(event)
            val eventSaved = repo.execute(ContentCoverIntent.Upload(eventBase, photo))
            assertArrayEquals(photo.jpeg, eventSaved.asset!!.bytes)
            assertEquals(event.contentId, eventSaved.snapshot.item.id)
            expect(ContentCoverFailure.READ_ONLY) {
                repo.execute(ContentCoverIntent.Remove(eventSaved.snapshot))
            }

            phase = "valid verified nonmember denied by actual function"
            signIn(stranger)
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(news, photo.jpeg) }
            phase = "unverified assigned admin denied before function writes"
            signIn(unverified, false)
            expect(ContentCoverFailure.NOT_READY) { repo.load(news) }
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(news, photo.jpeg) }

            phase = "owner News reference removal does not delete object or other fields"
            signIn(owner)
            val removeBase = repo.load(news)
            val objectBefore = storage.reference.child(news.path).getBytes(3_000_000).await()
            val removed = repo.execute(ContentCoverIntent.Remove(removeBase))
            assertNull(removed.snapshot.imageUrl)
            assertTrue(ContentCoverContract.preserved(removeBase, removed.snapshot))
            assertFalse(
                db.document("news/${news.contentId}")
                    .get(Source.SERVER)
                    .await()
                    .contains("imageURL")
            )
            assertArrayEquals(
                objectBefore,
                storage.reference.child(news.path).getBytes(3_000_000).await(),
            )
            assertEquals(200, fixture.storageStatus(news, "GET"))

            phase = "real non-TOTP token cannot bypass activated privileged MFA"
            fixture.data.patch(
                "users/${owner.uid}",
                mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to true),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            expectCallable(LocalCallableFailure.FAILED_PRECONDITION) { call(event, second.jpeg) }
            phase = "restricted verified account cannot mutate cover"
            fixture.data.patch(
                "users/${owner.uid}",
                mapOf(
                    "globalRole" to "user",
                    "requiresMultiFactorAuth" to false,
                    "accountStatus" to "suspendedUntil",
                    "blockState" to "suspendedUntil",
                    "updatedAt" to Instant.now(),
                ),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(event, second.jpeg) }
        } catch (error: Throwable) {
            val reported = AssertionError("Content cover device phase=$phase", error)
            failure = reported
            throw reported
        } finally {
            scope.cancel()
            auth.signOut()
            fixture.cleanup(failure)
        }
    }

    private suspend fun expect(reason: ContentCoverFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $reason at $phase")
        } catch (error: Exception) {
            assertEquals(
                "$phase (${error.javaClass.simpleName})",
                reason,
                contentCoverFailure(error),
            )
        }
    }

    private suspend fun expectCallable(code: LocalCallableFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected actual callable $code at $phase")
        } catch (error: LocalCallableException) {
            assertEquals(phase, code, error.code)
        }
    }
}
