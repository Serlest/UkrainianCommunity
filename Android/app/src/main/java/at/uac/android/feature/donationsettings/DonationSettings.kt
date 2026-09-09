package at.uac.android.feature.donationsettings

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.backend.AppBackend
import at.uac.android.feature.browse.Donation
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

val donationTextKeys =
    listOf("titleUK", "messageUK", "buttonTitleUK", "titleDE", "messageDE", "buttonTitleDE")

data class DonationDraft(
    val enabled: Boolean = false,
    val url: String = "",
    val texts: Map<String, String> = donationTextKeys.associateWith {
        at.uac.android.feature.browse.donationDefaultText(
            it.dropLast(2),
            if (it.endsWith("UK")) "uk" else "de",
        )
    },
) {
    fun normalized(): DonationDraft {
        val trimmed = url.trim()
        val candidate =
            if (trimmed.isNotEmpty() && !trimmed.contains(":") && !trimmed.contains("://"))
                "https://$trimmed"
            else trimmed
        return copy(
            url = candidate,
            texts = donationTextKeys.associateWith { texts[it].orEmpty().trim() },
        )
    }

    fun fields(): Map<String, Any> =
        normalized().let { mapOf("isEnabled" to it.enabled, "donationURL" to it.url) + it.texts }

    fun valid(): Boolean =
        normalized().let { value ->
            value.url.length <= 2048 &&
                (value.url.isEmpty() && !value.enabled ||
                    Donation(value.fields() + ("isEnabled" to true)).url != null) &&
                donationTextKeys.all { key ->
                    value.texts.getValue(key).length <= if (key.startsWith("message")) 4000 else 200
                } &&
                value.texts.values.none { text -> text.any { it.isISOControl() && it !in "\n\t" } }
        }
}

data class DonationSnapshot(val draft: DonationDraft, val revision: Instant?, val exists: Boolean)

enum class DonationProblem {
    ACCESS,
    LOAD,
    INVALID,
    CONFLICT,
    UNCONFIRMED,
    SAVED_REFRESH_FAILED,
}

class DonationException(val problem: DonationProblem) : Exception(problem.name)

interface DonationSettingsRepository {
    suspend fun load(session: ModerationSession): DonationSnapshot

    suspend fun save(session: ModerationSession, baseline: DonationSnapshot, draft: DonationDraft)
}

fun donationSettingsRepository(
    context: Context,
    authority: () -> ModerationSession?,
    gate: ModerationDecisionGate,
): DonationSettingsRepository {
    val db = AppBackend.firestore(context)
    val access = ModerationAccess(db, AppBackend.auth(context))
    val reference = db.document("appConfig/donation")
    fun requireCurrent(session: ModerationSession) {
        if (session != authority() || !session.ready || session.role != "owner")
            throw DonationException(DonationProblem.ACCESS)
        access.identity(session)
    }
    fun decode(data: Map<String, Any?>?): DonationSnapshot {
        if (data == null) return DonationSnapshot(DonationDraft(), null, false)
        if (
            data["isEnabled"] !is Boolean ||
                data["donationURL"] !is String ||
                donationTextKeys.any { data[it] !is String }
        )
            throw DonationException(DonationProblem.INVALID)
        val stamp =
            data["updatedAt"] as? com.google.firebase.Timestamp
                ?: throw DonationException(DonationProblem.INVALID)
        return DonationSnapshot(
            DonationDraft(
                data["isEnabled"] as Boolean,
                data["donationURL"] as String,
                donationTextKeys.associateWith { data[it] as String },
            ),
            Instant.ofEpochSecond(stamp.seconds, stamp.nanoseconds.toLong()),
            true,
        )
    }
    return object : DonationSettingsRepository {
        override suspend fun load(session: ModerationSession): DonationSnapshot =
            withTimeout(15_000) {
                requireCurrent(session)
                access.privileged(session)
                decode(reference.get(Source.SERVER).await().data).also { requireCurrent(session) }
            }

        override suspend fun save(
            session: ModerationSession,
            baseline: DonationSnapshot,
            draft: DonationDraft,
        ) {
            requireCurrent(session)
            if (!draft.valid()) throw DonationException(DonationProblem.INVALID)
            gate.withSession(session) {
                access.privileged(session)
                requireCurrent(session)
                db.runTransaction { transaction ->
                        requireCurrent(session)
                        val latest = decode(transaction.get(reference).data)
                        if (latest != baseline) throw DonationException(DonationProblem.CONFLICT)
                        transaction.set(
                            reference,
                            draft.fields() +
                                mapOf(
                                    "updatedAt" to FieldValue.serverTimestamp(),
                                    "updatedBy" to session.uid,
                                ),
                        )
                        Unit
                    }
                    .await()
                requireCurrent(session)
            }
        }
    }
}

