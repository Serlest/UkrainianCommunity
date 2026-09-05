package at.uac.android.feature.personal

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Memory-only editor. It is deliberately NOT a SavedStateHandle, Bundle, preference or disk record.
 */
data class PersonalProfileEditorState(
    val uid: String? = null,
    val confirmedSession: PersonalSession? = null,
    val baseline: ProfileDraft? = null,
    val draft: ProfileDraft = ProfileDraft(),
    val attempted: Boolean = false,
) {
    val dirty: Boolean
        get() = baseline?.let { draft != it } == true

    fun forSession(session: PersonalSession?): PersonalProfileEditorState =
        if (session == null || session.uid != uid) PersonalProfileEditorState()
        else copy(confirmedSession = confirmedSession?.takeIf { it == session && session.ready })

    override fun toString() =
        "PersonalProfileEditorState([redacted], confirmed=${confirmedSession != null}, dirty=$dirty)"
}

class PersonalProfileEditorViewModel(
    private val accountAuthority: () -> String?,
    private val sessionAuthority: () -> PersonalSession?,
) : ViewModel() {
    private val mutable = MutableStateFlow(PersonalProfileEditorState(uid = accountAuthority()))
    val state = mutable.asStateFlow()
    private var observer: Job? = null

    fun observeAccounts(values: Flow<String?>) {
        observer?.cancel()
        observer =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                values.collect(::bindAccount)
            }
    }

    /**
     * Same-UID RESTORING preserves local draft, but exact fresh-session proof is invalidated
     * immediately.
     */
    fun bindAccount(uid: String?) {
        val current = accountAuthority()
        if (uid != current) return
        if (current == null || mutable.value.uid != current) {
            mutable.value = PersonalProfileEditorState(uid = current)
        } else if (mutable.value.confirmedSession != sessionAuthority()) {
            mutable.value = mutable.value.copy(confirmedSession = null)
        }
    }

    fun accept(session: PersonalSession?, profile: PersonalProfile?, saved: Boolean) {
        bindAccount(accountAuthority())
        if (
            session == null ||
                profile == null ||
                !session.ready ||
                session != sessionAuthority() ||
                session.uid != accountAuthority() ||
                profile.uid != session.uid
        )
            return
        val previous = mutable.value
        val draft =
            when {
                previous.baseline == null -> profile.draft
                saved && previous.draft.normalized() == profile.draft -> profile.draft
                else -> mergeProfileDraft(previous.baseline, previous.draft, profile.draft)
            }
        mutable.value =
            previous.copy(confirmedSession = session, baseline = profile.draft, draft = draft)
    }

    private fun current(session: PersonalSession?): Boolean =
        session != null &&
            session.ready &&
            session == sessionAuthority() &&
            session.uid == accountAuthority() &&
            mutable.value.uid == session.uid &&
            mutable.value.confirmedSession == session &&
            mutable.value.baseline != null

    fun change(session: PersonalSession?, draft: ProfileDraft) {
        if (current(session)) mutable.value = mutable.value.copy(draft = draft)
    }

    /**
     * Returns data only to the fresh session that currently owns the form. The caller still uses
     * its real Auth mutation gate.
     */
    fun attemptSave(session: PersonalSession?): ProfileDraft? {
        if (!current(session)) return null
        mutable.value = mutable.value.copy(attempted = true)
        return mutable.value.draft.takeIf { it.validFor(session?.uid) }
    }

    override fun onCleared() {
        mutable.value = PersonalProfileEditorState()
        super.onCleared()
    }
}

/**
 * Keep draft only across the same authenticated identity's foreground refresh, not explicit
 * login/logout transitions.
 */
fun AuthSession.profileEditorIdentity(): String? =
    identity
        ?.takeIf {
            !it.anonymous &&
                stage in
                    setOf(
                        AuthStage.AUTHENTICATED,
                        AuthStage.RESTORING,
                        AuthStage.VERIFICATION_PENDING,
                        AuthStage.SESSION_UNAVAILABLE,
                    )
        }
        ?.uid

fun localPersonalProfileEditor(auth: AuthStore): PersonalProfileEditorViewModel =
    PersonalProfileEditorViewModel(
            { auth.state.value.profileEditorIdentity() },
            { auth.state.value.personalScope() },
        )
        .also { editor -> editor.observeAccounts(auth.state.map { it.profileEditorIdentity() }) }
