package at.uac.android

import at.uac.android.feature.donationsettings.*
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DonationSettingsTest {
    private val owner = ModerationSession("owner", 1, "owner", true)
    private val original = DonationSnapshot(DonationDraft(), Instant.EPOCH, true)

    private class Fake(var snapshot: DonationSnapshot) : DonationSettingsRepository {
        var saves = 0
        var failLoad = false
        var failSave = false

        override suspend fun load(session: ModerationSession): DonationSnapshot {
            if (failLoad) error("offline")
            return snapshot
        }

        override suspend fun save(
            session: ModerationSession,
            baseline: DonationSnapshot,
            draft: DonationDraft,
        ) {
            saves++
            if (failSave) error("lost response")
            snapshot = snapshot.copy(draft = draft, revision = Instant.EPOCH.plusSeconds(1))
        }
    }

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    @Test
    fun publicCardRetainsReadableFallbackWhenOwnerLeavesTextEmpty() {
        val card =
            at.uac.android.feature.browse.Donation(mapOf("titleUK" to " ", "buttonTitleDE" to ""))
        assertEquals("Підтримати проєкт", card.text("title", "uk"))
        assertEquals("Unterstützen", card.text("buttonTitle", "de"))
    }

    @Test
    fun normalizesHttpsAndRejectsUnsafeLinks() {
        assertEquals(
            "https://example.org/help",
            DonationDraft(url = " example.org/help ").normalized().url,
        )
        for (url in
            listOf(
                "http://example.org",
                "https://user:pass@example.org",
                "https://localhost",
                "javascript:alert(1)",
                "https://example.org/a b",
            )) assertFalse(url, DonationDraft(true, url).valid())
        assertFalse(DonationDraft(true).valid())
        assertTrue(DonationDraft(false).valid())
        assertTrue(DonationDraft(true, "https://example.org/help").valid())
    }

    @Test
    fun acknowledgedSaveWithFailedRefreshRetainsDraftAndNeverResends() = runTest {
        val source = Fake(original)
        val model = DonationSettingsViewModel(source)
        model.load(owner)
        advanceUntilIdle()
        val draft = DonationDraft(true, "example.org/help")
        model.edit(draft)
        source.failLoad = true
        model.save()
        advanceUntilIdle()
        assertTrue(model.state.value.saved)
        assertFalse(model.state.value.dirty)
        assertEquals(draft.normalized(), model.state.value.draft)
        assertEquals(DonationProblem.SAVED_REFRESH_FAILED, model.state.value.problem)
        model.save()
        advanceUntilIdle()
        assertEquals(1, source.saves)
        source.failLoad = false
        model.load(owner, true)
        advanceUntilIdle()
        assertFalse(model.state.value.needsReadback)
        assertEquals(1, source.saves)
    }

    @Test
    fun unknownSaveRequiresReadbackAndDirtyBackCanBeCancelled() = runTest {
        val source = Fake(original).apply { failSave = true }
        val model = DonationSettingsViewModel(source)
        model.load(owner)
        advanceUntilIdle()
        model.edit(DonationDraft(url = "https://example.org"))
        var leaves = 0
        model.requestLeave { leaves++ }
        assertTrue(model.state.value.confirmLeave)
        model.cancelLeave()
        assertEquals(0, leaves)
        assertTrue(model.state.value.dirty)
        model.save()
        advanceUntilIdle()
        model.save()
        advanceUntilIdle()
        assertEquals(1, source.saves)
        assertEquals(DonationProblem.UNCONFIRMED, model.state.value.problem)
        model.bind(null)
        assertNull(model.state.value.baseline)
        assertEquals(DonationDraft(), model.state.value.draft)
    }

    @Test
    fun unchangedBackDoesNotAskForDiscard() = runTest {
        val model = DonationSettingsViewModel(Fake(original))
        model.load(owner)
        advanceUntilIdle()
        var leaves = 0
        model.requestLeave { leaves++ }
        assertEquals(1, leaves)
        assertFalse(model.state.value.confirmLeave)
    }
}
