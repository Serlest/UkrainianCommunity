package at.uac.android.feature.systemlogs

import android.content.Context
import java.security.MessageDigest

interface SystemLogMutationJournal {
    fun read(principal: String): SystemLogPending?
    fun write(principal: String, pending: SystemLogPending)
    fun clear(principal: String)
}

data class SystemLogPending(val action: String, val targetId: String? = null)

class MemorySystemLogMutationJournal : SystemLogMutationJournal {
    private val values = mutableMapOf<String, SystemLogPending>()
    override fun read(principal: String) = synchronized(values) { values[principal] }
    override fun write(principal: String, pending: SystemLogPending) {
        validate(pending, requireDeleteTarget = true)
        synchronized(values) { values[principal] = pending }
    }
    override fun clear(principal: String) { synchronized(values) { values.remove(principal) } }
}

class SharedPreferencesSystemLogMutationJournal private constructor(context: Context) : SystemLogMutationJournal {
    private val preferences = context.applicationContext.getSharedPreferences("uac-system-log-mutations", Context.MODE_PRIVATE)
    private fun key(principal: String) = "pending-" + MessageDigest.getInstance("SHA-256").digest(principal.toByteArray()).take(12).joinToString("") { "%02x".format(it) }
    override fun read(principal: String): SystemLogPending? =
        preferences.getString(key(principal), null)?.let { encoded ->
            val pieces = encoded.split('\n', limit = 2)
            SystemLogPending(pieces[0], pieces.getOrNull(1)?.takeIf(String::isNotEmpty))
                .also { validate(it, requireDeleteTarget = encoded.contains('\n')) }
        }

    override fun write(principal: String, pending: SystemLogPending) {
        validate(pending, requireDeleteTarget = true)
        val encoded = pending.action + "\n" + pending.targetId.orEmpty()
        if (!preferences.edit().putString(key(principal), encoded).commit())
            SystemLogContract.fail(SystemLogFailure.OFFLINE)
    }
    override fun clear(principal: String) {
        if (!preferences.edit().remove(key(principal)).commit()) SystemLogContract.fail(SystemLogFailure.UNCONFIRMED)
    }

    companion object {
        @Volatile private var instance: SharedPreferencesSystemLogMutationJournal? = null
        fun get(context: Context): SharedPreferencesSystemLogMutationJournal = instance ?: synchronized(this) {
            instance ?: SharedPreferencesSystemLogMutationJournal(context).also { instance = it }
        }
    }
}

private fun validate(pending: SystemLogPending, requireDeleteTarget: Boolean) {
    if (pending.action !in setOf("delete", "clear", "testPush"))
        SystemLogContract.fail(SystemLogFailure.INVALID)
    if (pending.action == "delete") {
        if (requireDeleteTarget && pending.targetId?.let(SystemLogContract::id) != true)
            SystemLogContract.fail(SystemLogFailure.INVALID)
    } else if (pending.targetId != null) {
        SystemLogContract.fail(SystemLogFailure.INVALID)
    }
}
