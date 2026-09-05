package at.uac.android

import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.core.LocalImageException
import at.uac.android.core.LocalImageFailure
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.personal.PersonalMutationGate
import at.uac.android.feature.personal.PersonalProfile
import at.uac.android.feature.personal.PersonalSession
import at.uac.android.feature.personal.ProfileDraft
import at.uac.android.feature.personal.mergeProfileDraft
import at.uac.android.feature.profilemedia.*
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileMediaTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val alice = PersonalSession("avatar-alice", true, true, 1)
    private val bob = PersonalSession("avatar-bob", true, true, 2)
    private val photo = PreparedAvatar(byteArrayOf(-1, -40, -1, -39))
    private val draft = ProfileDraft("Demo Person", "Demo", "Wien", "Unsaved-safe", "", "wien")

    private fun url(uid: String) =
        "http://10.0.2.2:9198/v0/b/${LocalStorage.BUCKET}/o/profileImages%2F$uid%2Favatar.jpg?alt=media&token=synthetic"

    private fun profile(uid: String) =
        PersonalProfile(
            uid,
            "$uid@example.invalid",
            draft.copy(avatarUrl = url(uid)),
            Instant.EPOCH,
        )

    private inner class FakeSource : ProfileMediaSource {
        var uploads = 0
        var commits = 0
        var uploadFailure: ProfileMediaFailure? = null
        var commitFailure: ProfileMediaFailure? = null
        var beforeUpload: suspend () -> Unit = {}
        var afterUpload: suspend () -> Unit = {}
        var beforeCommit: suspend () -> Unit = {}
        var returnedUid: String? = null
        var foreignUrl = false

        override suspend fun upload(
            uid: String,
            photo: PreparedAvatar,
            operation: AvatarOperation,
            onProgress: (Float) -> Unit,
        ): String {
            uploads++
            beforeUpload()
            operation.check()
            uploadFailure?.let { throw ProfileMediaException(it) }
            onProgress(.5f)
            afterUpload()
            return url(if (foreignUrl) bob.uid else uid)
        }

        override suspend fun saveAvatar(
            uid: String,
            url: String,
            stillCurrent: () -> Boolean,
        ): PersonalProfile {
            if (!stillCurrent()) throw CancellationException()
            commits++
            beforeCommit()
            commitFailure?.let { throw ProfileMediaException(it) }
            return profile(returnedUid ?: uid)
        }
    }

    @Test
    fun canonicalPathAndOwnLocalUrlAreRequired() {
        assertEquals("profileImages/${alice.uid}/avatar.jpg", profileAvatarPath(alice.uid))
        assertFalse(draft.copy(avatarUrl = url(alice.uid)).valid())
        assertTrue(draft.copy(avatarUrl = url(alice.uid)).validFor(alice.uid))
        assertFalse(draft.copy(avatarUrl = url(bob.uid)).validFor(alice.uid))
        assertTrue(draft.copy(avatarUrl = "https://example.invalid/legacy.jpg").validFor(alice.uid))
        for (bad in
            listOf(
                url(alice.uid).replace("10.0.2.2", "localhost"),
                url(alice.uid).replace(":9198", ":9199"),
                url(alice.uid).replace(LocalStorage.BUCKET, "real.appspot.com"),
                url(alice.uid).replace("avatar.jpg", "other.jpg"),
                url(alice.uid).replace("http://", "http://user@"),
                url(alice.uid) + "#ignored",
            )) {
            assertFalse(bad, draft.copy(avatarUrl = bad).validFor(alice.uid))
        }
    }

    @Test
    fun serverRefreshMergesUntouchedFieldsWithoutErasingDirtyTextOrConfirmedAvatar() {
        val local =
            draft.copy(
                displayName = "Local draft",
                bio = "Unsaved biography",
                avatarUrl = url(alice.uid),
            )
        val server =
            draft.copy(
                displayName = "Concurrent server name",
                city = "Graz",
                federalState = "steiermark",
            )
        val merged = mergeProfileDraft(draft, local, server)
        assertEquals("Local draft", merged.displayName)
        assertEquals("Unsaved biography", merged.bio)
        assertEquals("Graz", merged.city)
        assertEquals("steiermark", merged.federalState)
        assertEquals(url(alice.uid), merged.avatarUrl)
        assertEquals(server, mergeProfileDraft(draft, draft, server))
    }

    @Test
    fun sourceDimensionsAndSamplingNeverDecodeAboveBound() {
        assertFalse(LocalImagePreparation.validDimensions(0, 1))
        assertFalse(LocalImagePreparation.validDimensions(Int.MAX_VALUE, Int.MAX_VALUE))
        assertFalse(LocalImagePreparation.validDimensions(32769, 1))
        assertFalse(LocalImagePreparation.validDimensions(10001, 10000))
        assertTrue(LocalImagePreparation.validDimensions(10000, 10000))
        assertEquals(4, LocalImagePreparation.sampleSize(8000, 6000, 2048))
        assertEquals(2, LocalImagePreparation.sampleSize(2049, 2048, 2048))
        assertEquals(
            512 to 512,
            LocalImagePreparation.outputSize(2048, 512, LocalImagePolicy.AVATAR),
        )
        assertEquals(
            1024 to 1024,
            LocalImagePreparation.outputSize(2048, 2048, LocalImagePolicy.AVATAR),
        )
        assertEquals(
            1600 to 800,
            LocalImagePreparation.outputSize(3200, 1600, LocalImagePolicy.ORG_LOGO),
        )
        assertEquals(
            100 to 200,
            LocalImagePreparation.outputSize(100, 200, LocalImagePolicy.ORG_LOGO),
        )
    }

    @Test
    fun processedJpegHasStrictSizeBoundaryAndMagic() {
        assertTrue(LocalImagePreparation.validJpeg(photo.jpeg, LocalImagePolicy.AVATAR))
        val tooBig =
            ByteArray(LocalImagePolicy.AVATAR.maximumBytes).apply {
                this[0] = -1
                this[1] = -40
                this[size - 2] = -1
                this[size - 1] = -39
            }
        assertFalse(LocalImagePreparation.validJpeg(tooBig, LocalImagePolicy.AVATAR))
        assertFalse(
            LocalImagePreparation.validJpeg(byteArrayOf(1, 2, 3, 4), LocalImagePolicy.AVATAR)
        )
    }

    @Test
    fun boundedReaderReturnsSmallContentAndRejectsOneByteTooMany() = runTest {
        assertArrayEquals(
            byteArrayOf(1, 2, 3),
            LocalImagePreparation.readBounded(ByteArrayInputStream(byteArrayOf(1, 2, 3))),
        )
        val endless =
            object : InputStream() {
                override fun read() = 1

                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    buffer.fill(1, offset, offset + length)
                    return length
                }
            }
        try {
            LocalImagePreparation.readBounded(endless)
            fail("Unbounded source")
        } catch (error: LocalImageException) {
            assertEquals(LocalImageFailure.TOO_LARGE, error.reason)
        }
    }

    @Test
    fun animatedAndMalformedContainersAreRejectedBeforeDecode() {
        fun rejection(bytes: ByteArray, reason: LocalImageFailure) {
            try {
                LocalImagePreparation.validateContainer(bytes)
                fail("Unsafe container")
            } catch (error: LocalImageException) {
                assertEquals(reason, error.reason)
            }
        }
        rejection("GIF89a".toByteArray(), LocalImageFailure.UNSUPPORTED)
        rejection("<svg/>".toByteArray(), LocalImageFailure.UNSUPPORTED)
        rejection(byteArrayOf(-1, -40, 0, 0), LocalImageFailure.INVALID)
        val pngHeader = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)
        rejection(
            pngHeader + byteArrayOf(0, 0, 0, 0) + "acTL".toByteArray() + ByteArray(4),
            LocalImageFailure.UNSUPPORTED,
        )
        rejection(
            pngHeader + byteArrayOf(127, -1, -1, -1) + "IDAT".toByteArray() + ByteArray(4),
            LocalImageFailure.INVALID,
        )
        val webp =
            "RIFF".toByteArray() +
                byteArrayOf(14, 0, 0, 0) +
                "WEBPVP8X".toByteArray() +
                byteArrayOf(1, 0, 0, 0, 2, 0)
        rejection(webp, LocalImageFailure.UNSUPPORTED)
    }

    @Test
    fun guestAndNotReadyNeverUpload() = runTest {
        val source = FakeSource()
        for ((session, reason) in
            listOf(
                null to ProfileMediaFailure.SIGN_IN,
                alice.copy(active = false) to ProfileMediaFailure.NOT_READY,
                alice.copy(emailVerified = false) to ProfileMediaFailure.NOT_READY,
            )) {
            try {
                ProfileMediaRepository(source, { session }).save(photo, AvatarOperation(), {}, {})
                fail("Unsafe session")
            } catch (error: ProfileMediaException) {
                assertEquals(reason, error.reason)
            }
        }
        assertEquals(0, source.uploads)
    }

    @Test
    fun uploadAndPrivatePublicConfirmationUseExactlyOneGate() = runTest {
        val source = FakeSource()
        var locks = 0
        var inside = false
        val gate =
            object : PersonalMutationGate {
                override suspend fun <T> withSession(
                    session: PersonalSession,
                    operation: suspend () -> T,
                ): T {
                    assertFalse(inside)
                    inside = true
                    locks++
                    try {
                        return operation()
                    } finally {
                        inside = false
                    }
                }
            }
        source.beforeUpload = { assertTrue(inside) }
        val phases = mutableListOf<ProfileMediaPhase>()
        assertEquals(
            alice.uid,
            ProfileMediaRepository(source, { alice }, gate)
                .save(photo, AvatarOperation(), phases::add, {})
                .uid,
        )
        assertEquals(listOf(ProfileMediaPhase.UPLOADING, ProfileMediaPhase.COMMITTING), phases)
        assertEquals(1, locks)
        assertFalse(inside)
        assertEquals(1, source.commits)
    }

    @Test
    fun failureAfterUploadIsNotReportedAsSuccessOrAutomaticallyRetried() = runTest {
        val source = FakeSource().apply { commitFailure = ProfileMediaFailure.UNCONFIRMED }
        try {
            ProfileMediaRepository(source, { alice }).save(photo, AvatarOperation(), {}, {})
            fail("Unconfirmed profile")
        } catch (error: ProfileMediaException) {
            assertEquals(ProfileMediaFailure.UNCONFIRMED, error.reason)
        }
        assertEquals(1, source.uploads)
        assertEquals(1, source.commits)
    }

    @Test
    fun readBackTimeoutIsNotMisreportedAsUserCancellation() = runTest {
        val source = FakeSource().apply { beforeCommit = { withTimeout(10) { delay(20) } } }
        val model = model(source)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        model.save()
        advanceUntilIdle()
        assertEquals(ProfileMediaFailure.OFFLINE, model.state.value.error)
        assertNull(model.state.value.confirmed)
        assertFalse(model.state.value.cancelRequested)
        assertSame(photo, model.state.value.selection)
    }

    @Test
    fun foreignStorageUrlAndForeignReceiptAreRejected() = runTest {
        val source = FakeSource().apply { foreignUrl = true }
        try {
            ProfileMediaRepository(source, { alice }).save(photo, AvatarOperation(), {}, {})
            fail("Foreign URL")
        } catch (error: ProfileMediaException) {
            assertEquals(ProfileMediaFailure.INVALID, error.reason)
        }
        assertEquals(0, source.commits)
        source.foreignUrl = false
        source.returnedUid = bob.uid
        try {
            ProfileMediaRepository(source, { alice }).save(photo, AvatarOperation(), {}, {})
            fail("Foreign receipt")
        } catch (error: ProfileMediaException) {
            assertEquals(ProfileMediaFailure.UNCONFIRMED, error.reason)
        }
    }

    @Test
    fun accountSwitchBetweenUploadAndCommitNeverCommits() = runTest {
        var current = alice
        val source = FakeSource().apply { afterUpload = { current = bob } }
        try {
            ProfileMediaRepository(source, { current }).save(photo, AvatarOperation(), {}, {})
            fail("Account switched")
        } catch (_: CancellationException) {}
        assertEquals(0, source.commits)
    }

    @Test
    fun cancellationBeforeOrAfterUploadStopsCommitWithoutDeletingCanonicalObject() = runTest {
        val source = FakeSource()
        val first = AvatarOperation().apply { cancel() }
        try {
            ProfileMediaRepository(source, { alice }).save(photo, first, {}, {})
            fail("Cancelled")
        } catch (error: ProfileMediaException) {
            assertEquals(ProfileMediaFailure.CANCELLED, error.reason)
        }
        assertEquals(0, source.uploads)
        val second = AvatarOperation()
        source.afterUpload = { second.cancel() }
        try {
            ProfileMediaRepository(source, { alice }).save(photo, second, {}, {})
            fail("Cancelled")
        } catch (error: ProfileMediaException) {
            assertEquals(ProfileMediaFailure.CANCELLED, error.reason)
        }
        assertEquals(1, source.uploads)
        assertEquals(0, source.commits)
    }

    @Test
    fun lateUploadCancelHandlerStillReceivesEarlierCancellation() {
        var called = 0
        val operation = AvatarOperation()
        operation.cancel()
        operation.attachCancel { called++ }
        assertEquals(1, called)
        operation.attachCancel(null)
        operation.cancel()
        assertEquals(1, called)
    }

    private fun model(
        source: FakeSource,
        authority: () -> PersonalSession? = { alice },
        prepare: ProfilePhotoPreparation = ProfilePhotoPreparation { photo },
    ) = ProfileMediaViewModel(source, prepare, authority).also { it.bind(authority()) }

    private class FakePicker : ExternalImagePickerAuthorization {
        var opened = 0
        var finished = 0
        var cancelled = 0
        var captured: Pair<String, Long>? = null

        override fun begin(uid: String, revision: Long): ExternalImagePickerLease {
            opened++
            captured = uid to revision
            return object : ExternalImagePickerLease {
                override fun finish() {
                    finished++
                }

                override fun cancel() {
                    cancelled++
                }
            }
        }
    }

    @Test
    fun pickerCannotOpenWithoutExplicitForegroundAuthorization() {
        val model = model(FakeSource())
        assertFalse(model.beginPicker())
        assertFalse(model.state.value.pickerOpen)
        assertEquals(ProfileMediaFailure.NOT_READY, model.state.value.error)
    }

    @Test
    fun pickerLeaseSurvivesSameScopeRebindAndFinishesOnlyOnce() = runTest {
        val picker = FakePicker()
        val model =
            ProfileMediaViewModel(
                FakeSource(),
                ProfilePhotoPreparation { photo },
                { alice },
                pickerAuthorization = picker,
            )
        model.bind(alice)
        assertTrue(model.beginPicker())
        assertFalse(model.beginPicker())
        assertTrue(model.state.value.busy)
        assertEquals(alice.uid to alice.revision, picker.captured)
        model.bind(
            alice
        ) // Recreated UI can bind the same authoritative identity without losing the pending
        // result.
        model.pickerResult("content://synthetic/photo")
        model.pickerResult("content://synthetic/duplicate")
        advanceUntilIdle()
        assertSame(photo, model.state.value.selection)
        assertEquals(1, picker.finished)
        assertEquals(0, picker.cancelled)
        assertFalse(model.state.value.busy)
    }

    @Test
    fun accountOrSameUidNewRevisionInvalidatesPendingPickerBeforeResult() = runTest {
        for (next in listOf(bob, alice.copy(revision = 2))) {
            var current = alice
            val picker = FakePicker()
            val model =
                ProfileMediaViewModel(
                    FakeSource(),
                    ProfilePhotoPreparation { photo },
                    { current },
                    pickerAuthorization = picker,
                )
            model.bind(current)
            assertTrue(model.beginPicker())
            current = next
            model.bind(current)
            model.pickerResult("content://synthetic/photo")
            advanceUntilIdle()
            assertNull(model.state.value.selection)
            assertEquals(1, picker.cancelled)
            assertEquals(0, picker.finished)
            assertFalse(model.state.value.pickerOpen)
        }
    }

    @Test
    fun failedPickerLaunchCancelsLeaseAndCanBeOpenedAgain() {
        val picker = FakePicker()
        val model =
            ProfileMediaViewModel(
                FakeSource(),
                ProfilePhotoPreparation { photo },
                { alice },
                pickerAuthorization = picker,
            )
        model.bind(alice)
        assertTrue(model.beginPicker())
        model.pickerUnavailable()
        assertEquals(1, picker.cancelled)
        assertFalse(model.state.value.busy)
        assertEquals(ProfileMediaFailure.UNREADABLE, model.state.value.error)
        assertTrue(model.beginPicker())
        model.cancel()
        assertEquals(2, picker.cancelled)
    }

    @Test
    fun emptyPickerResultFinishesLeaseWithoutDiscardingExistingSelection() = runTest {
        val picker = FakePicker()
        val model =
            ProfileMediaViewModel(
                FakeSource(),
                ProfilePhotoPreparation { photo },
                { alice },
                pickerAuthorization = picker,
            )
        model.bind(alice)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.pickerResult(null)
        assertSame(photo, model.state.value.selection)
        assertEquals(1, picker.finished)
        assertFalse(model.state.value.busy)
    }

    @Test
    fun pickerDismissalPreservesSelectionButOldAccountResultIsIgnored() = runTest {
        var current = alice
        val model = model(FakeSource(), { current })
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        assertSame(photo, model.state.value.selection)
        model.select(null, alice)
        assertSame(photo, model.state.value.selection)
        current = bob
        model.bind(bob)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        assertNull(model.state.value.selection)
    }

    @Test
    fun duplicatePendingAndConfirmedSaveDoNotUploadAgain() = runTest {
        val source = FakeSource().apply { beforeUpload = { delay(100) } }
        val model = model(source)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        model.save()
        model.save()
        runCurrent()
        assertEquals(1, source.uploads)
        advanceUntilIdle()
        model.save()
        advanceUntilIdle()
        assertEquals(1, source.uploads)
        assertNotNull(model.state.value.confirmed)
        assertFalse(model.state.value.confirmationDelivered)
        model.confirmationDelivered()
        assertTrue(model.state.value.confirmationDelivered)
        model.cancel()
        assertNull(model.state.value.confirmed)
        assertNull(model.state.value.selection)
    }

    @Test
    fun explicitRetryReusesPreparedPhotoAfterUnconfirmedFailure() = runTest {
        val source = FakeSource().apply { commitFailure = ProfileMediaFailure.UNCONFIRMED }
        val model = model(source)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        model.save()
        advanceUntilIdle()
        assertSame(photo, model.state.value.selection)
        assertEquals(ProfileMediaFailure.UNCONFIRMED, model.state.value.error)
        source.commitFailure = null
        model.save()
        advanceUntilIdle()
        assertNotNull(model.state.value.confirmed)
        assertNull(model.state.value.error)
        assertEquals(2, source.uploads)
    }

    @Test
    fun immediateAccountMaskAndClearProtectLatePreparation() = runTest {
        var current = alice
        val model =
            model(
                FakeSource(),
                { current },
                ProfilePhotoPreparation {
                    delay(100)
                    photo
                },
            )
        model.select("content://synthetic/photo", alice)
        runCurrent()
        current = bob
        assertNull(model.state.value.forSession(bob).selection)
        model.bind(bob)
        advanceUntilIdle()
        assertEquals(bob, model.state.value.session)
        assertNull(model.state.value.selection)
        assertFalse(model.state.value.busy)
    }

    @Test
    fun immediateAccountClearAlsoProtectsNonCancellableLateUpload() = runTest {
        var current = alice
        val deferred = CompletableDeferred<Unit>()
        val source = FakeSource().apply { beforeUpload = { deferred.await() } }
        val model = model(source, { current })
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        model.save()
        runCurrent()
        current = bob
        model.bind(bob)
        assertNull(model.state.value.selection)
        assertNull(model.state.value.confirmed)
        deferred.complete(Unit)
        advanceUntilIdle()
        assertEquals(0, source.commits)
        assertEquals(bob, model.state.value.session)
        assertNull(model.state.value.error)
    }

    @Test
    fun cancellingPreparationDiscardsPrivateSelection() = runTest {
        val model =
            model(
                FakeSource(),
                prepare =
                    ProfilePhotoPreparation {
                        delay(100)
                        photo
                    },
            )
        model.select("content://synthetic/photo", alice)
        runCurrent()
        model.cancel()
        advanceUntilIdle()
        assertFalse(model.state.value.busy)
        assertNull(model.state.value.selection)
    }

    @Test
    fun cancellingUploadWaitsForSettledTaskBeforeIdle() = runTest {
        val deferred = CompletableDeferred<Unit>()
        val source = FakeSource().apply { beforeUpload = { deferred.await() } }
        val model = model(source)
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        model.save()
        runCurrent()
        model.cancel()
        assertTrue(model.state.value.busy)
        assertTrue(model.state.value.cancelRequested)
        deferred.complete(Unit)
        advanceUntilIdle()
        assertFalse(model.state.value.busy)
        assertFalse(model.state.value.cancelRequested)
        assertEquals(ProfileMediaFailure.CANCELLED, model.state.value.error)
        assertEquals(0, source.commits)
    }

    @Test
    fun unsupportedPreparationGivesActionableErrorWithoutUpload() = runTest {
        val source = FakeSource()
        val model =
            model(
                source,
                prepare =
                    ProfilePhotoPreparation {
                        throw LocalImageException(LocalImageFailure.UNSUPPORTED)
                    },
            )
        model.select("content://synthetic/photo", alice)
        advanceUntilIdle()
        assertEquals(ProfileMediaFailure.UNSUPPORTED, model.state.value.error)
        assertFalse(model.state.value.busy)
        assertEquals(0, source.uploads)
    }
}
