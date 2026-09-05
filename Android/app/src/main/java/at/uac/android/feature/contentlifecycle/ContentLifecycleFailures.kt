package at.uac.android.feature.contentlifecycle

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.authoring.AuthoringException
import at.uac.android.feature.authoring.AuthoringFailure
import at.uac.android.feature.organization.OrganizationException
import at.uac.android.feature.organization.OrganizationFailure

/** Kept separate from Android-backed Firestore enum initializers so protocol mapping is pure. */
fun contentLifecycleFailure(error: Throwable): ContentLifecycleFailure =
    when (error) {
        is ContentLifecycleException -> error.reason
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> ContentLifecycleFailure.DENIED
                LocalCallableFailure.INVALID_ARGUMENT -> ContentLifecycleFailure.INVALID
                LocalCallableFailure.NOT_FOUND -> ContentLifecycleFailure.MISSING
                LocalCallableFailure.FAILED_PRECONDITION -> ContentLifecycleFailure.STALE
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> ContentLifecycleFailure.OFFLINE
                LocalCallableFailure.UNCONFIRMED -> ContentLifecycleFailure.UNCONFIRMED
                else -> ContentLifecycleFailure.UNKNOWN
            }
        is AuthException -> ContentLifecycleFailure.NOT_READY
        is AuthoringException ->
            when (error.failure) {
                AuthoringFailure.SIGN_IN -> ContentLifecycleFailure.SIGN_IN
                AuthoringFailure.NOT_READY -> ContentLifecycleFailure.NOT_READY
                AuthoringFailure.DENIED -> ContentLifecycleFailure.DENIED
                AuthoringFailure.MISSING -> ContentLifecycleFailure.MISSING
                AuthoringFailure.STALE -> ContentLifecycleFailure.STALE
                AuthoringFailure.INVALID -> ContentLifecycleFailure.INVALID
                AuthoringFailure.OFFLINE -> ContentLifecycleFailure.OFFLINE
                AuthoringFailure.INDEX -> ContentLifecycleFailure.INDEX
                AuthoringFailure.UNCONFIRMED -> ContentLifecycleFailure.UNCONFIRMED
                else -> ContentLifecycleFailure.UNKNOWN
            }
        is OrganizationException ->
            when (error.failure) {
                OrganizationFailure.SIGN_IN -> ContentLifecycleFailure.SIGN_IN
                OrganizationFailure.NOT_READY -> ContentLifecycleFailure.NOT_READY
                OrganizationFailure.DENIED -> ContentLifecycleFailure.DENIED
                OrganizationFailure.INVALID -> ContentLifecycleFailure.INVALID
                OrganizationFailure.MISSING -> ContentLifecycleFailure.MISSING
                OrganizationFailure.OFFLINE -> ContentLifecycleFailure.OFFLINE
                OrganizationFailure.STALE -> ContentLifecycleFailure.STALE
                OrganizationFailure.UNCONFIRMED -> ContentLifecycleFailure.UNCONFIRMED
                else -> ContentLifecycleFailure.UNKNOWN
            }
        else -> contentLifecycleSdkFailure(error)
    }
