package at.uac.android

import at.uac.android.feature.legalmanagement.LegalDraftContract
import at.uac.android.feature.legalmanagement.LegalDraftInput
import at.uac.android.feature.legalmanagement.LegalLocale
import at.uac.android.feature.legalmanagement.ManagedLegalVersion
import at.uac.android.feature.legalevidence.EvidenceAccountsContract
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LegalManagementContractTest {
    private val document = ManagedLegalVersion("terms", "2026.14", 202614, "x", emptyMap(),
        null, null, "published")
    private val draft = LegalDraftInput("terms", "2026.15", 202615, "2026.14", null,
        mapOf("de" to LegalLocale("Titel", "Text\r\n"),
            "uk" to LegalLocale("Назва", "Текст")), "Änderung", "Зміна")

    @Test fun nextVersionAndIosSummary() {
        assertEquals("2026.15" to 202615L, LegalDraftContract.next(document))
        assertEquals("DE:Änderung\nUK:Зміна", LegalDraftContract.summary(draft))
        val payload = LegalDraftContract.payload(draft, "draft")
        assertEquals(true, payload["requiresAcceptance"])
        assertEquals("2026.14", payload["supersedesVersion"])
        assertEquals(64, (payload["contentHash"] as String).length)
        val locales = payload["locales"] as Map<*, *>
        assertEquals("Text", (locales["de"] as Map<*, *>)["contentMarkdown"])
    }

    @Test fun noMissingTranslationOrInvalidVersion() {
        assertThrows(Exception::class.java) {
            LegalDraftContract.requireValid(draft.copy(summaryUk = ""))
        }
        assertThrows(Exception::class.java) {
            LegalDraftContract.requireValid(draft.copy(versionNumber = 202616))
        }
        assertThrows(Exception::class.java) {
            LegalDraftContract.requireValid(draft.copy(locales = draft.locales - "uk"))
        }
        val unfinished = draft.copy(locales = draft.locales +
            ("de" to LegalLocale("", "")), summaryDe = "", summaryUk = "")
        LegalDraftContract.requireSaveable(unfinished)
        assertEquals(null, LegalDraftContract.payload(unfinished, "draft")["changeSummary"])
        assertThrows(Exception::class.java) { LegalDraftContract.requireValid(unfinished) }
    }

    @Test fun accountPageCursorAndSearchContract() {
        val raw = mapOf("accounts" to listOf(mapOf("userId" to "u1", "displayName" to "Anna",
            "email" to "anna@example.invalid", "createdAt" to "2026-10-14T10:00:00.000Z")),
            "nextCursor" to mapOf("userId" to "u1", "createdAt" to "2026-10-14T10:00:00.000Z",
                "seconds" to 1791972000, "nanoseconds" to 0), "totalMatches" to null)
        val page = EvidenceAccountsContract.decode(raw)
        assertEquals("u1", page.accounts.single().userId)
        assertEquals("u1", page.cursor?.userId)
        assertTrue(EvidenceAccountsContract.request("", page.cursor)["cursor"] is Map<*, *>)
        assertThrows(IllegalArgumentException::class.java) {
            EvidenceAccountsContract.request("a", null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            EvidenceAccountsContract.request("Anna", page.cursor)
        }
    }
}
