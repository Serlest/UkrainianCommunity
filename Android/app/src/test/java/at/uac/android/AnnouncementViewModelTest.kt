package at.uac.android

import at.uac.android.feature.announcements.AnnouncementLocalStore
import at.uac.android.feature.announcements.AnnouncementPage
import at.uac.android.feature.announcements.AnnouncementSession
import at.uac.android.feature.announcements.AnnouncementSource
import at.uac.android.feature.announcements.AnnouncementText
import at.uac.android.feature.announcements.AnnouncementViewModel
import at.uac.android.feature.announcements.UserAnnouncement
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AnnouncementViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun item(mode: String = "once") =
        UserAnnouncement(
            "notice", 1, 1,
            AnnouncementText("Заголовок", "Titel"),
            AnnouncementText("Текст", "Text"),
            emptyList(), emptyList(), emptyList(), listOf("android"),
            mode, true, false, 100, 1_000, "published", null, null,
        )

    private class MemoryStore : AnnouncementLocalStore {
        override val secret = "a".repeat(96)
        override var guestPushEnabled = false
        val marks = mutableSetOf<Pair<String, String>>()
        val pending = mutableMapOf<String, Boolean>()
        override fun presented(id: String) = id to "presented" in marks
        override fun acknowledged(id: String) = id to "acknowledged" in marks
        override fun mark(id: String, event: String) { marks += id to event }
        override fun pending(id: String, event: String, scope: String, value: Boolean) {
            pending["$scope:$event:$id"] = value
        }
        override fun pendingEvents(scope: String) = pending.filter { it.key.startsWith("$scope:") && it.value }
            .keys.map { key -> key.substringAfterLast(':') to key.substringAfter("$scope:").substringBefore(':') }
        override fun scope(uid: String?) = uid ?: "guest"
    }

    private class FakeSource(private val item: UserAnnouncement) : AnnouncementSource {
        val events = mutableListOf<Pair<String, String>>()
        override suspend fun installationId() = "c123456789012345678901"
        override suspend fun feed(cursor: String?) = AnnouncementPage(listOf(item), 200, null)
        override suspend fun event(id: String, event: String, secret: String?) { events += id to event }
        override suspend fun register(secret: String, fid: String, language: String) = Unit
        override suspend fun confirm(secret: String, challenge: String) = Unit
        override suspend fun disable(secret: String) = Unit
        override suspend fun manage(operation: String, values: Map<String, Any?>): Any? = emptyMap<String, Any>()
    }

    @Test
    fun guestOnceAnnouncementIsPresentedOnlyOncePerSession() = runTest(dispatcher) {
        val source = FakeSource(item())
        val model = AnnouncementViewModel(source, MemoryStore())
        model.configure(AnnouncementSession(null, 1, available = true, ready = true, owner = false))
        model.refresh(present = true)
        advanceUntilIdle()
        assertSame(model.state.value.items.single(), model.state.value.active)
        model.dismiss()
        model.presentIfPossible()
        advanceUntilIdle()
        assertNull(model.state.value.active)
        assertEquals(listOf("notice" to "presented"), source.events)
    }

    @Test
    fun acknowledgementRecordsPresentedAndAcknowledgedWithoutLosingFeed() = runTest(dispatcher) {
        val source = FakeSource(item("acknowledge"))
        val model = AnnouncementViewModel(source, MemoryStore())
        model.configure(AnnouncementSession("account", 2, available = true, ready = true, owner = false))
        model.refresh(present = true)
        advanceUntilIdle()
        model.acknowledge()
        advanceUntilIdle()
        assertNull(model.state.value.active)
        assertEquals(listOf("notice" to "presented", "notice" to "acknowledged"), source.events)
        assertEquals(1, model.state.value.items.size)
    }
}
