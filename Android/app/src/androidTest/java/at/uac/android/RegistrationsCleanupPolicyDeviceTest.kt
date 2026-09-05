package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Deterministic policy only: no Firebase, transport, account, permission, or clock mutation. */
@RunWith(AndroidJUnit4::class)
class RegistrationsCleanupPolicyDeviceTest {
    @Test
    fun successAndAlreadyAbsentRequireIndependent404() {
        for (status in listOf(200, 204, 404)) assertEquals(
            RegistrationCleanupOutcome.CONFIRMED_ABSENT,
            RegistrationCleanupPolicy.evaluate(status, 404),
        )
    }

    @Test
    fun local500AndIndependent404RemainExplicitWarning() {
        assertEquals(
            RegistrationCleanupOutcome.CONFIRMED_ABSENT_WITH_WARNING,
            RegistrationCleanupPolicy.evaluate(500, 404),
        )
    }

    @Test
    fun noSuccessfulDeleteOr500CanReplaceAbsenceEvidence() {
        for (deleted in listOf(200, 204, 404, 500)) for (read in
            listOf(null, 200, 204, 400, 401, 403, 500, 503)) assertEquals(
            RegistrationCleanupOutcome.FAILED,
            RegistrationCleanupPolicy.evaluate(deleted, read),
        )
    }

    @Test
    fun otherClientServerAndRedirectErrorsFailEvenWhenAbsent() {
        for (status in
            listOf(
                null,
                0,
                301,
                307,
                400,
                401,
                403,
                409,
                412,
                429,
                501,
                502,
                503,
                504,
            )) assertEquals(
            RegistrationCleanupOutcome.FAILED,
            RegistrationCleanupPolicy.evaluate(status, 404),
        )
    }

    @Test
    fun deleteTransportFailureCannotBecomeAWarningOrSuccess() {
        for (status in listOf(null, 200, 404, 500)) assertEquals(
            RegistrationCleanupOutcome.FAILED,
            RegistrationCleanupPolicy.evaluate(status, 404, deleteTransportError = true),
        )
    }

    @Test
    fun readTransportFailureCannotBeAcceptedByItsPartialStatus() {
        for (status in listOf(200, 204, 404, 500)) assertEquals(
            RegistrationCleanupOutcome.FAILED,
            RegistrationCleanupPolicy.evaluate(status, 404, readTransportError = true),
        )
    }

    @Test
    fun bothTransportFailuresAreAlwaysUnconfirmed() {
        assertEquals(
            RegistrationCleanupOutcome.FAILED,
            RegistrationCleanupPolicy.evaluate(
                500,
                404,
                deleteTransportError = true,
                readTransportError = true,
            ),
        )
    }
}
