package at.uac.android.feature.announcements

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AnnouncementDraft(
    val id: String = UUID.randomUUID().toString().replace("-", "_"),
    val revision: Int = 0,
    val titleUk: String = "",
    val titleDe: String = "",
    val bodyUk: String = "",
    val bodyDe: String = "",
    val groups: Set<String> = setOf("registered"),
    val userIds: Set<String> = emptySet(),
    val regions: Set<String> = emptySet(),
    val targetPlatforms: Set<String> = setOf("ios", "android"),
    val mode: String = "once",
    val feedback: Boolean = false,
    val push: Boolean = false,
    val startsAt: Long = System.currentTimeMillis(),
    val expiresAt: Long = System.currentTimeMillis() + 7 * 86_400_000L,
) {
    fun payload() =
        mapOf(
            "id" to id,
            "schemaVersion" to AnnouncementContract.CAPABILITY,
            "revision" to revision,
            "title" to mapOf("uk" to titleUk.trim(), "de" to titleDe.trim()),
            "body" to mapOf("uk" to bodyUk.trim(), "de" to bodyDe.trim()),
            "groups" to groups.sorted(),
            "userIds" to userIds.sorted(),
            "regions" to regions.sorted(),
            "targetPlatforms" to targetPlatforms.sorted(),
            "mode" to mode,
            "feedback" to feedback,
            "push" to push,
            "startsAt" to startsAt,
            "expiresAt" to expiresAt,
        )

    fun publishable(now: Long = System.currentTimeMillis()) =
        listOf(titleUk, titleDe, bodyUk, bodyDe).all { it.isNotBlank() } &&
            titleUk.length <= 160 &&
            titleDe.length <= 160 &&
            bodyUk.length <= 6_000 &&
            bodyDe.length <= 6_000 &&
            (groups.isNotEmpty() || userIds.isNotEmpty()) &&
            userIds.size <= 100 && userIds.all(AnnouncementContract::id) &&
            targetPlatforms.isNotEmpty() &&
            expiresAt > maxOf(startsAt, now) &&
            expiresAt - startsAt <= 90 * 86_400_000L
}

data class AnnouncementOwnerState(
    val items: List<UserAnnouncement> = emptyList(),
    val draft: AnnouncementDraft? = null,
    val loading: Boolean = false,
    val error: AnnouncementFailure? = null,
    val notice: String? = null,
    val audience: AnnouncementAudience? = null,
    val statistics: Map<String, AnnouncementStatistics> = emptyMap(),
    val users: List<AnnouncementUser> = emptyList(),
    val usersCursor: String? = null,
    val itemsCursor: String? = null,
)

data class AnnouncementUser(val id: String, val name: String, val region: String?)

data class AnnouncementAudience(val accounts: Int, val guests: Boolean)

data class AnnouncementStatistics(
    val presented: Int,
    val acknowledged: Int,
    val action: Int,
    val guestPresented: Int,
    val guestAcknowledged: Int,
    val pushSuccess: Int,
    val pushFailure: Int,
    val pushState: String,
)

