package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.time.Instant
import java.util.Locale
import org.junit.Assert.*
import org.junit.Test

class FeedbackInboxSelectionTest {
    private val time = Instant.parse("2026-09-03T17:00:00.123456789Z")
    private val actor = FeedbackSession("author-id", 1, true, false, "Émilie Müller")

    private fun item(id: String = "target-id", extra: Map<String, Any?> = emptyMap()) =
        FeedbackContract.item(
            RawDocument(
                id,
                FeedbackContract.creation(
                    id,
                    actor,
                    FeedbackDraft(message = "Вітаю! Wien, Café."),
                    time,
                ) + extra,
            )
        )

    private fun page(items: List<FeedbackItem>) =
        FeedbackPage(items, FeedbackCursor(time, "source-cursor"), true, 2)

    private fun select(
        items: List<FeedbackItem>,
        query: String = "",
        filter: FeedbackInboxFilter = FeedbackInboxFilter.ALL,
        sort: FeedbackInboxSort = FeedbackInboxSort.NEWEST,
        language: String = "de",
    ) =
        FeedbackInboxSelector.select(
            page(items),
            FeedbackInboxOptions(query, filter, sort),
            language,
        )

    @Test
    fun defaultsMatchOpenNewestWithoutAStoredQuery() {
        assertEquals(
            FeedbackInboxOptions("", FeedbackInboxFilter.OPEN, FeedbackInboxSort.NEWEST),
            FeedbackInboxOptions(),
        )
    }

    @Test
    fun statusGroupsPreserveLegacyAliasesAndKeepUnknownSeparate() {
        val items = FeedbackStatus.entries.map { item(it.name).copy(status = it) }
        assertEquals(
            listOf("OPEN"),
            select(items, filter = FeedbackInboxFilter.OPEN).items.map { it.id },
        )
        assertEquals(
            setOf("ANSWERED", "REVIEWED"),
            select(items, filter = FeedbackInboxFilter.ANSWERED).items.map { it.id }.toSet(),
        )
        assertEquals(
            setOf("ARCHIVED", "CLOSED"),
            select(items, filter = FeedbackInboxFilter.CLOSED).items.map { it.id }.toSet(),
        )
        assertEquals(
            listOf("UNKNOWN"),
            select(items, filter = FeedbackInboxFilter.UNKNOWN).items.map { it.id },
        )
        assertEquals(6, select(items).items.size)
    }

    @Test
    fun countsAreLoadedStatusCountsNotSearchResultCounts() {
        val result =
            select(listOf(item("a"), item("b").copy(status = FeedbackStatus.CLOSED)), "no-match")
        assertTrue(result.items.isEmpty())
        assertEquals(2, result.loadedCount)
        assertEquals(2, result.counts[FeedbackInboxFilter.ALL])
        assertEquals(1, result.counts[FeedbackInboxFilter.OPEN])
        assertEquals(1, result.counts[FeedbackInboxFilter.CLOSED])
        assertTrue(result.hasMore)
        assertEquals(2, result.invalidCount)
    }

    @Test
    fun queryUsesAndAcrossAuthorIdTypeBodyPreviewAndRecordId() {
        val row = item(extra = mapOf("lastMessageText" to "Spätere Antwort"))
        for (query in
            listOf(
                "emilie author frage cafe spatere target",
                "ВІТАЮ wien",
                "author-id",
                "target-id",
            )) assertEquals(listOf(row), select(listOf(row), query).items)
        assertTrue(select(listOf(row), "wien missingword").items.isEmpty())
    }

    @Test
    fun tokensMatchSubstringsAndPunctuationIsASeparatorNotRegex() {
        val row = item()
        assertEquals(listOf(row), select(listOf(row), "mull [caf].* (wi)").items)
        assertEquals(listOf(row), select(listOf(row), " ; --- \n\t ").items)
        assertTrue(select(listOf(row), "a|z").items.isEmpty())
    }

    @Test
    fun caseDiacriticWidthAndCombiningFormsMatchWithoutChangingText() {
        val row = item()
        for (query in listOf("ＥＭＩＬＩＥ ＣＡＦＥ", "E\u0301milie cafe\u0301", "MÜLLER")) assertEquals(
            listOf(row),
            select(listOf(row), query).items,
        )
        assertEquals("Émilie Müller", row.name)
        assertEquals("Вітаю! Wien, Café.", row.message)
    }

