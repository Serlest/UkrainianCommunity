package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.analyticsconsent.AnalyticsConsentV2
import at.uac.android.feature.analyticsconsent.AnalyticsConsentV2Contract
import at.uac.android.feature.analyticsconsent.analyticsConsentV2MayUseLegacy
import at.uac.android.feature.appupdate.AndroidRelease
import at.uac.android.feature.appupdate.AndroidUpdatePolicy
import at.uac.android.feature.appupdate.ReleaseVersion
import at.uac.android.feature.legalevidence.LegalEvidencePageContract
import at.uac.android.feature.organizationaccess.OrganizationAccessContract
import at.uac.android.feature.organizationaccess.OrganizationPhotoAttempt
import at.uac.android.feature.organizationaccess.OrganizationPhotoContract
import at.uac.android.feature.organizationaccess.OrganizationPhotoVersion
import at.uac.android.feature.organizationaccess.OrganizationUpdateAttempt
import at.uac.android.feature.organizationaccess.OrganizationVersion
import at.uac.android.feature.organizationaccess.recoverUnknownMutation
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Build68ContractTest {
  @Test
  fun organizationAccessIsPrincipalBoundAndFailClosed() {
    val raw =
        mapOf(
            "principalId" to "user",
            "schemaVersion" to 1,
            "policyVersion" to "organization-actions-v1",
            "mode" to "enforced",
            "actionModes" to mapOf("editInfo" to "enforced"),
            "commands" to mapOf("updateOrganizationInfo" to true, "saveOrganizationPhoto" to false),
            "records" to listOf(mapOf("organizationId" to "org", "actions" to listOf("editInfo"))),
        )
    val access = OrganizationAccessContract.accessResponse(raw, "user", setOf("org"), Instant.EPOCH)
    assertTrue(access.allows("org", "editInfo"))
    assertFalse(access.allows("other", "editInfo"))
    org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
      OrganizationAccessContract.accessResponse(raw, "other", setOf("org"), Instant.EPOCH)
    }
  }

  @Test
  fun organizationUpdateUsesRevisionAndCanConfirmUnknownResult() {
    val attempt =
        OrganizationUpdateAttempt(
            "user",
            "org",
            "operation",
            "10:20",
            "approved",
            mapOf("name" to "UAC"),
        )
    val request = OrganizationAccessContract.updateRequest(attempt, "1.0.2")
    assertEquals("10:20", request["expectedRevision"])
    assertTrue(
        OrganizationAccessContract.confirms(
            attempt,
            OrganizationVersion("org", "11:1", mapOf("name" to "UAC", "city" to "Wien")),
        )
    )
    assertFalse(
        OrganizationAccessContract.confirms(
            attempt,
            OrganizationVersion("org", "11:1", mapOf("name" to "Other")),
        )
    )
    org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
      OrganizationAccessContract.updateRequest(
          attempt.copy(fields = mapOf("moderationStatus" to "approved")),
          "1.0.2",
      )
    }
  }

  @Test
  fun photoContractBindsRecoveryToImmutableOperationPath() {
    val jpeg = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xd9.toByte())
    val attempt = OrganizationPhotoAttempt("user", "org", "photo", "operation", null, jpeg, null)
    assertNotNull(OrganizationPhotoContract.request(attempt, "1.0.2")["imageBase64"])
    val digest =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest("user\u0000operation".toByteArray())
            .joinToString("") { "%02x".format(it) }
    assertTrue(
        OrganizationPhotoContract.confirms(
            attempt,
            OrganizationPhotoVersion(
                "org",
                "photo",
                "https://host/o/organizations%2Forg%2FphotoVersions%2F$digest.jpg?token=x",
            ),
        )
    )
    assertFalse(
        OrganizationPhotoContract.confirms(
            attempt,
            OrganizationPhotoVersion("org", "photo", "https://host/old.jpg"),
        )
    )
  }

  @Test
  fun unknownMutationReconcilesThenReplaysSameOperationAtMostOnce() = runTest {
    var dispatches = 0
    var reads = 0
    val recovered =
        recoverUnknownMutation(
            dispatch = {
              dispatches++
              if (dispatches == 1) throw LocalCallableException(LocalCallableFailure.UNCONFIRMED)
              "receipt"
            },
            read = {
              reads++
              null as String?
            },
            confirms = { null },
        )
    assertEquals("receipt", recovered)
    assertEquals(2, dispatches)
    assertEquals(1, reads)

    dispatches = 0
    reads = 0
    val readBack =
        recoverUnknownMutation(
            dispatch = {
              dispatches++
              throw LocalCallableException(LocalCallableFailure.UNCONFIRMED)
            },
            read = {
              reads++
              "committed"
            },
            confirms = { "read-receipt" },
        )
    assertEquals("read-receipt", readBack)
    assertEquals(1, dispatches)
    assertEquals(1, reads)
  }

  @Test
  fun consentV2CarriesExactPublishedVersionsAndPrincipal() {
    val value =
        AnalyticsConsentV2(
            "user",
            true,
            "123e4567-e89b-12d3-a456-426614174000",
            "uk",
            "1.0.2",
            AnalyticsConsentV2Contract.PRIVACY_VERSION,
            AnalyticsConsentV2Contract.DISCLOSURE_VERSION,
        )
    val request = AnalyticsConsentV2Contract.request(value)
    assertEquals("user", request["principalId"])
    assertEquals("2026.12", request["privacyVersion"])
    assertTrue(
        AnalyticsConsentV2Contract.receipt(
            mapOf("enabled" to true, "consentID" to value.consentId),
            value,
        )
    )
    assertTrue(
        analyticsConsentV2MayUseLegacy(LocalCallableException(LocalCallableFailure.NOT_FOUND))
    )
    assertFalse(
        analyticsConsentV2MayUseLegacy(
            LocalCallableException(LocalCallableFailure.PERMISSION_DENIED)
        )
    )
  }

  @Test
  fun legalEvidencePageRejectsForeignIdentityAndAcceptsOpaqueCursor() {
    val raw =
        mapOf(
            "account" to
                mapOf(
                    "userId" to "user",
                    "displayName" to null,
                    "email" to null,
                    "createdAt" to "2026-09-04T10:00:00.000Z",
                ),
            "events" to
                listOf(
                    mapOf(
                        "id" to "event",
                        "userId" to "user",
                        "eventType" to "termsAccepted",
                        "occurredAt" to "2026-09-04T10:00:00.000Z",
                        "source" to "registration",
                    )
                ),
            "nextCursor" to "opaque",
            "generatedAt" to "2026-09-04T10:01:00.000Z",
        )
    assertEquals("opaque", LegalEvidencePageContract.page(raw, "user").nextCursor)
    org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
      LegalEvidencePageContract.page(raw, "other")
    }
  }

  @Test
  fun androidUpdatePolicyUsesNumericVersionsAndFixedPackageUri() {
    assertTrue(ReleaseVersion.parse("1.2")!! > ReleaseVersion.parse("1.1.9")!!)
    val update =
        AndroidUpdatePolicy.available(
            "1.0.2",
            36,
            "at.uac.android",
            AndroidRelease("at.uac.android", "1.1", 26, true),
        )
    assertEquals("market://details?id=at.uac.android", update?.storeUri)
    assertNull(
        AndroidUpdatePolicy.available(
            "1.1",
            36,
            "at.uac.android",
            AndroidRelease("at.uac.android", "1.1", 26, true),
        )
    )
    assertNull(
        AndroidUpdatePolicy.available(
            "1.0",
            25,
            "at.uac.android",
            AndroidRelease("at.uac.android", "2.0", 26, true),
        )
    )
  }
}