class AnnouncementViewModel(
    private val source: AnnouncementSource,
    private val store: AnnouncementLocalStore,
) : ViewModel() {
    private val mutable = MutableStateFlow(AnnouncementState(guestPushEnabled = store.guestPushEnabled))
    val state: StateFlow<AnnouncementState> = mutable.asStateFlow()
    private val mutableOwner = MutableStateFlow(AnnouncementOwnerState())
    val ownerState: StateFlow<AnnouncementOwnerState> = mutableOwner.asStateFlow()
    private var refreshJob: Job? = null
    private val presentedThisSession = mutableSetOf<String>()

    fun configure(session: AnnouncementSession) {
        if (mutable.value.session == session) return
        refreshJob?.cancel()
        presentedThisSession.clear()
        mutable.value = AnnouncementState(session = session, guestPushEnabled = store.guestPushEnabled)
        mutableOwner.value = AnnouncementOwnerState()
    }

    fun refresh(present: Boolean = false) {
        val captured = mutable.value.session ?: return
        if (!captured.available || !captured.ready) return
        refreshJob?.cancel()
        refreshJob = viewModelScope.launch {
            mutable.value = mutable.value.copy(loading = true, error = null)
            try {
                flushPending(captured)
                var cursor: String? = null
                var serverNow = 0L
                val items = mutableListOf<UserAnnouncement>()
                var pages = 0
                do {
                    val page = source.feed(cursor)
                    requireCurrent(captured)
                    serverNow = page.serverNow
                    items += page.items
                    cursor = page.cursor
                    pages++
                } while (cursor != null && pages < 10)
                if (cursor != null) AnnouncementContract.fail(AnnouncementFailure.INVALID)
                requireCurrent(captured)
                mutable.value =
                    mutable.value.copy(
                        items = items.distinctBy { it.id },
                        serverNow = serverNow,
                        loading = false,
                        error = null,
                    )
                if (present) presentIfPossible()
            } catch (error: CancellationException) {
                throw error
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutable.value = mutable.value.copy(loading = false, error = error.failure)
            } catch (_: Exception) {
                if (mutable.value.session == captured)
                    mutable.value = mutable.value.copy(loading = false, error = AnnouncementFailure.UNKNOWN)
            }
        }
    }

    fun presentIfPossible(preferredId: String? = mutable.value.pendingPushId) {
        val current = mutable.value
        if (current.active != null || !current.session.orReady()) return
        val candidate =
            current.items.firstOrNull {
                (preferredId == null || it.id == preferredId) && eligible(it, current)
            } ?: current.items.firstOrNull { eligible(it, current) }
        if (candidate != null) {
            mutable.value = current.copy(active = candidate, pendingPushId = null)
            record(candidate, "presented")
        }
    }

    fun dismiss() {
        if (mutable.value.active != null) mutable.value = mutable.value.copy(active = null)
    }

    fun acknowledge() {
        val item = mutable.value.active ?: return
        record(item, "acknowledged")
        mutable.value = mutable.value.copy(active = null)
    }

    fun action() {
        mutable.value.active?.let { record(it, "action") }
        mutable.value = mutable.value.copy(active = null)
    }

    fun push(id: String) {
        if (!AnnouncementContract.id(id)) return
        mutable.value = mutable.value.copy(pendingPushId = id)
        refresh()
    }

    fun open(id: String) {
        if (!AnnouncementContract.id(id)) return
        val item = mutable.value.items.firstOrNull { it.id == id }
        if (item != null) mutable.value = mutable.value.copy(active = item, pendingPushId = null)
        else {
            mutable.value = mutable.value.copy(pendingPushId = id)
            refresh(present = true)
        }
    }

    fun challenge(value: String) {
        if (!Regex("[a-f0-9]{64}").matches(value)) return
        val captured = mutable.value.session ?: return
        viewModelScope.launch {
            runCatching { source.confirm(store.secret, value) }
            if (mutable.value.session == captured) syncPush(language = "de", permission = true)
        }
    }

    fun syncPush(language: String, permission: Boolean) {
        val captured = mutable.value.session ?: return
        viewModelScope.launch {
            try {
                if (!permission || captured.uid == null && !store.guestPushEnabled) {
                    source.disable(store.secret)
                    return@launch
                }
                val fid = source.installationId()
                requireCurrent(captured)
                source.register(store.secret, fid, language)
            } catch (_: Exception) {
                // The in-app feed remains authoritative and registration retries next foreground.
            }
        }
    }

    fun guestPush(enabled: Boolean, language: String, permission: Boolean) {
        store.guestPushEnabled = enabled
        mutable.value = mutable.value.copy(guestPushEnabled = enabled)
        syncPush(language, permission && enabled)
    }

    fun loadOwner() = loadOwnerPage(more = false)

    fun loadMoreOwner() = loadOwnerPage(more = true)

    private fun loadOwnerPage(more: Boolean) {
        val session = mutable.value.session ?: return
        if (!session.owner) return
        val cursor = if (more) mutableOwner.value.itemsCursor ?: return else null
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null)
            try {
                val response = source.manage("list", buildMap { cursor?.let { put("cursor", it) } }) as? Map<*, *>
                    ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                val items = (response["items"] as? List<*>)?.map(AnnouncementContract::parse)
                    ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                val next = response["cursor"]?.let { it as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID) }
                if (next != null && !AnnouncementContract.id(next)) AnnouncementContract.fail(AnnouncementFailure.INVALID)
                requireCurrent(session)
                mutableOwner.value = mutableOwner.value.copy(
                    items = ((if (more) mutableOwner.value.items else emptyList()) + items).distinctBy { it.id },
                    itemsCursor = next,
                    loading = false,
                    error = null,
                )
            } catch (error: AnnouncementException) {
                if (mutable.value.session == session)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    fun edit(draft: AnnouncementDraft = AnnouncementDraft()) {
        mutableOwner.value = mutableOwner.value.copy(draft = draft, notice = null, error = null, audience = null)
    }

    fun edit(item: UserAnnouncement) = edit(draftFrom(item))

    fun changeDraft(block: (AnnouncementDraft) -> AnnouncementDraft) {
        mutableOwner.value.draft?.let { mutableOwner.value = mutableOwner.value.copy(draft = block(it)) }
    }

    fun saveDraft() = ownerMutation("save") { draft ->
        mapOf("draft" to draft.payload(), "revision" to draft.revision)
    }

    fun publishDraft() = ownerMutation("publish") { draft ->
        if (!draft.publishable()) AnnouncementContract.fail(AnnouncementFailure.INVALID)
        mapOf("id" to draft.id, "revision" to draft.revision)
    }

    fun testDraft() = ownerMutation("test") { draft ->
        if (!draft.publishable()) AnnouncementContract.fail(AnnouncementFailure.INVALID)
        mapOf("draft" to draft.payload())
    }

    fun previewDraft() {
        val captured = mutable.value.session ?: return
        val draft = mutableOwner.value.draft ?: return
        if (!captured.owner) return
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null, audience = null)
            try {
                var cursor: String? = null
                var accounts = 0
                var guests = false
                var pages = 0
                do {
                    val response = source.manage("preview", buildMap {
                        put("draft", draft.payload())
                        cursor?.let { put("cursor", it) }
                    }) as? Map<*, *> ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    accounts += (response["accounts"] as? Number)?.toInt()?.takeIf { it >= 0 }
                        ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    guests = guests || (response["guests"] as? Boolean
                        ?: AnnouncementContract.fail(AnnouncementFailure.INVALID))
                    cursor = response["cursor"]?.let { it as? String
                        ?: AnnouncementContract.fail(AnnouncementFailure.INVALID) }
                    pages++
                } while (cursor != null && pages < 100)
                if (cursor != null) AnnouncementContract.fail(AnnouncementFailure.LIMIT)
                requireCurrent(captured)
                if (mutableOwner.value.draft == draft)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, audience = AnnouncementAudience(accounts, guests))
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    fun loadUsers(more: Boolean = false) {
        val captured = mutable.value.session ?: return
        if (!captured.owner || mutableOwner.value.loading) return
        val cursor = if (more) mutableOwner.value.usersCursor ?: return else null
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null)
            try {
                val response = source.manage("users", buildMap { cursor?.let { put("cursor", it) } }) as? Map<*, *>
                    ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                val page = (response["items"] as? List<*>)?.map { raw ->
                    val user = raw as? Map<*, *> ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    val id = user["id"] as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    val name = user["name"] as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    val region = user["region"]?.let { it as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID) }
                    if (!AnnouncementContract.id(id) || name.isBlank() || name.length > 300 ||
                        region != null && region !in AnnouncementContract.REGIONS)
                        AnnouncementContract.fail(AnnouncementFailure.INVALID)
                    AnnouncementUser(id, name, region)
                } ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                val next = response["cursor"]?.let { it as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID) }
                if (next != null && !AnnouncementContract.id(next)) AnnouncementContract.fail(AnnouncementFailure.INVALID)
                requireCurrent(captured)
                mutableOwner.value = mutableOwner.value.copy(
                    loading = false,
                    users = (if (more) mutableOwner.value.users else emptyList()) + page,
                    usersCursor = next,
                )
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    fun cancel(item: UserAnnouncement) = ownerItemOperation(item, "cancel")

    fun statistics(item: UserAnnouncement) {
        val captured = mutable.value.session ?: return
        if (!captured.owner) return
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null)
            try {
                val response = source.manage("stats", mapOf("id" to item.id)) as? Map<*, *>
                    ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                fun count(key: String) = (response[key] as? Number)?.toInt()?.takeIf { it >= 0 }
                    ?: AnnouncementContract.fail(AnnouncementFailure.INVALID)
                val result = AnnouncementStatistics(
                    count("presented"), count("acknowledged"), count("action"),
                    count("guestPresented"), count("guestAcknowledged"),
                    count("pushSuccess"), count("pushFailure"),
                    response["pushState"] as? String ?: AnnouncementContract.fail(AnnouncementFailure.INVALID),
                )
                requireCurrent(captured)
                mutableOwner.value = mutableOwner.value.copy(
                    loading = false,
                    statistics = mutableOwner.value.statistics + (item.id to result),
                )
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    private fun ownerItemOperation(item: UserAnnouncement, operation: String) {
        val captured = mutable.value.session ?: return
        if (!captured.owner || !AnnouncementContract.id(item.id)) return
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null)
            try {
                source.manage(operation, mapOf("id" to item.id))
                requireCurrent(captured)
                mutableOwner.value = mutableOwner.value.copy(loading = false, notice = operation)
                loadOwner()
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    private fun ownerMutation(operation: String, payload: (AnnouncementDraft) -> Map<String, Any?>) {
        val captured = mutable.value.session ?: return
        val draft = mutableOwner.value.draft ?: return
        if (!captured.owner) return
        viewModelScope.launch {
            mutableOwner.value = mutableOwner.value.copy(loading = true, error = null, notice = null)
            try {
                val response = source.manage(operation, payload(draft))
                requireCurrent(captured)
                val saved = (response as? Map<*, *>)?.get("item")?.let(AnnouncementContract::parse)
                val updatedDraft = saved?.let(::draftFrom) ?: draft
                mutableOwner.value = mutableOwner.value.copy(
                    draft = if (operation == "publish") null else updatedDraft,
                    loading = false,
                    notice = operation,
                )
                if (operation != "save") loadOwner()
            } catch (error: AnnouncementException) {
                if (mutable.value.session == captured)
                    mutableOwner.value = mutableOwner.value.copy(loading = false, error = error.failure)
            }
        }
    }

    private fun record(item: UserAnnouncement, event: String) {
        val session = mutable.value.session ?: return
        if (event == "presented") presentedThisSession += item.id
        if (session.uid == null && event in setOf("presented", "acknowledged")) store.mark(item.id, event)
        val scope = store.scope(session.uid)
        store.pending(item.id, event, scope, true)
        viewModelScope.launch {
            try {
                source.event(item.id, event, if (session.uid == null) store.secret else null)
                store.pending(item.id, event, scope, false)
            } catch (_: Exception) {
                // Idempotent event is replayed on the next refresh.
            }
        }
    }

    private suspend fun flushPending(session: AnnouncementSession) {
        val scope = store.scope(session.uid)
        for ((id, event) in store.pendingEvents(scope)) {
            source.event(id, event, if (session.uid == null) store.secret else null)
            requireCurrent(session)
            store.pending(id, event, scope, false)
        }
    }

    private fun eligible(item: UserAnnouncement, state: AnnouncementState): Boolean {
        if (!item.active(state.serverNow)) return false
        if (item.id in presentedThisSession) return false
        return if (state.session?.uid == null)
            if (item.mode == "once") !store.presented(item.id) else !store.acknowledged(item.id)
        else if (item.mode == "once") item.presentedAt == null else item.acknowledgedAt == null
    }

    private fun requireCurrent(session: AnnouncementSession) {
        if (mutable.value.session != session) AnnouncementContract.fail(AnnouncementFailure.STALE)
    }

    private fun AnnouncementSession?.orReady() = this?.available == true && this.ready

    private fun draftFrom(item: UserAnnouncement) =
        AnnouncementDraft(
            id = item.id,
            revision = item.revision,
            titleUk = item.title.uk,
            titleDe = item.title.de,
            bodyUk = item.body.uk,
            bodyDe = item.body.de,
            groups = item.groups.toSet(),
            userIds = item.userIds.toSet(),
            regions = item.regions.toSet(),
            targetPlatforms = item.targetPlatforms.toSet(),
            mode = item.mode,
            feedback = item.feedback,
            push = item.push,
            startsAt = item.startsAt,
            expiresAt = item.expiresAt,
        )
}