data class DonationSettingsState(
    val session: ModerationSession? = null,
    val baseline: DonationSnapshot? = null,
    val draft: DonationDraft = DonationDraft(),
    val loading: Boolean = false,
    val saving: Boolean = false,
    val saved: Boolean = false,
    val needsReadback: Boolean = false,
    val problem: DonationProblem? = null,
    val confirmLeave: Boolean = false,
) {
    val dirty
        get() = baseline != null && draft.normalized() != baseline.draft.normalized()
}

class DonationSettingsViewModel(private val repository: DonationSettingsRepository) : ViewModel() {
    private val mutable = MutableStateFlow(DonationSettingsState())
    val state = mutable.asStateFlow()
    private var job: Job? = null
    private var leave: (() -> Unit)? = null

    fun bind(session: ModerationSession?) {
        if (state.value.session == session) return
        job?.cancel()
        leave = null
        mutable.value = DonationSettingsState(session = session)
    }

    fun load(session: ModerationSession?, force: Boolean = false) {
        bind(session)
        if (session?.ready != true || session.role != "owner") {
            mutable.value = state.value.copy(problem = DonationProblem.ACCESS)
            return
        }
        if (state.value.saving || state.value.loading || (!force && state.value.baseline != null))
            return
        val previous = state.value
        if (previous.dirty && !previous.needsReadback) return
        mutable.value = previous.copy(loading = true, problem = null)
        job = viewModelScope.launch {
            try {
                val fresh = repository.load(session)
                if (state.value.session == session)
                    mutable.value =
                        state.value.copy(
                            baseline = fresh,
                            draft = fresh.draft,
                            loading = false,
                            needsReadback = false,
                        )
            } catch (error: Exception) {
                if (error is CancellationException && error !is TimeoutCancellationException)
                    throw error
                if (state.value.session == session)
                    mutable.value =
                        state.value.copy(
                            loading = false,
                            problem = (error as? DonationException)?.problem ?: DonationProblem.LOAD,
                        )
            }
        }
    }

    fun edit(draft: DonationDraft) {
        if (
            state.value.baseline == null ||
                state.value.loading ||
                state.value.saving ||
                state.value.needsReadback
        )
            return
        mutable.value = state.value.copy(draft = draft, saved = false, problem = null)
    }

    fun save() {
        val before = state.value
        val session = before.session ?: return
        val baseline = before.baseline ?: return
        if (before.loading || before.saving || before.needsReadback || !before.dirty) return
        val draft = before.draft.normalized()
        if (!draft.valid()) {
            mutable.value = before.copy(problem = DonationProblem.INVALID)
            return
        }
        mutable.value = before.copy(saving = true, saved = false, problem = null)
        job = viewModelScope.launch {
            try {
                repository.save(session, baseline, draft)
                if (state.value.session != session) return@launch
                mutable.value =
                    state.value.copy(
                        baseline = baseline.copy(draft = draft),
                        draft = draft,
                        saved = true,
                        needsReadback = true,
                    )
                try {
                    val fresh = repository.load(session)
                    if (state.value.session == session)
                        mutable.value =
                            state.value.copy(
                                baseline = fresh,
                                draft = fresh.draft,
                                needsReadback = false,
                            )
                } catch (error: Exception) {
                    if (error is CancellationException && error !is TimeoutCancellationException)
                        throw error
                    if (state.value.session == session)
                        mutable.value =
                            state.value.copy(problem = DonationProblem.SAVED_REFRESH_FAILED)
                }
            } catch (error: Exception) {
                if (error is CancellationException && error !is TimeoutCancellationException)
                    throw error
                if (state.value.session == session)
                    mutable.value =
                        state.value.copy(
                            problem =
                                (error as? DonationException)?.problem
                                    ?: DonationProblem.UNCONFIRMED,
                            needsReadback = true,
                        )
            } finally {
                if (state.value.session == session) mutable.value = state.value.copy(saving = false)
            }
        }
    }

    fun requestLeave(action: () -> Unit) {
        if (state.value.saving) return
        if (state.value.dirty) {
            leave = action
            mutable.value = state.value.copy(confirmLeave = true)
        } else action()
    }

    fun cancelLeave() {
        leave = null
        mutable.value = state.value.copy(confirmLeave = false)
    }

    fun discardAndLeave() {
        val action = leave
        leave = null
        mutable.value =
            state.value.copy(
                draft = state.value.baseline?.draft ?: DonationDraft(),
                confirmLeave = false,
            )
        action?.invoke()
    }
}