    @Test
    fun searchIsIndependentOfDeviceDefaultLocale() {
        val old = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"))
            assertEquals(1, select(listOf(item()), "WIEN EMILIE").items.size)
        } finally {
            Locale.setDefault(old)
        }
    }

    @Test
    fun localizedTypeTitleUsesSelectedLanguage() {
        assertEquals(1, select(listOf(item()), "питання", language = "uk").items.size)
        assertTrue(select(listOf(item()), "frage", language = "uk").items.isEmpty())
        assertEquals(1, select(listOf(item()), "frage", language = "de").items.size)
        assertEquals(1, select(listOf(item()), "target", language = "uk").items.size)
    }

    @Test
    fun unknownTypeDoesNotCrashOrGainAnInventedSearchLabel() {
        val row = item(extra = mapOf("type" to "future-kind"))
        assertNull(row.type)
        assertEquals(listOf(row), select(listOf(row), "cafe").items)
        assertTrue(select(listOf(row), "future-kind").items.isEmpty())
    }

    @Test
    fun nonSearchableSubjectAndLegalCaseAreNotSilentlyAdded() {
        val row =
            item(
                extra =
                    mapOf(
                        "subject" to "SUBJECTONLY",
                        "dsaCase" to mapOf("caseNumber" to "CASEONLY"),
                    )
            )
        assertTrue(select(listOf(row), "SUBJECTONLY").items.isEmpty())
        assertTrue(select(listOf(row), "CASEONLY").items.isEmpty())
    }

    @Test
    fun lastMessageActivityOverridesUpdatedAndCreatedTimes() {
        val olderCreation =
            item("a")
                .copy(
                    createdAt = time.minusSeconds(100),
                    updatedAt = time.minusSeconds(100),
                    lastMessageAt = time.plusNanos(1),
                )
        val newerCreation =
            item("b")
                .copy(createdAt = time.plusSeconds(100), updatedAt = time, lastMessageAt = null)
        assertEquals(
            listOf("a", "b"),
            select(listOf(newerCreation, olderCreation)).items.map { it.id },
        )
        assertEquals(
            listOf("b", "a"),
            select(listOf(newerCreation, olderCreation), sort = FeedbackInboxSort.OLDEST)
                .items
                .map { it.id },
        )
    }

    @Test
    fun nanosAndIdTiesHaveStableTotalOrderInBothDirections() {
        val rows = listOf(item("b"), item("a"), item("c").copy(lastMessageAt = time.plusNanos(1)))
        assertEquals(listOf("c", "a", "b"), select(rows).items.map { it.id })
        assertEquals(
            listOf("a", "b", "c"),
            select(rows.reversed(), sort = FeedbackInboxSort.OLDEST).items.map { it.id },
        )
    }

    @Test
    fun activityParserKeepsExactNanosAndLegacyFallback() {
        assertEquals(time, item().lastMessageAt)
        val fields =
            FeedbackContract.creation("old", actor, FeedbackDraft(message = "old"), time) -
                "lastMessageAt"
        val old = FeedbackContract.item(RawDocument("old", fields - "updatedAt"))
        assertNull(old.lastMessageAt)
        assertEquals(time, old.updatedAt)
        assertEquals(
            time.plusNanos(1),
            item(extra = mapOf("lastMessageAt" to time.plusNanos(1))).lastMessageAt,
        )
    }

    @Test
    fun malformedActivityIsRejectedRatherThanSilentlyMisordered() {
        for (invalid in listOf("yesterday", 123L, true)) {
            val error = runCatching {
                item(extra = mapOf("lastMessageAt" to invalid))
            }
                .exceptionOrNull()
            assertTrue(error is FeedbackException)
            assertEquals(FeedbackFailure.INVALID, (error as FeedbackException).failure)
        }
    }

    @Test
    fun sourceCursorHasMoreInvalidAndOrderAreNeverModifiedBySelection() {
        val rows = listOf(item("b"), item("a"))
        val original = page(rows)
        val cursor = original.next
        val result =
            FeedbackInboxSelector.select(
                original,
                FeedbackInboxOptions("no-match", sort = FeedbackInboxSort.OLDEST),
                "uk",
            )
        assertTrue(result.items.isEmpty())
        assertSame(cursor, original.next)
        assertEquals(time.nano, original.next!!.createdAt.nano)
        assertEquals(listOf("b", "a"), original.items.map { it.id })
        assertTrue(original.hasMore)
        assertEquals(2, original.invalid)
    }

    @Test
    fun loadingMoreCanRevealMatchesWithoutClaimingAnEarlierGlobalEmptyResult() {
        val first = page(listOf(item("a")))
        val options = FeedbackInboxOptions("newer-reply", FeedbackInboxFilter.ALL)
        val initially = FeedbackInboxSelector.select(first, options, "de")
        assertTrue(initially.items.isEmpty())
        assertTrue(initially.hasMore)
        val more =
            first.copy(
                items = first.items + item("b").copy(preview = "newer-reply"),
                hasMore = false,
            )
        val later = FeedbackInboxSelector.select(more, options, "de")
        assertEquals(listOf("b"), later.items.map { it.id })
        assertFalse(later.hasMore)
        assertEquals(2, later.invalidCount)
    }

    @Test
    fun nullAndEmptyPagesHaveNoFabricatedItemsOrCounts() {
        for (page in listOf(null, FeedbackPage(emptyList(), null, false))) {
            val result = FeedbackInboxSelector.select(page, FeedbackInboxOptions(), "de")
            assertTrue(result.items.isEmpty())
            assertTrue(result.counts.values.all { it == 0 })
            assertEquals(0, result.loadedCount)
        }
    }

    @Test
    fun queryBoundsRejectWithoutTruncatingUnicode() {
        assertTrue(FeedbackInboxSelector.validQuery("a".repeat(200)))
        assertTrue(FeedbackInboxSelector.validQuery("🙂".repeat(100)))
        for (value in listOf("a".repeat(201), "🙂".repeat(101), "\uD800", "\uDC00")) {
            assertFalse(FeedbackInboxSelector.validQuery(value))
            assertTrue(runCatching { select(listOf(item()), value) }.isFailure)
        }
    }

    @Test
    fun diagnosticStringsNeverExposeQueryOrPrivateRows() {
        val options = FeedbackInboxOptions("PRIVATE SEARCH")
        val text =
            options.toString() + FeedbackInboxSelector.select(page(listOf(item())), options, "de")
        for (secret in
            listOf("PRIVATE SEARCH", "Émilie", "Café", "author-id", "target-id")) assertFalse(
            text.contains(secret)
        )
    }
}
