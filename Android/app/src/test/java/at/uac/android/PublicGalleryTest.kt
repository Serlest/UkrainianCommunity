package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.ReadFailure
import at.uac.android.feature.publicgallery.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class PublicGalleryTest {
    private val time = Instant.parse("2026-09-03T05:00:00Z")

    private fun row(id: String = "photo-1", extra: Map<String, Any?> = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "imageURL" to "https://example.invalid/$id?token=not-for-logs",
                "caption" to "  Public caption  ",
                "uploadedBy" to "not-a-displayed-profile",
                "createdAt" to time,
            ) + extra,
        )

    private fun window(rows: List<RawDocument> = listOf(row())) =
        PublicGalleryProjection.window(rows, null, null)

    @Test
    fun freshProjectionPreservesBackendOrderAndContainsOnlyDisplayFields() {
        val result = window(listOf(row("z"), row("a")))
        assertEquals(listOf("z", "a"), result.photos.map { it.id })
        assertEquals("Public caption", result.photos.first().caption)
        assertNull(result.cachedAt)
        assertNull(result.failure)
        assertFalse(result.truncated)
        assertFalse(result.toString().contains("not-a-displayed-profile"))
    }

    @Test
    fun latestWindowNeverExceedsThirtyAndDoesNotClaimCompleteOverflow() {
        assertEquals(30, window((1..30).map { row("photo-$it") }).photos.size)
        assertFalse(window((1..30).map { row("photo-$it") }).truncated)
        val result = window((1..100).map { row("photo-$it") })
        assertEquals(30, result.photos.size)
        assertTrue(result.truncated)
        assertEquals("photo-30", result.photos.last().id)
    }

    @Test
    fun duplicateVisibleDocumentIdsFailClosedInsteadOfAliasingPagerPages() {
        val result = window(listOf(row(), row(extra = mapOf("imageURL" to "different"))))
        assertTrue(result.photos.isEmpty())
        assertEquals(ReadFailure.INVALID, result.failure)
    }

    @Test
    fun requiredWireFieldsCannotBeInventedByUi() {
        for (extra in
            listOf(
                mapOf("imageURL" to 5),
                mapOf("uploadedBy" to null),
                mapOf("createdAt" to "yesterday"),
            )) {
            val result = window(listOf(row(extra = extra)))
            assertEquals(ReadFailure.INVALID, result.failure)
            assertTrue(result.photos.isEmpty())
        }
    }

    @Test
    fun opaqueDocumentIdDoesNotRequireNewManagementUuidGrammar() {
        assertEquals("legacy.photo 1", window(listOf(row("legacy.photo 1"))).photos.single().id)
        for (id in listOf("", " ", "path/other", "unsafe\nname")) {
            assertEquals(ReadFailure.INVALID, window(listOf(row(id))).failure)
        }
    }

    @Test
    fun optionalCaptionRemainsOptionalAndNoFallbackUploaderOrPrivateFieldsAreAdded() {
        for (caption in listOf(null, "   ", 9)) assertNull(
            window(listOf(row(extra = mapOf("caption" to caption)))).photos.single().caption
        )
        val result =
            window(
                listOf(
                    row(
                        extra =
                            mapOf(
                                "email" to "private@example.invalid",
                                "bio" to "Private biography",
                            )
                    )
                )
            )
        assertFalse(result.toString().contains("private@example.invalid"))
        assertFalse(result.toString().contains("Private biography"))
    }

    @Test
    fun nonNetworkFailuresNeverResurrectIncomingStaleRows() {
        for (failure in ReadFailure.entries.filter { it != ReadFailure.OFFLINE }) {
            val result = PublicGalleryProjection.window(listOf(row()), time, failure)
            assertTrue(result.photos.isEmpty())
            assertNull(result.cachedAt)
            assertEquals(failure, result.failure)
        }
    }

    @Test
    fun offlineRowsNeedAnExplicitCacheTimestamp() {
        assertTrue(
            PublicGalleryProjection.window(listOf(row()), null, ReadFailure.OFFLINE)
                .photos
                .isEmpty()
        )
        val result = PublicGalleryProjection.window(listOf(row()), time, ReadFailure.OFFLINE)
        assertEquals(1, result.photos.size)
        assertEquals(time, result.cachedAt)
        assertEquals(ReadFailure.OFFLINE, result.failure)
    }

    @Test
    fun successfulCacheResultKeepsItsVisibleAge() {
        val result = PublicGalleryProjection.window(listOf(row()), time, null)
        assertEquals(time, result.cachedAt)
        assertEquals(1, result.photos.size)
    }

    @Test
    fun selectedIdRequiresCurrentDisplayPermissionAndMembership() {
        val window = window()
        assertEquals("photo-1", PublicGalleryProjection.selected(window, "photo-1", true)?.id)
        assertNull(PublicGalleryProjection.selected(window, "photo-1", false))
        assertNull(PublicGalleryProjection.selected(window, "removed", true))
        assertNull(PublicGalleryProjection.selected(window, null, true))
    }

    @Test
    fun currentRowWinsAndRemovedPhotoNeverReturnsOldUrl() {
        val changed = window(listOf(row(extra = mapOf("imageURL" to "current-local-object"))))
        assertEquals(
            "current-local-object",
            PublicGalleryProjection.selected(changed, "photo-1", true)?.imageUrl,
        )
        assertNull(PublicGalleryProjection.selected(window(emptyList()), "photo-1", true))
    }

    @Test
    fun gridUsesOnlyTwoOrThreeColumnsAtExactIosBoundary() {
        for (width in listOf(-1f, 0f, 329.99f, Float.NaN, Float.POSITIVE_INFINITY)) assertEquals(
            2,
            PublicGalleryProjection.columns(width),
        )
        for (width in listOf(330f, 500f, 2000f)) assertEquals(
            3,
            PublicGalleryProjection.columns(width),
        )
    }

    @Test
    fun urlPolicyIsNotReimplementedOrExpandedByProjection() {
        // The existing PublicImage/Policy rejects this URL without contacting it; projection adds
        // no loader.
        assertEquals(
            "file:///private/image",
            window(listOf(row(extra = mapOf("imageURL" to "file:///private/image"))))
                .photos
                .single()
                .imageUrl,
        )
    }

    @Test
    fun publicModelDiagnosticsDoNotExposeCaptionOrDownloadToken() {
        val diagnostic = window().toString()
        assertFalse(diagnostic.contains("Public caption"))
        assertFalse(diagnostic.contains("not-for-logs"))
        assertFalse(diagnostic.contains("https://"))
    }
}
