package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.moderation.ModerationContract
import at.uac.android.feature.moderation.ModerationKind
import at.uac.android.feature.moderation.ModerationTarget
import at.uac.android.feature.organizationreview.OrganizationReviewContract
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class OrganizationReviewPreviewIntegrationTest {
    private val id = "synthetic-preview-organization"
    private val time = Instant.parse("2026-09-03T00:00:00.123456789Z")

    private fun fields() =
        mapOf<String, Any?>(
            "id" to id,
            "name" to "Original",
            "description" to "Synthetic description",
            "moderationStatus" to "pendingReview",
            "submittedByUserId" to "synthetic-applicant",
            "createdAt" to time,
            "updatedAt" to time,
        )

    private fun preview(values: Map<String, Any?>) =
        ModerationContract.preview(
            ModerationTarget(ModerationKind.ORGANIZATION, id),
            RawDocument(id, values),
        )

    @Test
    fun organizationPreviewBindsTheExactRawFieldsNotTrimmedDisplayText() {
        val first = fields()
        val whitespace = first + ("name" to " Original ")
        assertEquals(preview(first).item.title, preview(whitespace).item.title)
        assertEquals(
            OrganizationReviewContract.fingerprint(id, first),
            preview(first).organizationReviewFingerprint,
        )
        assertNotEquals(
            preview(first).organizationReviewFingerprint,
            preview(whitespace).organizationReviewFingerprint,
        )
        assertNull(preview(first).reviewVersion)
    }

    @Test
    fun displayedRawFingerprintPreservesTimestampNanoseconds() {
        assertNotEquals(
            preview(fields()).organizationReviewFingerprint,
            preview(fields() + ("updatedAt" to time.plusNanos(1))).organizationReviewFingerprint,
        )
    }

    @Test
    fun unsupportedRawTypeKeepsReadablePreviewButCannotEnableMutation() {
        val result = preview(fields() + ("unknownLegacyField" to Any()))
        assertEquals("Original", result.item.title.base)
        assertNull(result.organizationReviewFingerprint)
        assertNull(result.reviewVersion)
    }

    @Test
    fun approvedOrganizationRemainsReadOnlyEvenWhenOtherFieldsAreValid() {
        val result = preview(fields() + ("moderationStatus" to "approved"))
        assertEquals("approved", result.item.status)
        assertNull(result.organizationReviewFingerprint)
        assertNull(result.reviewVersion)
    }
}
