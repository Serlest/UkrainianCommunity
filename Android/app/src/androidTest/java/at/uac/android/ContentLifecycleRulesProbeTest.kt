package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Required DENIED regression after the original snapshot839 ALLOWED audit and approved local Rules
 * fix.
 */
@RunWith(AndroidJUnit4::class)
class ContentLifecycleRulesProbeTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun teamCancellationFieldMutationIsDeniedAndExactSyntheticFixtureRemainsUnchanged() =
        runBlocking {
            assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
            val fixture = ContentLifecycleFixtures("author4clifeprobe-${UUID.randomUUID()}")
            val auth = LocalFirebase.auth(context)
            val db = LocalFirebase.firestore(context)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
            val source = localAuthoringSource(context)
            val repository =
                AuthoringRepository(
                    source,
                    { store.state.value.organizationScope() },
                    AuthOrganizationMutationGate(store),
                )
            var original: AuthoringItem? = null
            var failure: Throwable? = null
            var phase = "setup"
            suspend fun signIn(account: ContentCoverFixtures.Account) {
                withContext(Dispatchers.Main) { store.signOut() }.join()
                withContext(Dispatchers.Main) { store.signIn(account.email, fixture.password)!! }
                    .join()
                assertTrue(store.state.value.readyForActions)
            }
            try {
                AuthEmulatorFixtures.seedLegalReference()
                val owner = fixture.media.account("owner")
                val admin = fixture.media.account("admin")
                fixture.media.organization(owner, listOf(admin))
                signIn(owner)
                val actor = requireNotNull(store.state.value.organizationScope())
                val target = fixture.register(ContentKind.EVENTS)
                val org = requireNotNull(source.organization(target.organizationId, actor))
                val draft =
                    AuthoringContract.newDraft(ContentKind.EVENTS, org)
                        .copy(
                            id = target.contentId,
                            title = "Synthetic Rules cancellation probe",
                            summary = "Local audit only",
                            body = "Restored immediately after one scoped direct field probe.",
                        )
                original =
                    repository.submit(
                        AuthoringContract.submission(
                            draft.copy(event = draft.event.copy(venue = "Synthetic hall")),
                            org,
                            actor,
                            null,
                        )
                    )
                signIn(admin)
                assertEquals(
                    OrganizationAuthority.ADMIN,
                    source
                        .organization(
                            target.organizationId,
                            requireNotNull(store.state.value.organizationScope()),
                        )
                        ?.authority,
                )
                phase =
                    "one direct cancellationState field update with unchanged approved moderation"
                val reference = db.document("events/${target.contentId}")
                val allowed =
                    try {
                        reference
                            .update(
                                mapOf(
                                    "cancellationState" to "cancelled",
                                    "updatedAt" to FieldValue.serverTimestamp(),
                                )
                            )
                            .await()
                        true
                    } catch (error: FirebaseFirestoreException) {
                        if (error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED)
                            throw error
                        false
                    }
                val actual = db.runTransaction { it.get(reference) }.await()
                if (allowed) {
                    assertEquals("cancelled", actual.getString("cancellationState"))
                    assertEquals("approved", actual.getString("moderationStatus"))
                    assertFalse(actual.contains("cancelledBy"))
                    assertFalse(actual.contains("cancelledAt"))
                    assertEquals(0L, actual.getLong("registeredCount"))
                    println(
                        "LOCAL_RULES_PROBE: team-admin cancellationState-only ALLOWED; moderation approved; no backend actor/timestamp. Product does not use this path."
                    )
                } else {
                    assertFalse(actual.contains("cancellationState"))
                    println(
                        "LOCAL_RULES_PROBE: team-admin cancellationState-only DENIED by installed Rules."
                    )
                }
                phase = "exact fixture restoration and read-back"
                fixture.data.seed("events/${target.contentId}", requireNotNull(original).fields)
                val restored = db.runTransaction { it.get(reference) }.await()
                assertFalse(restored.contains("cancellationState"))
                assertFalse(restored.contains("cancelledAt"))
                assertFalse(restored.contains("cancelledBy"))
                assertEquals("approved", restored.getString("moderationStatus"))
                assertEquals(original.fields["title"], restored.getString("title"))
                assertEquals(0L, restored.getLong("registeredCount"))
                println(
                    "LOCAL_RULES_PROBE: exact synthetic event restored; scoped cleanup follows."
                )
                assertFalse(
                    "Server-managed cancellationState must be denied to a direct organization-admin write",
                    allowed,
                )
            } catch (error: Throwable) {
                val reported = AssertionError("Lifecycle Rules audit phase=$phase", error)
                failure = reported
                throw reported
            } finally {
                try {
                    original?.let { fixture.data.seed("events/${it.id}", it.fields) }
                } catch (error: Throwable) {
                    if (failure == null) failure = error else failure.addSuppressed(error)
                }
                scope.cancel()
                auth.signOut()
                fixture.cleanup(failure)
                if (failure != null && failure !is AssertionError) throw failure
            }
        }
}
