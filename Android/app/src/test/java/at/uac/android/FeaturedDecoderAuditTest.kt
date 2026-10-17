package at.uac.android

import at.uac.android.feature.featuredmanagement.FirebaseFeaturedManagementSource
import at.uac.android.feature.featuredmanagement.FeaturedSection
import com.google.firebase.Timestamp
import java.util.Date
import org.junit.Assert.*
import org.junit.Test

class FeaturedDecoderAuditTest {
    private fun fields(): Map<String, Any> = mapOf(
        "id" to "banner-audit", "createdBy" to "owner", "createdAt" to Timestamp(Date(1000)),
        "updatedAt" to Timestamp(Date(2000)), "imageURL" to "https://example.org/banner.jpg",
        "regionScope" to "allAustria", "actionType" to "none", "isActive" to false,
        "displayDurationSeconds" to 6, "priority" to 1,
        "visibleSections" to listOf("home", "events", "organizations", "directory"),
    )

    @Test fun allProductionPlacementsDecodeWithoutRepairOrLoss() {
        val banner = FirebaseFeaturedManagementSource.decode("banner-audit", fields())
        assertFalse(banner.repairRequired)
        assertEquals(FeaturedSection.entries.toSet(), banner.draft.sections)
    }

    @Test fun unsupportedAndMalformedFieldsCannotMasqueradeAsCleanFallbacks() {
        val changes = listOf(
            mapOf("visibleSections" to listOf("home", "futurePlacement")),
            mapOf("localizations" to mapOf("de" to 5)),
            mapOf("localizations" to mapOf("de" to mapOf("title" to 5))),
            mapOf("title" to "x".repeat(121)), mapOf("displayDurationSeconds" to "6"),
            mapOf("priority" to "1"), mapOf("isActive" to "false"), mapOf("startsAt" to "invalid"),
        )
        changes.forEach { change ->
            assertTrue(change.keys.toString(), FirebaseFeaturedManagementSource.decode("banner-audit", fields() + change).repairRequired)
        }
    }
}
