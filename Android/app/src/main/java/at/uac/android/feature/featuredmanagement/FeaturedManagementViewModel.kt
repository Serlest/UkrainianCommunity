package at.uac.android.feature.featuredmanagement

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.moderation.ModerationSession
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class FeaturedManagementViewModel(
    private val repository: FeaturedManagementRepository,
    private val prepare: FeaturedImagePreparation,
) : ViewModel() {
    private val mutable = MutableStateFlow(FeaturedState())
    val state: StateFlow<FeaturedState> = mutable.asStateFlow()

    fun load(session: ModerationSession?) {
        if (session?.role != "owner" || !session.ready) {
            mutable.value = FeaturedState(failure = FeaturedFailure.ACCESS)
            return
        }
        val owner = session.uid
        mutable.update { if (it.loading) it else it.copy(sessionOwner = owner, loading = true, failure = null, unconfirmed = false) }
        viewModelScope.launch {
            try {
                val values = repository.list(session)
                mutable.update { current -> if (current.sessionOwner == owner) current.copy(loading = false, banners = values, failure = null) else current }
            } catch (error: CancellationException) { throw error } catch (error: FeaturedException) {
                mutable.update { current -> if (current.sessionOwner == owner) current.copy(loading = false, failure = error.failure) else current }
            }
        }
    }

    fun create() = mutable.update { it.copy(editing = FeaturedDraft(UUID.randomUUID().toString()), editingVersion = null, failure = null) }

    fun edit(banner: FeaturedBanner) = mutable.update { it.copy(editing = banner.draft, editingVersion = banner.version, failure = null) }

    fun change(transform: (FeaturedDraft) -> FeaturedDraft) = mutable.update { state -> state.editing?.let { state.copy(editing = transform(it), failure = null) } ?: state }

    fun closeEditor() = mutable.update { it.copy(editing = null, editingVersion = null, failure = null) }

    fun save(session: ModerationSession?) = launchMutation(session) { owner, snapshot ->
        val draft = snapshot.editing ?: FeaturedManagementContract.fail(FeaturedFailure.INVALID)
        repository.save(owner, draft, snapshot.editingVersion)
    }

    fun active(session: ModerationSession?, banner: FeaturedBanner, active: Boolean) = launchMutation(session) { owner, _ -> repository.setActive(owner, banner, active) }

    fun delete(session: ModerationSession?, banner: FeaturedBanner) = launchMutation(session) { owner, _ -> repository.delete(owner, banner); null }

    fun upload(session: ModerationSession?, uri: String) {
        val owner = session ?: return fail(FeaturedFailure.ACCESS)
        val draft = mutable.value.editing ?: return fail(FeaturedFailure.INVALID)
        if (mutable.value.uploading || mutable.value.saving) return fail(FeaturedFailure.BUSY)
        mutable.update { it.copy(uploading = true, failure = null) }
        viewModelScope.launch {
            try {
                val bytes = prepare.prepare(uri)
                val url = repository.upload(owner, draft.id, bytes)
                mutable.update { current -> if (current.editing?.id == draft.id) current.copy(uploading = false, editing = current.editing.copy(imageUrl = url)) else current.copy(uploading = false) }
            } catch (error: CancellationException) { throw error } catch (error: Exception) {
                fail((error as? FeaturedException)?.failure ?: FeaturedFailure.IMAGE, uploading = false)
            }
        }
    }

    private fun launchMutation(session: ModerationSession?, action: suspend (ModerationSession, FeaturedState) -> FeaturedBanner?) {
        val owner = session ?: return fail(FeaturedFailure.ACCESS)
        val snapshot = mutable.value
        if (snapshot.saving || snapshot.uploading) return fail(FeaturedFailure.BUSY)
        mutable.update { it.copy(saving = true, failure = null, unconfirmed = false) }
        viewModelScope.launch {
            try {
                action(owner, snapshot)
                val list = repository.list(owner)
                mutable.update { current -> if (current.sessionOwner == owner.uid) current.copy(saving = false, banners = list, editing = null, editingVersion = null, failure = null) else current }
            } catch (error: CancellationException) { throw error } catch (error: FeaturedException) {
                mutable.update { current -> current.copy(saving = false, failure = error.failure, unconfirmed = error.failure == FeaturedFailure.UNCONFIRMED) }
            }
        }
    }

    private fun fail(reason: FeaturedFailure, uploading: Boolean = mutable.value.uploading) { mutable.update { it.copy(uploading = uploading, failure = reason) } }
}
