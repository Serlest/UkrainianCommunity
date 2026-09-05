package at.uac.android.feature.contentmedia

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalImageException
import at.uac.android.core.LocalImageFailure
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.authoring.AuthoringException
import at.uac.android.feature.authoring.AuthoringFailure
import at.uac.android.feature.organization.OrganizationException
import at.uac.android.feature.organization.OrganizationFailure

/** Pure mappings are separate from Android-backed Firestore/Storage enum initializers. */
fun contentCoverFailure(error: Throwable): ContentCoverFailure =
    when (error) {
        is ContentCoverException -> error.reason
        is LocalImageException ->
            when (error.reason) {
                LocalImageFailure.INVALID -> ContentCoverFailure.INVALID_IMAGE
                LocalImageFailure.TOO_LARGE -> ContentCoverFailure.TOO_LARGE
                LocalImageFailure.UNSUPPORTED -> ContentCoverFailure.UNSUPPORTED
                LocalImageFailure.UNREADABLE -> ContentCoverFailure.UNREADABLE
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> ContentCoverFailure.DENIED
                LocalCallableFailure.NOT_FOUND -> ContentCoverFailure.MISSING
                LocalCallableFailure.INVALID_ARGUMENT -> ContentCoverFailure.INVALID
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> ContentCoverFailure.OFFLINE
                LocalCallableFailure.UNCONFIRMED -> ContentCoverFailure.UNCONFIRMED
                LocalCallableFailure.FAILED_PRECONDITION -> ContentCoverFailure.STALE
                else -> ContentCoverFailure.UNKNOWN
            }
        is AuthException ->
            when (error.problem) {
                AuthProblem.PERMISSION_DENIED -> ContentCoverFailure.DENIED
                AuthProblem.SESSION_CHANGED -> ContentCoverFailure.NOT_READY
                else -> ContentCoverFailure.NOT_READY
            }
        is AuthoringException ->
            when (error.failure) {
                AuthoringFailure.SIGN_IN -> ContentCoverFailure.SIGN_IN
                AuthoringFailure.NOT_READY -> ContentCoverFailure.NOT_READY
                AuthoringFailure.DENIED -> ContentCoverFailure.DENIED
                AuthoringFailure.INVALID -> ContentCoverFailure.INVALID
                AuthoringFailure.MISSING -> ContentCoverFailure.MISSING
                AuthoringFailure.STALE -> ContentCoverFailure.STALE
                AuthoringFailure.OFFLINE -> ContentCoverFailure.OFFLINE
                AuthoringFailure.UNCONFIRMED -> ContentCoverFailure.UNCONFIRMED
                else -> ContentCoverFailure.UNKNOWN
            }
        is OrganizationException ->
            when (error.failure) {
                OrganizationFailure.SIGN_IN -> ContentCoverFailure.SIGN_IN
                OrganizationFailure.NOT_READY -> ContentCoverFailure.NOT_READY
                OrganizationFailure.DENIED -> ContentCoverFailure.DENIED
                OrganizationFailure.INVALID -> ContentCoverFailure.INVALID
                OrganizationFailure.MISSING -> ContentCoverFailure.MISSING
                OrganizationFailure.STALE -> ContentCoverFailure.STALE
                OrganizationFailure.OFFLINE -> ContentCoverFailure.OFFLINE
                else -> ContentCoverFailure.UNKNOWN
            }
        else -> contentCoverSdkFailure(error)
    }
