package at.uac.android

import at.uac.android.feature.browse.*
import at.uac.android.feature.community.*
import at.uac.android.feature.personal.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HistoryHooksTest {
    private val personal = PersonalSession("synthetic-hooks", true, true, 1)
    private val community = CommunitySession(personal.uid, 1, true, "user")
    private val time = Instant.EPOCH

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private inner class PersonalFake : PersonalSource {
        var stored: RawDocument? = null
        var legacy = false
        var readBackFails = false

        override suspend fun marker(marker: PersonalMarker) = if (readBackFails) null else stored

        override suspend fun setMarker(
            marker: PersonalMarker,
            enabled: Boolean,
            stillCurrent: () -> Boolean,
        ) {
            stored =
                if (enabled) RawDocument(marker.id, marker.identityFields() + ("createdAt" to time))
                else null
        }

        override suspend fun setMarkerConfirmed(
            marker: PersonalMarker,
            enabled: Boolean,
            stillCurrent: () -> Boolean,
        ): Boolean? {
            val changed = (stored != null) != enabled
            setMarker(marker, enabled, stillCurrent)
            return if (legacy) null else changed
        }

        override suspend fun profile(uid: String): PersonalProfile = error("Unused")

        override suspend fun saveProfile(
            uid: String,
            draft: ProfileDraft,
            stillCurrent: () -> Boolean,
        ): PersonalProfile = error("Unused")

        override suspend fun bookmarkPage(
            uid: String,
            kind: ContentKind,
            after: String?,
            size: Int,
        ) = MarkerPage(emptyList(), null, false)

        override suspend fun relationPage(uid: String, after: String?, size: Int) =
            MarkerPage(emptyList(), null, false)

        override suspend fun approvedContent(kind: ContentKind, ids: List<String>) =
            emptyList<RawDocument>()
    }

    @Test
    fun personalCallbackRunsAfterGateAndReadbackOnlyForActualChanges() = runTest {
        var inside = false
        var callbacks = 0
        val fake = PersonalFake()
        val gate =
            object : PersonalMutationGate {
                override suspend fun <T> withSession(
                    session: PersonalSession,
                    operation: suspend () -> T,
                ): T {
                    inside = true
                    return try {
                        operation()
                    } finally {
                        inside = false
                    }
                }
            }
        val model =
            PersonalViewModel(
                fake,
                sessionAuthority = { personal },
                mutationGate = gate,
                onConfirmedChange = {
                    assertFalse(inside)
                    assertTrue(it.didChange == true)
                    callbacks++
                    error("Secondary history unavailable")
                },
            )
        model.bind(personal)
        val target = PersonalTarget(ContentKind.NEWS, "synthetic-hook-news")
        model.set(target, PersonalAction.BOOKMARK, true)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        assertTrue(model.state.value.actions[target]!!.bookmarked)
        assertTrue(model.state.value.actionErrors.isEmpty())
        model.set(target, PersonalAction.BOOKMARK, true)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        fake.legacy = true
        model.set(target, PersonalAction.BOOKMARK, false)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        fake.legacy = false
        fake.readBackFails = true
        model.set(target, PersonalAction.BOOKMARK, true)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        assertNotNull(model.state.value.actionErrors[target])
    }

    private inner class CommunityFake : CommunitySource {
        var registered = false
        var readBackFails = false

        override suspend fun parent(target: CommunityTarget) =
            RawDocument(
                target.id,
                mapOf(
                    "startDate" to time.plusSeconds(3600),
                    "moderationStatus" to "approved",
                    "requiresRegistration" to true,
                    "registeredCount" to if (registered) 1L else 0L,
                ),
            )

        override suspend fun registration(eventId: String, uid: String): RawDocument? =
            if (registered && !readBackFails) {
                val id = CommunityContract.registrationId(eventId, uid)
                RawDocument(
                    id,
                    mapOf(
                        "id" to id,
                        "eventId" to eventId,
                        "userId" to uid,
                        "registeredAt" to time,
                    ),
                )
            } else null

        override suspend fun call(name: String, data: Fields, uid: String): Any {
            val next = name == "registerForEvent"
            val changed = next != registered
            registered = next
            return mapOf(
                "eventId" to data["eventId"],
                "registrationState" to if (next) "registered" else "notRegistered",
                "registeredCount" to if (next) 1L else 0L,
                "didChange" to changed,
            )
        }

        override suspend fun comment(target: CommunityTarget, id: String): RawDocument? = null

        override fun comments(target: CommunityTarget) = emptyFlow<Result<CommentPage>>()

        override suspend fun moderation(target: CommunityTarget, session: CommunitySession) = false

        override suspend fun deleteComment(
            target: CommunityTarget,
            id: String,
            uid: String,
            stillCurrent: () -> Boolean,
        ) = Unit
    }

    @Test
    fun communityKeepsDidChangeAndSecondaryFailureNeverUndoesPrimarySuccess() = runTest {
        var inside = false
        var callbacks = 0
        val fake = CommunityFake()
        val gate =
            object : CommunityMutationGate {
                override suspend fun <T> withSession(
                    session: CommunitySession,
                    operation: suspend () -> T,
                ): T {
                    inside = true
                    return try {
                        operation()
                    } finally {
                        inside = false
                    }
                }
            }
        val model =
            CommunityViewModel(fake, { community }, gate) {
                assertFalse(inside)
                callbacks++
                assertTrue(it.didChange)
                error("Secondary history unavailable")
            }
        model.show(CommunityTarget(ContentKind.EVENTS, "synthetic-hook-event"))
        advanceUntilIdle()
        model.setRegistration(true)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        assertTrue(model.state.value.participation!!.registered)
        assertNull(model.state.value.registrationError)
        model.setRegistration(true)
        advanceUntilIdle()
        assertEquals(1, callbacks)
        model.setRegistration(false)
        advanceUntilIdle()
        assertEquals(2, callbacks)
        fake.readBackFails = true
        model.setRegistration(true)
        advanceUntilIdle()
        assertEquals(2, callbacks)
        assertEquals(CommunityFailure.UNCONFIRMED, model.state.value.registrationError)
    }
}
