package at.uac.android.feature.contentmedia

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalImageException
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.authoring.AuthoringException
import at.uac.android.feature.organization.OrganizationException

enum class ContentCoverStage {
    UPLOAD_CALL,
    UPLOAD_RECEIPT,
    READ_DOCUMENT,
    READ_IMAGE,
    VERIFY_UPLOAD,
    REMOVE_CALL,
    VERIFY_REMOVE,
    MUTATION,
}

enum class ContentCoverCheck {
    TARGET,
    DOCUMENT_URL,
    BYTE_COUNT,
    BYTES,
    TOKEN,
    CONTENT_TYPE,
    JPEG,
    PRESERVED_FIELDS,
    MISSING_ASSET,
    REFERENCE_PRESENT,
}

data class ContentCoverCause(val type: String, val code: String?)

/**
 * Safe structured diagnostics only: never Throwable messages/details, IDs, URLs, tokens or image
 * data.
 */
data class ContentCoverDiagnostic(
    val stage: ContentCoverStage,
    val causes: List<ContentCoverCause> = emptyList(),
    val failedChecks: Set<ContentCoverCheck> = emptySet(),
    val changedFields: Set<String> = emptySet(),
)

fun contentCoverDiagnostic(stage: ContentCoverStage, error: Throwable): ContentCoverDiagnostic {
    val chain = generateSequence(error) { it.cause }.take(10).toList()
    chain
        .filterIsInstance<ContentCoverException>()
        .firstNotNullOfOrNull { it.diagnostic }
        ?.let {
            return it
        }
    return ContentCoverDiagnostic(
        stage,
        chain.map { cause ->
            val type =
                cause.javaClass.simpleName.takeIf { it.matches(Regex("[A-Za-z0-9_$]{1,80}")) }
                    ?: "Exception"
            val code =
                when (cause) {
                    is ContentCoverException -> cause.reason.name
                    is LocalCallableException -> cause.code.name
                    is LocalImageException -> cause.reason.name
                    is AuthoringException -> cause.failure.name
                    is OrganizationException -> cause.failure.name
                    is AuthException -> cause.problem.name
                    else -> contentCoverSdkCode(cause)
                }
            ContentCoverCause(type, code)
        },
    )
}

internal fun contentCoverChangedFields(
    before: ContentCoverSnapshot,
    after: ContentCoverSnapshot,
): Set<String> =
    (before.item.fields.keys + after.item.fields.keys)
        .filter { key ->
            key !in setOf("imageURL", "updatedAt") &&
                before.item.fields[key] != after.item.fields[key]
        }
        .mapTo(linkedSetOf()) { key ->
            key.takeIf { it.matches(Regex("[A-Za-z][A-Za-z0-9_.-]{0,63}")) } ?: "unexpected-field"
        }
