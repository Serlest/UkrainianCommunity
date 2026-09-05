package at.uac.android

import at.uac.android.feature.auth.*
import at.uac.android.feature.personal.*
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PersonalProfileEditorTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val alice = PersonalSession("editor-alice", true, true, 1)
    private val bob = PersonalSession("editor-bob", true, true, 2)
    private val base =
        ProfileDraft("Synthetic name", "Synthetic display", "Wien", "Private baseline", "", "wien")

    private fun profile(session: PersonalSession = alice, draft: ProfileDraft = base) =
        PersonalProfile(session.uid, "synthetic@example.invalid", draft, Instant.EPOCH)

    @Test
    fun initialMemoryEditorNeedsExactServerProfileBeforeEditOrSave() {
        val model = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        model.change(alice, base)
        assertNull(model.attemptSave(alice))
        assertEquals(ProfileDraft(), model.state.value.draft)
        model.accept(alice, profile(), false)
        assertEquals(base, model.state.value.draft)
        model.change(alice, base.copy(bio = "Local private draft"))
        assertTrue(model.state.value.dirty)
        assertEquals("Local private draft", model.attemptSave(alice)?.bio)
    }

    @Test
    fun sameUidRefreshPreservesDraftButNotOldRevisionEditAuthority() {
        var session: PersonalSession? = alice
        val model = PersonalProfileEditorViewModel({ alice.uid }, { session })
        model.accept(alice, profile(), false)
        model.change(alice, base.copy(displayName = "Unsaved local", bio = "Unsaved biography"))
        session = null
        model.bindAccount(alice.uid)
        assertNull(model.state.value.confirmedSession)
        assertNull(model.attemptSave(alice))
        model.change(alice, base.copy(displayName = "Stale callback"))
        assertEquals("Unsaved local", model.state.value.draft.displayName)
        val fresh = alice.copy(revision = 7)
        session = fresh
        model.bindAccount(alice.uid)
        model.change(fresh, base)
        assertEquals("Unsaved local", model.state.value.draft.displayName)
        model.accept(fresh, profile(fresh, base.copy(city = "Graz")), false)
        assertEquals("Unsaved local", model.state.value.draft.displayName)
        assertEquals("Unsaved biography", model.state.value.draft.bio)
        assertEquals("Graz", model.state.value.draft.city)
        assertEquals(fresh, model.state.value.confirmedSession)
    }

    @Test
    fun latestThreeWayMergePreservesConflictsAndAdoptsUntouchedFieldsRepeatedly() {
        val model = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        model.accept(alice, profile(), false)
        model.change(alice, base.copy(bio = "Local conflict"))
        val first = base.copy(bio = "Remote conflict", city = "Graz")
        model.accept(alice, profile(draft = first), false)
        assertEquals("Local conflict", model.state.value.draft.bio)
        assertEquals("Graz", model.state.value.draft.city)
        model.accept(alice, profile(draft = first.copy(city = "Linz")), false)
        assertEquals("Local conflict", model.state.value.draft.bio)
        assertEquals("Linz", model.state.value.draft.city)
    }

    @Test
    fun invalidAttemptAndDirtyTextSurviveRecompositionBindingNotAConfirmedSave() {
        val model = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        model.accept(alice, profile(), false)
        model.change(alice, base.copy(displayName = ""))
        assertNull(model.attemptSave(alice))
        assertTrue(model.state.value.attempted)
        model.bindAccount(alice.uid)
        model.accept(alice, profile(), false)
        assertEquals("", model.state.value.draft.displayName)
        assertTrue(model.state.value.attempted)
        assertTrue(model.state.value.dirty)
    }

    @Test
    fun confirmedNormalizedSaveClearsDirtyWithoutStaleReceiptErasingNewEdit() {
        val model = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        model.accept(alice, profile(), false)
        val dirty = base.copy(displayName = "  Local name  ")
        model.change(alice, dirty)
        model.accept(alice, profile(draft = dirty.normalized()), true)
        assertEquals("Local name", model.state.value.draft.displayName)
        assertFalse(model.state.value.dirty)
        model.change(alice, model.state.value.draft.copy(displayName = "Later edit"))
        model.accept(alice, profile(draft = dirty.normalized()), true)
        assertEquals("Later edit", model.state.value.draft.displayName)
        assertTrue(model.state.value.dirty)
    }

    @Test
    fun newUidAndSignOutImmediatelyClearDraftAndIgnoreOldServerResult() {
        var uid: String? = alice.uid
        var session: PersonalSession? = alice
        val model = PersonalProfileEditorViewModel({ uid }, { session })
        model.accept(alice, profile(), false)
        model.change(alice, base.copy(bio = "Sensitive synthetic"))
        uid = bob.uid
        session = bob
        assertEquals(PersonalProfileEditorState(), model.state.value.forSession(bob))
        model.bindAccount(uid)
        assertEquals(PersonalProfileEditorState(uid = bob.uid), model.state.value)
        model.accept(alice, profile(), false)
        assertNull(model.state.value.baseline)
        model.accept(bob, profile(bob), false)
        uid = null
        session = null
        model.bindAccount(null)
        assertEquals(PersonalProfileEditorState(), model.state.value)
    }

    @Test
    fun notReadyCannotConfirmEditOrSaveEvenWhenUidMatches() {
        val unready = alice.copy(active = false)
        val model = PersonalProfileEditorViewModel({ alice.uid }, { unready })
        model.accept(unready, profile(), false)
        assertNull(model.state.value.baseline)
        model.change(unready, base)
        assertNull(model.attemptSave(unready))
        model.accept(alice, profile(), false)
        assertNull(model.state.value.baseline)
    }

    @Test
    fun pureStateMaskHidesForeignUidButRetainsReadOnlySameUidDraft() {
        val state =
            PersonalProfileEditorState(
                alice.uid,
                alice,
                base,
                base.copy(bio = "Synthetic private"),
                true,
            )
        assertEquals(PersonalProfileEditorState(), state.forSession(null))
        assertEquals(PersonalProfileEditorState(), state.forSession(bob))
        val next = state.forSession(alice.copy(revision = 4))
        assertEquals(state.draft, next.draft)
        assertNull(next.confirmedSession)
        assertFalse(state.toString().contains("Synthetic private"))
        assertFalse(state.toString().contains(alice.uid))
    }

    @Test
    fun authIdentityRetentionIsLimitedToForegroundRefreshNotSignOutOrLogin() {
        val identity = AuthIdentity(alice.uid, "synthetic@example.invalid", true)
        for (stage in
            listOf(
                AuthStage.AUTHENTICATED,
                AuthStage.RESTORING,
                AuthStage.SESSION_UNAVAILABLE,
                AuthStage.VERIFICATION_PENDING,
            )) {
            assertEquals(
                alice.uid,
                AuthSession(stage, identity, revision = 1).profileEditorIdentity(),
            )
        }
        for (stage in
            listOf(AuthStage.GUEST, AuthStage.AUTHENTICATING, AuthStage.MFA_CHALLENGE)) assertNull(
            AuthSession(stage, identity, revision = 1).profileEditorIdentity()
        )
        assertNull(
            AuthSession(AuthStage.RESTORING, identity.copy(anonymous = true))
                .profileEditorIdentity()
        )
    }

    @Test
    fun coldNewViewModelNeverRestoresPrivateDraftFromAnyPersistence() {
        val first = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        first.accept(alice, profile(), false)
        first.change(alice, base.copy(bio = "Private memory only"))
        val cold = PersonalProfileEditorViewModel({ alice.uid }, { alice })
        assertEquals(ProfileDraft(), cold.state.value.draft)
        assertNull(cold.state.value.baseline)
        assertNull(cold.state.value.confirmedSession)
    }

    @Test
    fun observerMasksSameUidRevisionBeforeCompositionAndRejectsLateIdentityEvent() = runTest {
        var uid: String? = alice.uid
        var session: PersonalSession? = alice
        val stream = MutableStateFlow(uid)
        val model = PersonalProfileEditorViewModel({ uid }, { session })
        model.observeAccounts(stream)
        model.accept(alice, profile(), false)
        session = null
        model.bindAccount(uid)
        assertNull(model.state.value.confirmedSession)
        uid = bob.uid
        session = bob
        stream.value = uid
        runCurrent()
        model.bindAccount(alice.uid)
        assertEquals(bob.uid, model.state.value.uid)
        assertNull(model.state.value.baseline)
    }
}
