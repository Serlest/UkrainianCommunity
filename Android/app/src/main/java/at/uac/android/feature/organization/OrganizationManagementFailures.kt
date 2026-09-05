package at.uac.android.feature.organization

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure

/**
 * Pure protocol/domain cases must not initialize Android-backed Firestore enum tables in JVM tests.
 */
fun organizationManagementFailure(error: Throwable): OrganizationManagementFailure =
    when (error) {
        is OrganizationManagementException -> error.failure
        is OrganizationException ->
            when (error.failure) {
                OrganizationFailure.SIGN_IN -> OrganizationManagementFailure.SIGN_IN
                OrganizationFailure.NOT_READY -> OrganizationManagementFailure.NOT_READY
                OrganizationFailure.DENIED -> OrganizationManagementFailure.DENIED
                OrganizationFailure.INVALID -> OrganizationManagementFailure.INVALID
                OrganizationFailure.STALE -> OrganizationManagementFailure.STALE
                OrganizationFailure.MISSING -> OrganizationManagementFailure.MISSING
                OrganizationFailure.OFFLINE -> OrganizationManagementFailure.OFFLINE
                OrganizationFailure.UNCONFIRMED -> OrganizationManagementFailure.UNCONFIRMED
                else -> OrganizationManagementFailure.UNKNOWN
            }
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> OrganizationManagementFailure.DENIED
                LocalCallableFailure.FAILED_PRECONDITION,
                LocalCallableFailure.NOT_FOUND -> OrganizationManagementFailure.TARGET_UNAVAILABLE
                LocalCallableFailure.INVALID_ARGUMENT -> OrganizationManagementFailure.INVALID
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> OrganizationManagementFailure.OFFLINE
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableFailure.DATA_LOSS -> OrganizationManagementFailure.UNCONFIRMED
                else -> OrganizationManagementFailure.UNKNOWN
            }
        else -> organizationManagementSdkFailure(error)
    }
