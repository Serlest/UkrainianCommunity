package at.uac.android.feature.authoring.recovery

import android.util.AtomicFile
import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringDraft
import at.uac.android.feature.authoring.AuthoringItem
import at.uac.android.feature.authoring.AuthoringSubmission
import java.io.File
import java.io.FileOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** One process-wide instance and lock; AtomicFile alone does not serialize callers. */
internal class FileAuthoringRecoveryStore(
    private val root: File,
    private val cipher: AuthoringRecoveryCipher,
    private val sync: (FileOutputStream) -> Unit = { it.fd.sync() },
) : AuthoringRecoveryStore {
    private val mutex = Mutex()
    private val accountPattern = Regex("[a-f0-9]{64}")
    private val filePattern = Regex("[a-f0-9]{64}-(draft|pending)\\.bin(?:\\.bak|\\.new)?")

    private suspend fun <T> locked(block: () -> T): T =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                try {
                    directories()
                    block()
                } catch (error: AuthoringRecoveryException) {
                    throw error
                } catch (error: Exception) {
                    throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO, error)
                }
            }
        }

    private fun directories() {
        if (!root.exists() && !root.mkdirs())
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
        if (!root.isDirectory || root.canonicalFile != root.absoluteFile)
            RecoveryValidation.invalid()
    }

    private fun children(directory: File): List<File> =
        (directory.listFiles()?.toList()
                ?: throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO))
            .also {
                if (it.size > 256 || it.any { item -> item.canonicalFile != item.absoluteFile })
                    RecoveryValidation.invalid()
            }

    private fun accounts(): List<File> =
        children(root).also {
            if (it.any { item -> !accountPattern.matches(item.name) || !item.isDirectory })
                RecoveryValidation.invalid()
        }

    private fun files(account: File): List<File> =
        children(account).also {
            if (it.any { item -> !filePattern.matches(item.name) || !item.isFile })
                RecoveryValidation.invalid()
        }

    private fun directory(scope: AuthoringRecoveryScope): File {
        val account = File(root, scope.accountHash)
        if (!account.exists() && !account.mkdir())
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
        if (!account.isDirectory || account.canonicalFile != account.absoluteFile)
            RecoveryValidation.invalid()
        val scopes = files(account).map { it.name.substringBefore('-') }.toSet()
        if (scope.scopeHash !in scopes && scopes.size >= 32)
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.LIMIT)
        return account
    }

    private fun file(scope: AuthoringRecoveryScope, purpose: RecoveryPurpose) =
        File(directory(scope), "${scope.scopeHash}-${purpose.wire}.bin")

    private fun variants(file: File) =
        listOf(file, File(file.path + ".bak"), File(file.path + ".new"))

    private fun any(file: File) = variants(file).any { it.exists() }

    private fun mayCreateKey() = accounts().all { files(it).isEmpty() }

    private fun read(
        scope: AuthoringRecoveryScope,
        purpose: RecoveryPurpose,
    ): Pair<String, ByteArray>? {
        val file = file(scope, purpose)
        if (!any(file)) return null
        // An interrupted first write is not proof that no pending request existed.
        if (!file.exists() && !File(file.path + ".bak").exists())
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED)
        val bytes =
            AtomicFile(file).openRead().use { input ->
                val size = input.channel.size()
                if (size !in 1..AuthoringRecoveryCipher.MAX_ENVELOPE_BYTES.toLong())
                    RecoveryValidation.invalid()
                val buffer = ByteArray(size.toInt())
                var offset = 0
                while (offset < buffer.size) {
                    val count = input.read(buffer, offset, buffer.size - offset)
                    if (count <= 0) RecoveryValidation.invalid()
                    offset += count
                }
                if (input.read() != -1) RecoveryValidation.invalid()
                buffer
            }
        return cipher.decrypt(scope, purpose, bytes)
    }

    private fun draft(scope: AuthoringRecoveryScope): RecoveryDraft? =
        read(scope, RecoveryPurpose.DRAFT)?.let { (id, bytes) ->
            AuthoringRecoveryCodec.readDraft(scope, bytes).also {
                if (it.draft.id != id) RecoveryValidation.invalid()
            }
        }

    private fun pending(scope: AuthoringRecoveryScope): AuthoringSubmission? =
        read(scope, RecoveryPurpose.PENDING)?.let { (id, bytes) ->
            AuthoringRecoveryCodec.readPending(scope, bytes).also {
                if (it.id != id) RecoveryValidation.invalid()
            }
        }

    private fun write(
        scope: AuthoringRecoveryScope,
        purpose: RecoveryPurpose,
        id: String,
        bytes: ByteArray,
    ) {
        val target = file(scope, purpose)
        val encrypted = cipher.encrypt(scope, purpose, id, bytes, mayCreateKey())
        val atomic = AtomicFile(target)
        var stream: FileOutputStream? = null
        try {
            stream = atomic.startWrite()
            stream.write(encrypted)
            // AtomicFile may log its own sync failure instead of throwing. This explicit failure
            // must block the SDK.
            sync(stream)
            atomic.finishWrite(stream)
            stream = null
        } finally {
            if (stream != null) atomic.failWrite(stream)
        }
    }

    private fun delete(file: File) {
        AtomicFile(file).delete()
        if (any(file)) throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
    }

    override suspend fun load(scope: AuthoringRecoveryScope): AuthoringRecoveredCreation? = locked {
        val draft = draft(scope)
        val pending = pending(scope)
        if (draft == null && pending == null) null
        else AuthoringRecoveredCreation(draft?.draft, draft?.zoneId, pending)
    }

    override suspend fun saveDraft(
        scope: AuthoringRecoveryScope,
        draft: AuthoringDraft,
        zoneId: String,
    ): Unit = locked {
        if (pending(scope) != null)
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        this.draft(scope) // Validate any existing ciphertext before replacing it.
        val value = RecoveryDraft(draft, zoneId)
        write(scope, RecoveryPurpose.DRAFT, draft.id, AuthoringRecoveryCodec.draft(scope, value))
        if (this.draft(scope) != value) RecoveryValidation.invalid()
    }

    override suspend fun prepareCreation(
        scope: AuthoringRecoveryScope,
        intent: AuthoringSubmission,
    ): AuthoringSubmission = locked {
        RecoveryValidation.intent(scope, intent)
        if (draft(scope)?.draft?.id?.let { it != intent.id } == true)
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        pending(scope)?.let { stored ->
            if (!RecoveryValidation.same(stored, intent))
                throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
            return@locked stored
        }
        write(
            scope,
            RecoveryPurpose.PENDING,
            intent.id,
            AuthoringRecoveryCodec.pending(scope, intent),
        )
        val actual = pending(scope) ?: throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
        if (!RecoveryValidation.same(intent, actual)) RecoveryValidation.invalid()
        actual
    }

    override suspend fun confirmCreation(
        scope: AuthoringRecoveryScope,
        expectedIntent: AuthoringSubmission,
        actual: AuthoringItem,
    ): Unit = locked {
        RecoveryValidation.intent(scope, expectedIntent)
        if (!AuthoringContract.matches(expectedIntent, actual))
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        val existing = pending(scope)
        if (existing != null && !RecoveryValidation.same(existing, expectedIntent))
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        // Delete the unsent copy first. If this fails, the pending journal still blocks another
        // UUID.
        if (draft(scope)?.draft?.id == expectedIntent.id) delete(file(scope, RecoveryPurpose.DRAFT))
        if (existing != null) delete(file(scope, RecoveryPurpose.PENDING))
    }

    override suspend fun discardUnsent(
        scope: AuthoringRecoveryScope,
        expectedDraftId: String,
    ): Unit = locked {
        if (draft(scope)?.draft?.id == expectedDraftId) delete(file(scope, RecoveryPurpose.DRAFT))
    }

    override suspend fun clearUnsentForAccount(uid: String): Unit = locked {
        val account = File(root, hash("uac-authoring-account-v1", uid))
        if (!account.exists()) return@locked
        if (!account.isDirectory || account.canonicalFile != account.absoluteFile)
            RecoveryValidation.invalid()
        var failure: Exception? = null
        files(account)
            .filter { it.name.substringBefore(".bin").endsWith("-draft") }
            .map { File(account, it.name.substringBefore(".bin") + ".bin") }
            .distinct()
            .forEach {
                try {
                    delete(it)
                } catch (error: Exception) {
                    if (failure == null) failure = error else failure.addSuppressed(error)
                }
            }
        failure?.let { throw it }
    }
}
