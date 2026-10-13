package at.uac.android

import at.uac.android.feature.featuredmanagement.*
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class FeaturedManagementContractTest {
    private val owner = ModerationSession("owner-1", 7, "owner", true)

    private fun draft(id: String = "banner-1") = FeaturedDraft(
        id = id,
        localizations = mapOf("uk" to FeaturedLocalized("Допомога", "Поруч"), "de" to FeaturedLocalized("Hilfe", "In der Nähe")),
        imageUrl = "https://example.org/banner.jpg",
        action = FeaturedAction.EVENT,
        actionTargetId = "event-1",
        sections = setOf(FeaturedSection.HOME, FeaturedSection.EVENTS),
        priority = 9,
    )

    @Test fun exactBuild68PayloadAndActionValidation() {
        val payload = FeaturedManagementContract.payload(draft())
        assertEquals(setOf("id", "localizations", "imageURL", "actionType", "actionTargetID", "regionScope", "visibleSections", "displayDurationSeconds", "priority", "isActive"), payload.keys)
        assertEquals(listOf("events", "home"), payload["visibleSections"])
        assertEquals("event", payload["actionType"])
        assertFails(FeaturedFailure.INVALID) { FeaturedManagementContract.validate(draft().copy(actionTargetId = "")) }
        assertFails(FeaturedFailure.INVALID) { FeaturedManagementContract.validate(draft().copy(action = FeaturedAction.EXTERNAL_URL, actionTargetId = "", externalUrl = "javascript:alert(1)")) }
    }

    @Test fun onlyReadyOwnerCanManage() {
        FeaturedManagementContract.requireOwner(owner)
        assertFails(FeaturedFailure.ACCESS) { FeaturedManagementContract.requireOwner(owner.copy(role = "admin")) }
        assertFails(FeaturedFailure.ACCESS) { FeaturedManagementContract.requireOwner(owner.copy(ready = false)) }
    }

    @Test fun staleUpdateIsRejectedBeforeMutation() = runTest {
        val value = banner(draft(), 1)
        val source = FakeSource(value.copy(version = value.version.copy(updatedAt = Instant.ofEpochSecond(2))))
        val repository = FeaturedManagementRepository(source) { owner }
        assertFailsSuspend(FeaturedFailure.CONFLICT) { repository.save(owner, draft(), value.version) }
        assertEquals(0, source.saves)
    }

    @Test fun createIsReadBackConfirmedAndSentOnce() = runTest {
        val source = FakeSource(null)
        val repository = FeaturedManagementRepository(source) { owner }
        val result = repository.save(owner, draft(), null)
        assertEquals("banner-1", result.id)
        assertEquals(1, source.saves)
        assertEquals(3L, result.version.updatedAt.epochSecond)
    }

    @Test fun callableFailureIsNeverRetriedOrReportedAsSuccess() = runTest {
        val source = FakeSource(null, failSave = true)
        val repository = FeaturedManagementRepository(source) { owner }
        assertFailsSuspend(FeaturedFailure.UNCONFIRMED) { repository.save(owner, draft(), null) }
        assertEquals(1, source.saves)
    }

    private fun banner(value: FeaturedDraft, second: Long) = FeaturedBanner(
        value,
        FeaturedVersion(value.id, Instant.ofEpochSecond(second), FeaturedManagementContract.fingerprint(value)),
        Instant.EPOCH,
        "owner-1",
        "owner-1",
    )

    private class FakeSource(var current: FeaturedBanner?, val failSave: Boolean = false) : FeaturedManagementSource {
        var saves = 0
        override suspend fun list(session: ModerationSession) = listOfNotNull(current)
        override suspend fun find(session: ModerationSession, id: String) = current
        override suspend fun save(session: ModerationSession, draft: FeaturedDraft, create: Boolean): FeaturedReceipt {
            saves++
            if (failSave) throw FeaturedException(FeaturedFailure.UNCONFIRMED)
            val receipt = FeaturedReceipt(draft.id, Instant.ofEpochSecond(3))
            current = FeaturedBanner(draft, FeaturedVersion(draft.id, receipt.updatedAt, FeaturedManagementContract.fingerprint(draft)), Instant.EPOCH, session.uid, session.uid)
            return receipt
        }
        override suspend fun setActive(session: ModerationSession, id: String, active: Boolean) = error("unused")
        override suspend fun delete(session: ModerationSession, id: String) = error("unused")
        override suspend fun upload(session: ModerationSession, bannerId: String, jpeg: ByteArray) = error("unused")
    }

    private fun assertFails(reason: FeaturedFailure, block: () -> Unit) {
        assertEquals(reason, assertThrows(FeaturedException::class.java, block).failure)
    }

    private suspend fun assertFailsSuspend(reason: FeaturedFailure, block: suspend () -> Unit) {
        try { block(); fail("Expected $reason") } catch (error: FeaturedException) { assertEquals(reason, error.failure) }
    }
}
