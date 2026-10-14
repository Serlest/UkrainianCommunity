package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import at.uac.android.design.UacTheme
import at.uac.android.feature.legalmanagement.*
import at.uac.android.feature.legalevidence.*
import at.uac.android.feature.moderation.ModerationSession
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class LegalManagementUiTest {
    @get:Rule val compose = createComposeRule()
    private val owner = ModerationSession("owner", 1, "owner", true)

    @Test fun ordinaryRoleCannotLoadLegalData() {
        var calls = 0
        val source = object : LegalManagementSource {
            override suspend fun load(session: ModerationSession): List<ManagedLegalDocument> { calls++; return emptyList() }
            override suspend fun save(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument { calls++; error("denied") }
            override suspend fun publish(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument { calls++; error("denied") }
        }
        compose.setContent { UacTheme("light") {
            LegalManagementScreen(ModerationSession("reader", 1, "user", true), "de", source, {})
        } }
        compose.onNodeWithTag("legal-management-denied").assertExists()
        compose.onNodeWithTag("legal-management-screen").assertDoesNotExist()
        assertEquals(0, calls)
    }

    @Test fun ownerMustSaveBilingualDraftBeforePublish() {
        val active = ManagedLegalVersion("terms", "2026.14", 202614, "active",
            mapOf("de" to LegalLocale("Titel", "Deutscher Volltext"),
                "uk" to LegalLocale("Назва", "Український повний текст")),
            null, null, "published")
        var current = ManagedLegalDocument(active, null)
        var saves = 0
        var publishes = 0
        val source = object : LegalManagementSource {
            override suspend fun load(session: ModerationSession) = listOf(current)
            override suspend fun save(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument {
                saves++
                val hash = LegalDraftContract.payload(input, "draft")["contentHash"] as String
                current = ManagedLegalDocument(active, ManagedLegalVersion("terms", input.version,
                    input.versionNumber, hash, input.locales, LegalDraftContract.summary(input),
                    input.supersedes, "draft"))
                return current
            }
            override suspend fun publish(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument {
                publishes++
                current = ManagedLegalDocument(current.draft!!.copy(status = "published"), null)
                return current
            }
        }
        compose.setContent { UacTheme("light") { LegalManagementScreen(owner, "de", source, {}) } }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("legal-management-open-terms").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("legal-management-open-terms").performClick()
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-summary-de"))
        compose.onNodeWithTag("legal-management-summary-de").performTextInput("Änderung")
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-summary-uk"))
        compose.onNodeWithTag("legal-management-summary-uk").performTextInput("Зміна")
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-publish"))
        compose.onNodeWithTag("legal-management-publish").assertIsNotEnabled()
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-save"))
        compose.onNodeWithTag("legal-management-save").performClick()
        compose.waitUntil(5_000) { saves == 1 }
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-publish"))
        compose.onNodeWithTag("legal-management-publish").assertIsEnabled().performClick()
        compose.onNodeWithTag("legal-management-confirm-publish").performClick()
        compose.waitUntil(5_000) { publishes == 1 }
        assertEquals("2026.15", current.active.version)
    }

    @Test fun evidenceListIsOwnerOnly() {
        var reads = 0
        val source = EvidenceAccountsSource { _, _ -> reads++; EvidenceAccountsPage(emptyList(), null, null) }
        compose.setContent { UacTheme("light") {
            LegalEvidenceAccountsScreen(ModerationSession("reader", 1, "user", true), "uk",
                source, {}, {})
        } }
        compose.onNodeWithTag("legal-evidence-accounts-denied").assertExists()
        assertEquals(0, reads)
    }

    @Test fun backSavesUnfinishedDraftWithoutPublishing() {
        val active = ManagedLegalVersion("terms", "2026.14", 202614, "active",
            mapOf("de" to LegalLocale("Titel", "Text"),
                "uk" to LegalLocale("Назва", "Текст")), null, null, "published")
        var current = ManagedLegalDocument(active, null)
        var saves = 0
        val source = object : LegalManagementSource {
            override suspend fun load(session: ModerationSession) = listOf(current)
            override suspend fun save(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument {
                saves++
                current = ManagedLegalDocument(active, ManagedLegalVersion("terms", input.version,
                    input.versionNumber,
                    LegalDraftContract.payload(input, "draft")["contentHash"] as String,
                    input.locales, LegalDraftContract.summary(input), input.supersedes, "draft"))
                return current
            }
            override suspend fun publish(session: ModerationSession, input: LegalDraftInput): ManagedLegalDocument {
                error("unfinished draft must not publish")
            }
        }
        compose.setContent { UacTheme("light") { LegalManagementScreen(owner, "de", source, {}) } }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("legal-management-open-terms").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("legal-management-open-terms").performClick()
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-title-de"))
        compose.onNodeWithTag("legal-management-title-de").performTextReplacement("")
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-publish"))
        compose.onNodeWithTag("legal-management-publish").assertIsNotEnabled()
        compose.onNodeWithTag("legal-management-screen")
            .performScrollToNode(hasTestTag("legal-management-back"))
        compose.onNodeWithTag("legal-management-back").performClick()
        compose.waitUntil(5_000) { saves == 1 }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag("legal-management-editor").fetchSemanticsNodes().isEmpty()
        }
        assertEquals("", current.draft!!.locales.getValue("de").title)
    }
}
