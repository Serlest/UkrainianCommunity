package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Build68CallableProtocolTest {
  private val reads = listOf("getOrganizationAccess", "getLegalEvidencePage")
  private val mutations =
      listOf(
          "updateOrganizationInfo",
          "saveOrganizationPhoto",
          "updateAnalyticsConsentV2",
          "updateAnalyticsConsent",
      )

  @Test
  fun onlyExactBuild68EndpointsAreEnabled() {
    (reads + mutations).forEach { assertTrue(LocalCallableProtocol.endpoint(it).endsWith("/$it")) }
  }

  @Test
  fun mutationsNeverBecomeOrdinaryRetriesAfterSubmission() {
    mutations.forEach { name ->
      assertTrue(LocalCallableProtocol.nonIdempotent(name))
      assertEquals(
          LocalCallableFailure.UNCONFIRMED,
          LocalCallableProtocol.transportFailure(name, true, LocalCallableFailure.UNAVAILABLE),
      )
      assertEquals(
          LocalCallableFailure.UNAVAILABLE,
          LocalCallableProtocol.transportFailure(name, false, LocalCallableFailure.UNAVAILABLE),
      )
    }
    reads.forEach { assertFalse(LocalCallableProtocol.nonIdempotent(it)) }
  }

  @Test
  fun onlyPhotoReceivesMediaBudgetAndDeadline() {
    assertEquals(
        4 * 1_024 * 1_024,
        LocalCallableProtocol.maximumRequestBytes("saveOrganizationPhoto"),
    )
    assertEquals(120_000, LocalCallableProtocol.maximumTimeoutMillis("saveOrganizationPhoto"))
    listOf(
            "getOrganizationAccess",
            "updateOrganizationInfo",
            "updateAnalyticsConsentV2",
            "updateAnalyticsConsent",
            "getLegalEvidencePage",
        )
        .forEach {
          assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(it))
          assertEquals(60_000, LocalCallableProtocol.maximumTimeoutMillis(it))
        }
  }

  @Test
  fun photoTransportRejectsShapeAndBase64BeforeDispatch() {
    val valid =
        mapOf(
            "principalId" to "user",
            "organizationId" to "org",
            "photoId" to "photo",
            "operationId" to "operation",
            "expectedImageURL" to null,
            "imageBase64" to "/9j/2Q==",
            "caption" to null,
            "clientVersion" to "1.0.2",
        )
    LocalCallableProtocol.request("saveOrganizationPhoto", valid)
    org.junit.Assert.assertThrows(LocalCallableException::class.java) {
      LocalCallableProtocol.request("saveOrganizationPhoto", valid + ("extra" to true))
    }
    org.junit.Assert.assertThrows(LocalCallableException::class.java) {
      LocalCallableProtocol.request(
          "saveOrganizationPhoto",
          valid + ("imageBase64" to "not base64"),
      )
    }
  }
}
