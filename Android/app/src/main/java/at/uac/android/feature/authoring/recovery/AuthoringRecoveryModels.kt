package at.uac.android.feature.authoring.recovery

import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringDraft
import at.uac.android.feature.authoring.AuthoringItem
import at.uac.android.feature.authoring.AuthoringPublication
import at.uac.android.feature.authoring.AuthoringSubmission
import at.uac.android.feature.browse.ContentKind
import java.security.MessageDigest
import java.time.ZoneId
import java.util.UUID

enum class AuthoringRecoveryFailure {
    LOCKED,
    INVALID,
    IO,
    PENDING_CONFLICT,
    LIMIT,
}

class AuthoringRecoveryException(val reason: AuthoringRecoveryFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

data class AuthoringRecoveryScope(
    val uid: String,
    val organizationId: String,
    val kind: ContentKind,
) {
    init {
        require(
            uid.isNotBlank() &&
                uid == uid.trim() &&
                uid.length <= 128 &&
                uid.none(Char::isISOControl)
        )
        require(AuthoringContract.id(organizationId) && kind in AuthoringContract.kinds)
    }

    val accountHash: String
        get() = hash("uac-authoring-account-v1", uid)

    val scopeHash: String
        get() = hash("uac-authoring-scope-v1", uid, organizationId, kind.collection)
}

data class AuthoringRecoveredCreation(
    val draft: AuthoringDraft? = null,
    val draftZoneId: String? = null,
    val pending: AuthoringSubmission? = null,
)

/**
 * Create-only persistence. No authority, credentials, arbitrary image bytes or generic pending
 * deletion.
 */
interface AuthoringRecoveryStore {
    suspend fun load(scope: AuthoringRecoveryScope): AuthoringRecoveredCreation?

    suspend fun saveDraft(scope: AuthoringRecoveryScope, draft: AuthoringDraft, zoneId: String)

    /** Returns the exact durably read-back immutable intent, before the SDK may be called. */
    suspend fun prepareCreation(
        scope: AuthoringRecoveryScope,
        intent: AuthoringSubmission,
    ): AuthoringSubmission

    suspend fun confirmCreation(
        scope: AuthoringRecoveryScope,
        expectedIntent: AuthoringSubmission,
        actual: AuthoringItem,
    )

    suspend fun discardUnsent(scope: AuthoringRecoveryScope, expectedDraftId: String)

    suspend fun clearUnsentForAccount(uid: String)
}

internal enum class RecoveryPurpose(val wire: String) {
    DRAFT("draft"),
    PENDING("pending"),
}

internal data class RecoveryDraft(val draft: AuthoringDraft, val zoneId: String)

internal object RecoveryValidation {
    private val createFields =
        AuthoringContract.editableFields +
            setOf(
                "id",
                "sourceType",
                "organizationId",
                "authorId",
                "authorName",
                "createdAt",
                "publishedAt",
                "likeCount",
                "viewCount",
                "commentCount",
                "registeredCount",
                "likeState",
                "registrationState",
                "updatedAt",
                "scheduledAt",
            )

    fun creationId(value: String) = runCatching {
        UUID.fromString(value).toString() == value
    }
        .getOrDefault(false)

    fun draft(scope: AuthoringRecoveryScope, draft: AuthoringDraft, zoneId: String) {
        if (
            !creationId(draft.id) ||
                draft.kind != scope.kind ||
                runCatching { ZoneId.of(zoneId) }.isFailure
        )
            invalid()
    }

    fun intent(scope: AuthoringRecoveryScope, value: AuthoringSubmission) {
        if (
            value.base != null ||
                !creationId(value.id) ||
                value.kind != scope.kind ||
                value.organizationId != scope.organizationId ||
                value.fields["id"] != value.id ||
                value.fields["organizationId"] != scope.organizationId ||
                value.fields["authorId"] != scope.uid ||
                value.fields["sourceType"] != "organization" ||
                value.fields.keys.any { it !in createFields } ||
                value.fields["likeState"] != "notLiked" ||
                (scope.kind == ContentKind.EVENTS &&
                    value.fields["registrationState"] != "notRegistered") ||
                (scope.kind == ContentKind.NEWS && "registrationState" in value.fields) ||
                !AuthoringPublication.validStoredShape(value.fields) ||
                listOf("likeCount", "viewCount", "commentCount", "registeredCount").any {
                    value.fields[it] != null && value.fields[it] != 0L
                }
        )
            invalid()
    }

    fun same(first: AuthoringSubmission, second: AuthoringSubmission) =
        first.kind == second.kind &&
            first.id == second.id &&
            first.organizationId == second.organizationId &&
            first.base == null &&
            second.base == null &&
            first.fields == second.fields

    fun invalid(): Nothing = throw AuthoringRecoveryException(AuthoringRecoveryFailure.INVALID)
}

internal fun hash(vararg parts: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    for (part in parts) {
        val bytes = part.toByteArray(Charsets.UTF_8)
        digest.update(
            byteArrayOf(
                (bytes.size ushr 24).toByte(),
                (bytes.size ushr 16).toByte(),
                (bytes.size ushr 8).toByte(),
                bytes.size.toByte(),
            )
        )
        digest.update(bytes)
    }
    return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
