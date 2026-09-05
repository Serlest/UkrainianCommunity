package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import org.junit.Assert.*
import org.junit.Test

/** Transport allowlist only. It does not grant actor/target permission or invoke a callable. */
class PlatformRoleCallableProtocolTest {
    private val names = listOf("assignAppAdmin", "removeAppAdmin")

    @Test
    fun twoExactExistingRoleCallablesUseTheLocalTransportOnly() {
        names.forEach { name ->
            assertEquals(
                "http://10.0.2.2:5008/demo-uac-android/europe-west3/$name",
                LocalCallableProtocol.endpoint(name),
            )
        }
    }

    @Test
    fun bothRoleCallsAppendRecordsAndAreNotIdempotent() {
        names.forEach { assertTrue(LocalCallableProtocol.nonIdempotent(it)) }
    }

    @Test
    fun noRoleActionReceivesTheLargerMediaBudgetOrDeletionDeadline() {
        names.forEach { name ->
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(name))
            val error =
                assertThrows(LocalCallableException::class.java) {
                    LocalCallableProtocol.request(name, mapOf("reason" to "x".repeat(65_536)))
                }
            assertEquals(LocalCallableFailure.INVALID_ARGUMENT, error.code)
        }
    }

    @Test
    fun roleTransportCannotSelectCloudForeignRegionOrAnotherPort() {
        names.forEach { name ->
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, project = "uac-android-test-20260903")
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, project = "ukrainiancommunity-dbd5f")
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, host = "cloudfunctions.net")
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, region = "us-central1")
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, port = 443)
            }
        }
    }

    @Test
    fun adjacentRoleBulkAndInjectedOperationsRemainForbidden() {
        for (name in
            listOf(
                "changeUserRole",
                "transferAppOwnership",
                "assignAppModerator",
                "assignAppAdmin/",
                "../removeAppAdmin",
                "warnAllUsers",
                "restoreUserV2",
                "deleteAnyAccount",
                "warnUser/",
                "../banUser",
                "suspendUser?retry=true",
                "deactivateUser#fragment",
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name)
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.request(name, emptyMap<String, String>())
            }
        }
    }

    @Test
    fun uncertainTransportAfterBodyStartNeverBecomesAnOrdinaryRetryableFailure() {
        names.forEach { name ->
            for (failure in
                listOf(
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED,
                    LocalCallableFailure.INTERNAL,
                    LocalCallableFailure.DATA_LOSS,
                    LocalCallableFailure.UNKNOWN,
                )) {
                assertEquals(
                    LocalCallableFailure.UNCONFIRMED,
                    LocalCallableProtocol.transportFailure(name, true, failure),
                )
                assertEquals(failure, LocalCallableProtocol.transportFailure(name, false, failure))
            }
            assertEquals(
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.PERMISSION_DENIED,
                ),
            )
        }
    }
}
