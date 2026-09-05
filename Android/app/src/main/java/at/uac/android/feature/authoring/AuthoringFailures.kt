package at.uac.android.feature.authoring

import at.uac.android.feature.organization.OrganizationException
import at.uac.android.feature.organization.OrganizationFailure

/**
 * Kept outside the Firestore source to avoid initializing Android-backed SDK enum tables in pure
 * tests.
 */
fun authoringFailure(error: Throwable): AuthoringFailure =
    when (error) {
        is AuthoringException -> error.failure
        is OrganizationException ->
            when (error.failure) {
                OrganizationFailure.SIGN_IN -> AuthoringFailure.SIGN_IN
                OrganizationFailure.NOT_READY -> AuthoringFailure.NOT_READY
                OrganizationFailure.DENIED -> AuthoringFailure.DENIED
                OrganizationFailure.INVALID -> AuthoringFailure.INVALID
                OrganizationFailure.MISSING -> AuthoringFailure.MISSING
                OrganizationFailure.STALE -> AuthoringFailure.STALE
                OrganizationFailure.OFFLINE -> AuthoringFailure.OFFLINE
                OrganizationFailure.UNCONFIRMED -> AuthoringFailure.UNCONFIRMED
                else -> AuthoringFailure.UNKNOWN
            }
        else -> authoringSdkFailure(error)
    }
