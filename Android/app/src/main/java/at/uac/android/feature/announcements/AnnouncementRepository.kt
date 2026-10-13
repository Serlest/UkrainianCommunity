package at.uac.android.feature.announcements

import android.content.Context
import androidx.core.content.edit
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

interface AnnouncementSource {
    suspend fun installationId(): String

    suspend fun feed(cursor: String? = null): AnnouncementPage

    suspend fun event(id: String, event: String, secret: String?)

    suspend fun register(secret: String, fid: String, language: String)

    suspend fun confirm(secret: String, challenge: String)

    suspend fun disable(secret: String)

    suspend fun manage(operation: String, values: Map<String, Any?> = emptyMap()): Any?

}

class FirebaseAnnouncementSource(
    private val calls: CallableGateway,
    private val installations: FirebaseInstallations,
) : AnnouncementSource {
    override suspend fun feed(cursor: String?): AnnouncementPage = request {
        AnnouncementContract.parsePage(
            call(
                "getAnnouncements",
                buildMap {
                    put("platform", "android")
                    put("capability", AnnouncementContract.CAPABILITY)
                    cursor?.let { put("cursor", it) }
                },
            )
        )
    }

    override suspend fun event(id: String, event: String, secret: String?) {
        request {
        require(AnnouncementContract.id(id) && event in setOf("presented", "acknowledged", "action"))
        call(
            "acknowledgeAnnouncement",
            buildMap {
                put("platform", "android")
                put("capability", AnnouncementContract.CAPABILITY)
                put("id", id)
                put("event", event)
                secret?.let { put("secret", it) }
            },
            )
        }
    }

    override suspend fun register(secret: String, fid: String, language: String) {
        request {
            call(
            "registerAnnouncementDevice",
            mapOf(
                "platform" to "android",
                "capability" to AnnouncementContract.CAPABILITY,
                "secret" to secret,
                "fid" to fid,
                "language" to language,
            ),
            )
        }
    }

    override suspend fun confirm(secret: String, challenge: String) {
        request {
            call(
            "registerAnnouncementDevice",
            mapOf(
                "platform" to "android",
                "capability" to AnnouncementContract.CAPABILITY,
                "operation" to "confirm",
                "secret" to secret,
                "challenge" to challenge,
            ),
            )
        }
    }

    override suspend fun disable(secret: String) {
        request {
            call(
            "registerAnnouncementDevice",
            mapOf(
                "platform" to "android",
                "capability" to AnnouncementContract.CAPABILITY,
                "operation" to "disable",
                "secret" to secret,
            ),
            )
        }
    }

    override suspend fun manage(operation: String, values: Map<String, Any?>): Any? = request {
        call("manageAnnouncements", mapOf("operation" to operation) + values)
    }

    @Suppress("DEPRECATION")
    override suspend fun installationId(): String = request {
        FirebaseMessaging.getInstance().token.await()
        installations.id.await()
    }

    private suspend fun call(name: String, data: Map<String, Any?>): Any? =
        calls.getHttpsCallable(name).withTimeout(20, TimeUnit.SECONDS).call(data).await().data

    private suspend fun <T> request(block: suspend () -> T): T =
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: AnnouncementException) {
            throw error
        } catch (error: LocalCallableException) {
            throw AnnouncementException(
                when (error.code) {
                    LocalCallableFailure.UNAUTHENTICATED -> AnnouncementFailure.SIGN_IN
                    LocalCallableFailure.PERMISSION_DENIED -> AnnouncementFailure.DENIED
                    LocalCallableFailure.FAILED_PRECONDITION -> AnnouncementFailure.NOT_READY
                    LocalCallableFailure.ABORTED -> AnnouncementFailure.STALE
                    LocalCallableFailure.RESOURCE_EXHAUSTED -> AnnouncementFailure.LIMIT
                    LocalCallableFailure.INVALID_ARGUMENT,
                    LocalCallableFailure.NOT_FOUND -> AnnouncementFailure.INVALID
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED -> AnnouncementFailure.OFFLINE
                    else -> AnnouncementFailure.UNKNOWN
                },
                error,
            )
        } catch (error: Exception) {
            throw AnnouncementException(AnnouncementFailure.UNKNOWN, error)
        }
}

interface AnnouncementLocalStore {
    val secret: String
    var guestPushEnabled: Boolean
    fun presented(id: String): Boolean
    fun acknowledged(id: String): Boolean
    fun mark(id: String, event: String)
    fun pending(id: String, event: String, scope: String, value: Boolean)
    fun pendingEvents(scope: String): List<Pair<String, String>>
    fun scope(uid: String?): String
}

class AnnouncementInstallationStore(context: Context) : AnnouncementLocalStore {
    private val preferences =
        context.applicationContext.getSharedPreferences("uac-announcements", Context.MODE_PRIVATE)

    override val secret: String
        get() =
            preferences.getString("installation-secret", null)
                ?: ByteArray(48)
                    .also(SecureRandom()::nextBytes)
                    .joinToString("") { "%02x".format(it) }
                    .also { preferences.edit(commit = true) { putString("installation-secret", it) } }

    override var guestPushEnabled: Boolean
        get() = preferences.getBoolean("guest-push", false)
        set(value) = preferences.edit { putBoolean("guest-push", value) }

    override fun presented(id: String) = preferences.getBoolean("presented:$id", false)

    override fun acknowledged(id: String) = preferences.getBoolean("acknowledged:$id", false)

    override fun mark(id: String, event: String) {
        if (AnnouncementContract.id(id) && event in setOf("presented", "acknowledged"))
            preferences.edit { putBoolean("$event:$id", true) }
    }

    override fun pending(id: String, event: String, scope: String, value: Boolean) {
        if (AnnouncementContract.id(id) && event in setOf("presented", "acknowledged", "action"))
            preferences.edit { putBoolean("pending:$scope:$event:$id", value) }
    }

    override fun pendingEvents(scope: String): List<Pair<String, String>> =
        preferences.all.keys
            .filter { it.startsWith("pending:$scope:") && preferences.getBoolean(it, false) }
            .take(100)
            .mapNotNull { key ->
                val parts = key.split(':', limit = 4)
                if (parts.size == 4 && parts[2] in setOf("presented", "acknowledged", "action") &&
                    AnnouncementContract.id(parts[3])) parts[3] to parts[2] else null
            }

    override fun scope(uid: String?): String =
        if (uid == null) "guest"
        else MessageDigest.getInstance("SHA-256").digest(uid.toByteArray()).take(12)
            .joinToString("") { "%02x".format(it) }
}

object AnnouncementPushInbox {
    private const val PREFERENCES = "uac-announcement-push"

    fun putId(context: Context, value: String) {
        if (AnnouncementContract.id(value))
            context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit(commit = true) { putString("id", value) }
    }

    fun putChallenge(context: Context, value: String) {
        if (Regex("[a-f0-9]{64}").matches(value))
            context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit(commit = true) { putString("challenge", value) }
    }

    fun takeId(context: Context): String? = take(context, "id")?.takeIf(AnnouncementContract::id)

    fun takeChallenge(context: Context): String? =
        take(context, "challenge")?.takeIf { Regex("[a-f0-9]{64}").matches(it) }

    private fun take(context: Context, key: String): String? {
        val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val value = preferences.getString(key, null)
        if (value != null) preferences.edit(commit = true) { remove(key) }
        return value
    }
}

fun announcementSource(context: Context): FirebaseAnnouncementSource {
    val app = AppBackend.app(context)
    return FirebaseAnnouncementSource(
        AppBackend.callables(context),
        FirebaseInstallations.getInstance(app),
    )
}
