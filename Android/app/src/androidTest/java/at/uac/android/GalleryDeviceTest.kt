package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalStorage
import at.uac.android.feature.gallery.*
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GalleryDeviceTest {
    private val context
        get() = AccountDeletionFixtures.context

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = operation()
        }

    @Test
    fun actualStorageCreateMetadataCounterReadBackAndNoOverwriteRules() = runBlocking {
        fixture { fixture, user, session, source, journal ->
            val target = fixture.target()
            val prepared = fixture.prepared()
            val intent = GalleryUploadIntent(target, "Synthetic photo caption", prepared)
            val repository = GalleryRepository(source, journal, { session }, gate)
            val beforeProfile =
                LocalFirebase.firestore(context)
                    .document("users/${user.uid}")
                    .get(Source.SERVER)
                    .await()
                    .data
            val created = repository.upload(intent)
            assertEquals(1, created.snapshot.counter)
            assertEquals(1, created.snapshot.photos.size)
            val saved = created.snapshot.photos.single()
            assertEquals(user.uid, saved.uploadedBy)
            assertEquals(intent.caption, saved.caption)
            assertTrue(
                saved.imageUrl.startsWith(
                    "https://firebasestorage.googleapis.com/v0/b/demo-uac-android.appspot.com/"
                )
            )
            assertEquals(prepared.hash, source.blob(target, session)?.hash)
            assertEquals(
                "keep-this-synthetic-value",
                created.snapshot.organization.fields["sentinel"],
            )
            val storage = LocalStorage.instance(context)
            val ref = storage.reference.child(target.path)
            val originalBlob = source.blob(target, session)!!
            val originalMetadata = ref.metadata.await()
            val different = fixture.prepared(Color.rgb(215, 25, 50))
            assertNotEquals(prepared.hash, different.hash)
            for (replacement in listOf(prepared, different)) {
                try {
                    ref.putBytes(
                            replacement.bytes(),
                            StorageMetadata.Builder().setContentType("image/jpeg").build(),
                        )
                        .await()
                    fail(
                        "Existing Gallery binary object must remain immutable, even under Storage CREATE"
                    )
                } catch (error: StorageException) {
                    assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
                }
            }
            try {
                ref.updateMetadata(
                        StorageMetadata.Builder()
                            .setCustomMetadata("unapproved", "metadata-write")
                            .build()
                    )
                    .await()
                fail("Gallery Storage metadata UPDATE must remain forbidden")
            } catch (error: StorageException) {
                assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
            }
            val invalidTarget = fixture.target()
            try {
                storage.reference
                    .child(invalidTarget.path)
                    .putBytes(
                        prepared.bytes(),
                        StorageMetadata.Builder().setContentType("image/png").build(),
                    )
                    .await()
                fail("Only the actual JPEG MIME is accepted")
            } catch (error: StorageException) {
                assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
            }
            try {
                LocalFirebase.firestore(context)
                    .document(target.document)
                    .update("caption", "Direct edit is forbidden")
                    .await()
                fail("Gallery metadata has no direct client update permission")
            } catch (error: FirebaseFirestoreException) {
                assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
            }
            val unchangedBlob = source.blob(target, session)!!
            assertEquals(originalBlob.hash, unchangedBlob.hash)
            assertEquals(originalBlob.token, unchangedBlob.token)
            assertArrayEquals(prepared.bytes(), unchangedBlob.bytes())
            val unchangedMetadata = ref.metadata.await()
            assertEquals(originalMetadata.generation, unchangedMetadata.generation)
            assertEquals(originalMetadata.metadataGeneration, unchangedMetadata.metadataGeneration)
            assertNull(unchangedMetadata.getCustomMetadata("unapproved"))
            assertEquals(saved, source.photo(target, session))
            assertEquals(1, source.snapshot(target.organizationId, session).counter)
            val deleted = repository.remove(saved)
            assertEquals(0, deleted.snapshot.counter)
            assertTrue(deleted.snapshot.photos.isEmpty())
            assertNull(deleted.pending)
            assertNull(source.photo(target, session))
            assertNull(source.blob(target, session))
            assertTrue(journal.pending(user.uid).isEmpty())
            assertEquals(
                beforeProfile,
                LocalFirebase.firestore(context)
                    .document("users/${user.uid}")
                    .get(Source.SERVER)
                    .await()
                    .data,
            )
        }
    }

    @Test
    fun lostCreateReceiptAndFailedFileCleanupAreReconciledWithoutReplayOrRollback() = runBlocking {
        fixture { fixture, user, session, source, journal ->
            val target = fixture.target()
            val intent =
                GalleryUploadIntent(target, "Synthetic unknown receipt", fixture.prepared())
            var creates = 0
            var cleanups = 0
            var failCleanup = false
            val interrupted =
                object : GallerySource by source {
                    override suspend fun create(
                        intent: GalleryUploadIntent,
                        imageUrl: String,
                        session: OrganizationSession,
                    ): GalleryReceipt {
                        creates++
                        source.create(intent, imageUrl, session)
                        // Simulate only a lost receipt AFTER the real handler committed. Actual
                        // metadata/blob remain real SDK state.
                        throw GalleryException(GalleryFailure.UNCONFIRMED)
                    }

                    override suspend fun removeBlob(
                        target: GalleryTarget,
                        session: OrganizationSession,
                    ) {
                        cleanups++
                        if (failCleanup) throw GalleryException(GalleryFailure.OFFLINE)
                        source.removeBlob(target, session)
                    }
                }
            val repository = GalleryRepository(interrupted, journal, { session }, gate)
            try {
                repository.upload(intent)
                fail("Lost receipt cannot be reported as success")
            } catch (error: GalleryException) {
                assertEquals(GalleryFailure.UNCONFIRMED, error.failure)
            }
            assertEquals(1, creates)
            assertEquals(0, cleanups)
            assertNotNull(source.photo(target, session))
            assertEquals(intent.photo.hash, source.blob(target, session)?.hash)
            val pending = journal.pending(user.uid).single()
            assertEquals(GalleryPhase.CREATE_SUBMITTED, pending.phase)
            assertEquals(GalleryRecovery.PUBLISHED, repository.reconcile(pending).status)
            assertEquals(1, creates)
            assertEquals(0, cleanups)
            assertTrue(journal.pending(user.uid).isEmpty())
            failCleanup = true
            val deleted = repository.remove(source.photo(target, session)!!)
            assertNotNull(deleted.pending)
            assertEquals(0, deleted.snapshot.counter)
            assertNull(source.photo(target, session))
            assertNotNull(source.blob(target, session))
            val recovery = repository.reconcile(journal.pending(user.uid).single())
            assertEquals(GalleryRecovery.CLEANUP_AVAILABLE, recovery.status)
            assertEquals(1, creates)
            assertEquals(1, cleanups)
            failCleanup = false
            repository.cleanup(recovery.pending!!)
            assertNull(source.blob(target, session))
            assertEquals(2, cleanups)
            assertEquals(1, creates)
            assertTrue(journal.pending(user.uid).isEmpty())
        }
    }

    private suspend fun fixture(
        action:
            suspend (
                Fixture,
                AccountDeletionFixtures.User,
                OrganizationSession,
                GallerySource,
                GalleryJournal,
            ) -> Unit
    ) {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Real Gallery SDK proof requires the guarded local callable runtime",
            AccountDeletionFixtures.online(),
        )
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-gallery")
        val session = OrganizationSession(user.uid, 1, true, "Synthetic gallery user", "user")
        val source = localGallerySource(context) { session }
        val journal = LocalGalleryJournal.get(context)
        val fixture = Fixture(user)
        var primary: Throwable? = null
        try {
            fixture.seed()
            action(fixture, user, session, source, journal)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            var cleanup = primary
            var resourcesRemoved = false
            try {
                fixture.cleanup()
                resourcesRemoved = true
            } catch (error: Throwable) {
                if (cleanup == null) cleanup = error else cleanup.addSuppressed(error)
            }
            if (resourcesRemoved) {
                var journalCleared = false
                try {
                    for (entry in journal.pending(user.uid)) {
                        check(entry.target.organizationId == fixture.organizationId)
                        journal.clear(user.uid, entry)
                    }
                    journalCleared = true
                } catch (error: Throwable) {
                    if (cleanup == null) cleanup = error else cleanup.addSuppressed(error)
                }
                if (journalCleared)
                    try {
                        AccountDeletionFixtures.clean(user)
                    } catch (error: Throwable) {
                        if (cleanup == null) cleanup = error else cleanup.addSuppressed(error)
                    }
            } else println("GALLERY_TEST_CLEANUP_PENDING accountRetained=true journalRetained=true")
            if (primary == null && cleanup != null) throw cleanup
        }
    }

    internal class Fixture(
        private val user: AccountDeletionFixtures.User,
        val organizationId: String = "gallery-${UUID.randomUUID()}",
    ) {
        private val targets = linkedSetOf<GalleryTarget>()

        fun target(): GalleryTarget =
            GalleryTarget(organizationId, UUID.randomUUID().toString()).also { targets += it }

        fun remember(target: GalleryTarget) {
            require(target.organizationId == organizationId)
            targets += target
        }

        fun prepared(color: Int = Color.rgb(10, 75, 210)): PreparedGalleryPhoto {
            val bitmap =
                Bitmap.createBitmap(80, 48, Bitmap.Config.ARGB_8888).apply { eraseColor(color) }
            try {
                return PreparedGalleryPhoto(
                    ByteArrayOutputStream()
                        .also { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it)) }
                        .toByteArray(),
                    80,
                    48,
                )
            } finally {
                bitmap.recycle()
            }
        }

        suspend fun seed() {
            require(organizationId.matches(Regex("gallery-[a-z0-9-]{1,80}")))
            patch(
                "organizations/$organizationId",
                mapOf(
                    "id" to organizationId,
                    "name" to "Synthetic gallery organization",
                    "city" to "Wien",
                    "shortDescription" to "Synthetic public gallery description",
                    "ownerId" to user.uid,
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to emptyList<String>(),
                    "moderationStatus" to "pendingReview",
                    "photoCount" to 0,
                    "createdAt" to Instant.parse("2026-09-03T10:00:00Z"),
                    "updatedAt" to Instant.parse("2026-09-03T10:00:00Z"),
                    "sentinel" to "keep-this-synthetic-value",
                ),
            )
        }

        private suspend fun patch(path: String, fields: Map<String, Any?>) =
            withContext(Dispatchers.IO) {
                AccountDeletionFixtures.requireLocalAvd()
                require(path == "organizations/$organizationId")
                val connection =
                    URL(
                            "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}"
                        )
                        .openConnection() as HttpURLConnection
                fun field(value: Any?): JSONObject =
                    when (value) {
                        null -> JSONObject().put("nullValue", JSONObject.NULL)
                        is String -> JSONObject().put("stringValue", value)
                        is Int -> JSONObject().put("integerValue", value.toString())
                        is Boolean -> JSONObject().put("booleanValue", value)
                        is Instant -> JSONObject().put("timestampValue", value.toString())
                        is List<*> ->
                            JSONObject()
                                .put(
                                    "arrayValue",
                                    JSONObject().put("values", JSONArray(value.map(::field))),
                                )
                        else -> error("Unsupported Gallery fixture type")
                    }
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
                                .put("fields", JSONObject(fields.mapValues { field(it.value) }))
                                .toString()
                                .toByteArray()
                        )
                    }
                    check(connection.responseCode in 200..299) {
                        "Gallery fixture setup HTTP ${connection.responseCode}"
                    }
                    connection.inputStream.use { it.readBytes() }
                } finally {
                    connection.disconnect()
                }
            }

        suspend fun cleanup() {
            AccountDeletionFixtures.requireLocalAvd()
            check(LocalFirebase.auth(AccountDeletionFixtures.context).currentUser?.uid == user.uid)
            var failure: Throwable? = null
            suspend fun step(action: suspend () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    val previous = failure
                    if (previous == null) failure = error else previous.addSuppressed(error)
                }
            }
            for (target in targets) {
                var objectRemoved = false
                step {
                    val ref =
                        LocalStorage.instance(AccountDeletionFixtures.context)
                            .reference
                            .child(target.path)
                    try {
                        ref.delete().await()
                    } catch (error: StorageException) {
                        if (error.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) throw error
                    }
                    try {
                        ref.metadata.await()
                        fail("Scoped test object cleanup must be read back")
                    } catch (error: StorageException) {
                        assertEquals(StorageException.ERROR_OBJECT_NOT_FOUND, error.errorCode)
                    }
                    objectRemoved = true
                }
                if (objectRemoved) step { removeConfirmed(target.document) }
            }
            // Keep parent permissions and the current synthetic identity when an object is not
            // confirmed absent.
            if (failure == null) step { removeConfirmed("organizations/$organizationId") }
            failure?.let { throw it }
        }

        private suspend fun removeConfirmed(path: String) {
            try {
                AccountDeletionFixtures.remove(path)
            } catch (error: Exception) {
                // A failed local response is not retried. Absence must be proved by a separate
                // read.
                if (AccountDeletionFixtures.document(path) != null) throw error
                println(
                    "GALLERY_TEST_CLEANUP_RESPONSE_RECONCILED collection=${path.substringBefore('/')}"
                )
            }
            assertNull(AccountDeletionFixtures.document(path))
        }
    }
}
