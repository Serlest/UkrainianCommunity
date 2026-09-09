package at.uac.android

import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.announcements.AnnouncementContract
import at.uac.android.feature.announcements.AnnouncementDraft
import at.uac.android.feature.announcements.AnnouncementException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Build72AnnouncementContractTest {
    private fun publicItem(change: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        mapOf(
            "id" to "release_notice",
            "schemaVersion" to 1,
            "revision" to 2,
            "title" to mapOf("uk" to "Заголовок", "de" to "Titel"),
            "body" to mapOf("uk" to "Текст", "de" to "Text"),
            "mode" to "acknowledge",
            "feedback" to true,
            "status" to "published",
            "startsAt" to 1_800_000_000_000L,
            "expiresAt" to 1_800_086_400_000L,
        ) + change

    @Test
    fun platformScopedFeedAcceptsPrivacyProjectionWithoutInventingAudience() {
        val page =
            AnnouncementContract.parsePage(
                mapOf(
                    "items" to listOf(publicItem()),
                    "serverNow" to 1_800_000_000_001L,
                    "cursor" to null,
                )
            )
        assertEquals(1, page.items.size)
        assertEquals(listOf("android"), page.items.single().targetPlatforms)
        assertTrue(page.items.single().groups.isEmpty())
        assertTrue(page.items.single().userIds.isEmpty())
    }

    @Test
    fun ownerProjectionStillRequiresExplicitValidTargetsAndAudienceFields() {
        val owner =
            publicItem(
                mapOf(
                    "groups" to listOf("registered"),
                    "userIds" to emptyList<String>(),
                    "regions" to listOf("wien"),
                )
            )
        org.junit.Assert.assertThrows(AnnouncementException::class.java) {
            AnnouncementContract.parse(owner)
        }
        val parsed = AnnouncementContract.parse(owner + ("targetPlatforms" to listOf("ios", "android")))
        assertEquals(listOf("wien"), parsed.regions)
        assertFalse(parsed.valid().not())
        org.junit.Assert.assertThrows(AnnouncementException::class.java) {
            AnnouncementContract.parse(owner + mapOf("targetPlatforms" to listOf("android"), "groups" to listOf("root")))
        }
    }

    @Test
    fun draftSupportsSpecificUsersAndEnforcesTheNinetyDayWindow() {
        val now = 1_800_000_000_000L
        val draft =
            AnnouncementDraft(
                id = "specific_user",
                titleUk = "Заголовок",
                titleDe = "Titel",
                bodyUk = "Текст",
                bodyDe = "Text",
                groups = emptySet(),
                userIds = setOf("account_1"),
                targetPlatforms = setOf("android"),
                startsAt = now,
                expiresAt = now + 86_400_000L,
            )
        assertTrue(draft.publishable(now))
        assertEquals(listOf("account_1"), draft.payload()["userIds"])
        assertFalse(draft.copy(expiresAt = now + 91 * 86_400_000L).publishable(now))
    }

    @Test
    fun announcementAndTranslationCallablesAreExactAndMutationsFailClosed() {
        val reads = listOf("getAnnouncements")
        val mutations =
            listOf(
                "acknowledgeAnnouncement",
                "registerAnnouncementDevice",
                "manageAnnouncements",
                "translateContent",
            )
        (reads + mutations).forEach {
            assertTrue(LocalCallableProtocol.endpoint(it).endsWith("/$it"))
        }
        mutations.forEach {
            assertTrue(LocalCallableProtocol.nonIdempotent(it))
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(
                    it,
                    requestStarted = true,
                    failure = LocalCallableFailure.UNAVAILABLE,
                ),
            )
        }
    }
}
