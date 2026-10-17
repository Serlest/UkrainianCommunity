package at.uac.android.feature.directory

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.BuildConfig
import at.uac.android.core.backend.CompiledBackend
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Firebase becomes authoritative only after a completeness proof; the accepted catalog survives offline restarts. */
class DirectoryViewModel(application: Application, private val source: DirectoryCatalogSource?,
    private val cache: DirectoryCatalogCache) : AndroidViewModel(application) {
    constructor(application: Application) : this(application,
        if (BuildConfig.USE_LOCAL_BACKEND) null else FirebaseDirectoryCatalogSource(application),
        DiskDirectoryCatalogCache(application, CompiledBackend.configuration.identity.projectId))

    val bundled by lazy { DirectoryCatalog.bundled(application) }
    private val mutable = MutableStateFlow(DirectorySnapshot(status = "loading",
        authoritative = runCatching { cache.activatedBefore() }.getOrDefault(true)))
    val snapshot = mutable.asStateFlow()
    private lateinit var state: DirectoryCatalogState
    private var categories: DirectoryCatalogSubscription? = null
    private var marker: DirectoryCatalogSubscription? = null
    private var confirmation: Job? = null
    private var observationEpoch = 0L
    private var serverEvents = 0L
    private val saves = Channel<DirectorySnapshot>(Channel.CONFLATED)
    private val initialized = viewModelScope.launch {
        val (cached, activated) = withContext(Dispatchers.IO) { runCatching { cache.read() }.getOrNull() to runCatching { cache.activatedBefore() }.getOrDefault(true) }
        state = DirectoryCatalogState(cached, activated)
        mutable.value = state.value
        observe()
    }

    init {
        viewModelScope.launch {
            for (snapshot in saves) {
                val success = withContext(Dispatchers.IO) { runCatching { cache.write(snapshot) }.isSuccess }
                if (!success) mutable.value = state.cacheFailure()
            }
        }
    }

    fun retry() {
        viewModelScope.launch {
            initialized.join()
            observe()
            confirm()
        }
    }

    private fun publish(next: DirectorySnapshot, save: Boolean = false) {
        mutable.value = next
        if (save && next.authoritative && next.complete && next.invalid == 0) saves.trySend(next)
    }

    private fun observe() {
        if (source == null) return
        categories?.close()
        marker?.close()
        val epoch = ++observationEpoch
        categories = source.categories({ batch ->
            if (observationEpoch == epoch) {
                val wasAuthoritative = state.value.authoritative
                if (!batch.fromCache && !batch.pendingWrites) serverEvents++
                val next = state.batch(batch)
                publish(next, !batch.fromCache && !batch.pendingWrites && batch.snapshot.invalid == 0 ||
                    !wasAuthoritative && next.authoritative)
            }
        }, { if (observationEpoch == epoch) publish(state.failure()) })
        marker = source.marker({ value, pending ->
            if (observationEpoch == epoch) {
                val wasAuthoritative = state.value.authoritative
                publish(state.marker(value, pending), !wasAuthoritative && state.value.authoritative)
                if (value != null && !pending) confirm()
            }
        }, {
            // Before migration an older ruleset may not expose the marker. Legacy bootstrap remains usable.
            if (observationEpoch == epoch && state.value.authoritative) publish(state.cached())
        })
    }

    private fun confirm() {
        if (source == null || confirmation?.isActive == true) return
        confirmation = viewModelScope.launch {
            try {
                repeat(3) {
                    val before = serverEvents
                    val batch = source.confirmedCatalog()
                    if (before == serverEvents) {
                        publish(state.batch(batch, serverReadAfterMarker = true), save = true)
                        return@launch
                    }
                    if (state.value.authoritative && state.value.complete) return@launch
                }
                publish(state.failure())
            } catch (e: CancellationException) { throw e }
            catch (_: Exception) {
                if (state.marker != null || state.value.authoritative) publish(state.failure())
            }
        }
    }

    /** A linked target is read from the server; it never resurrects an absent authoritative document from the bundle. */
    suspend fun refreshTarget(categoryID: String) {
        require(DirectoryCatalog.validId(categoryID))
        initialized.join()
        val source = source ?: return
        if (state.value.authoritative && !state.value.complete || !state.value.authoritative && state.marker != null) {
            publish(state.batch(source.confirmedCatalog(), serverReadAfterMarker = true), save = true)
            check(state.value.complete && state.value.invalid == 0)
        }
        val before = serverEvents
        val target = source.target(categoryID)
        if (before != serverEvents) return // A newer full server event already contains this target.
        publish(state.patch(categoryID, target.category, target.revision, target.deleted), save = state.value.authoritative)
    }

    override fun onCleared() {
        observationEpoch++
        categories?.close()
        marker?.close()
        saves.close()
        super.onCleared()
    }
}
