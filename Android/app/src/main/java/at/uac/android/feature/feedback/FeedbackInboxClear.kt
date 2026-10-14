package at.uac.android.feature.feedback

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.LocalCallableException
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.functions.FirebaseFunctionsException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.tasks.await

/** The server returns a thread count; protected DSA cases are retained. */
internal object FeedbackInboxClearContract {
    const val callable = "clearFeedbackInbox"

    fun count(data: Any?): Int {
        val value = data as? Map<*, *> ?: error("CLEAR_RECEIPT_INVALID")
        require(value.keys == setOf("deletedCount")) { "CLEAR_RECEIPT_INVALID" }
        val number = value["deletedCount"] as? Number ?: error("CLEAR_RECEIPT_INVALID")
        val long = number.toLong()
        require(number.toDouble() == long.toDouble() && long in 0..10_000) {
            "CLEAR_RECEIPT_INVALID"
        }
        return long.toInt()
    }
}

internal interface FeedbackInboxClearJournal {
    fun pending(uid: String): Boolean
    fun mark(uid: String)
    fun clear(uid: String)
}

internal class PersistentFeedbackInboxClearJournal(context: Context) : FeedbackInboxClearJournal {
    private val preferences = context.applicationContext.getSharedPreferences("uac-feedback-inbox-clear", Context.MODE_PRIVATE)
    private fun key(uid: String): String =
        MessageDigest.getInstance("SHA-256").digest(uid.toByteArray()).take(16)
            .joinToString("") { "%02x".format(it) }

    override fun pending(uid: String) = preferences.getBoolean(key(uid), false)
    override fun mark(uid: String) {
        check(preferences.edit().putBoolean(key(uid), true).commit()) { "CLEAR_JOURNAL_FAILED" }
    }
    override fun clear(uid: String) {
        check(preferences.edit().remove(key(uid)).commit()) { "CLEAR_JOURNAL_FAILED" }
    }
}

internal interface FeedbackInboxClearSource {
    suspend fun prepare(session: ModerationSession)
    suspend fun clear(session: ModerationSession): Int
}

internal class FirebaseFeedbackInboxClearSource(
    db: FirebaseFirestore,
    auth: FirebaseAuth,
    private val functions: CallableGateway,
) : FeedbackInboxClearSource {
    private val access = ModerationAccess(db, auth)
    init { FirebaseBackendGuard.requireSameApp(auth, db); functions.requireBoundTo(auth) }

    override suspend fun prepare(session: ModerationSession) {
        access.privileged(session)
        access.identity(session)
    }

    override suspend fun clear(session: ModerationSession): Int {
        access.identity(session)
        return FeedbackInboxClearContract.count(
            functions.getHttpsCallable(FeedbackInboxClearContract.callable)
                .withTimeout(
                    LocalCallableProtocol.maximumTimeoutMillis(FeedbackInboxClearContract.callable),
                    TimeUnit.MILLISECONDS,
                ).call(emptyMap<String, Any>()).await().data
        )
    }
}

internal fun localFeedbackInboxClearSource(context: Context): FeedbackInboxClearSource =
    FirebaseFeedbackInboxClearSource(
        AppBackend.firestore(context), AppBackend.auth(context), AppBackend.callables(context),
    )

internal class FeedbackInboxClearRepository(
    private val source: FeedbackInboxClearSource,
    private val journal: FeedbackInboxClearJournal,
    private val authority: () -> ModerationSession?,
) {
    private val mutex = Mutex()

    fun pending(session: ModerationSession?): Boolean =
        session?.takeIf { it.ready && it.role == "owner" }?.let { journal.pending(it.uid) } ?: false

    suspend fun clear(session: ModerationSession): Int {
        check(mutex.tryLock()) { "CLEAR_BUSY" }
        try {
            require(session.ready && session.role == "owner" && authority() == session) {
                "CLEAR_ACCESS"
            }
            check(!journal.pending(session.uid)) { "CLEAR_PENDING" }
            source.prepare(session)
            require(authority() == session) { "CLEAR_ACCESS" }
            // Persist before network dispatch. Even an uncertain response cannot trigger a replay.
            journal.mark(session.uid)
            return withContext(NonCancellable) {
                val result = source.clear(session)
                journal.clear(session.uid)
                result
            }
        } finally { mutex.unlock() }
    }

    /** Operator action after reviewing the server inbox; never resends the previous request. */
    fun acknowledge(session: ModerationSession) {
        require(session.ready && session.role == "owner" && authority() == session) {
            "CLEAR_ACCESS"
        }
        journal.clear(session.uid)
    }
}

data class FeedbackInboxClearState(
    val busy: Boolean = false,
    val pending: Boolean = false,
    val deletedCount: Int? = null,
    val failed: Boolean = false,
    val failureCode: String? = null,
)

internal class FeedbackInboxClearViewModel(
    private val repository: FeedbackInboxClearRepository,
) : ViewModel() {
    private val mutable = MutableStateFlow(FeedbackInboxClearState())
    val state = mutable.asStateFlow()
    private var bound: ModerationSession? = null

    fun bind(session: ModerationSession?) {
        if (bound == session) return
        bound = session
        mutable.value = FeedbackInboxClearState(pending = repository.pending(session))
    }

    fun clear(session: ModerationSession?, onSuccess: () -> Unit) {
        if (session == null || bound != session || mutable.value.busy || mutable.value.pending) return
        mutable.value = FeedbackInboxClearState(busy = true)
        viewModelScope.launch {
            try {
                val count = repository.clear(session)
                if (bound == session) {
                    mutable.value = FeedbackInboxClearState(deletedCount = count)
                    // UI refresh is secondary; it cannot turn a confirmed deletion into a
                    // retryable failure if navigation or the read layer throws afterwards.
                    runCatching(onSuccess)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val code = when (error) {
                    is FirebaseFunctionsException -> "FUNCTION_${error.code.name}"
                    is LocalCallableException -> "CALLABLE_${error.code.name}"
                    is ModerationException -> "MODERATION_${error.failure.name}"
                    else -> error.javaClass.simpleName.take(80)
                }
                if (bound == session) mutable.value = FeedbackInboxClearState(
                    pending = repository.pending(session), failed = true, failureCode = code,
                )
            }
        }
    }

    fun acknowledge(session: ModerationSession?) {
        if (session == null || bound != session || mutable.value.busy) return
        runCatching { repository.acknowledge(session) }
            .onSuccess { mutable.value = FeedbackInboxClearState() }
            .onFailure { mutable.value = mutable.value.copy(failed = true) }
    }
}
