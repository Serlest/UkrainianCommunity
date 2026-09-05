package at.uac.android

import at.uac.android.core.ReminderNavigationViewModel
import at.uac.android.feature.reminders.ReminderTapRequest
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class ReminderNavigationTest {
    private fun request() =
        ReminderTapRequest(UUID.randomUUID().toString(), UUID.randomUUID().toString())

    @Test
    fun duplicateActivityIntentDoesNotRestartACompletedTap() {
        val model = ReminderNavigationViewModel()
        val request = request()
        model.offer(request)
        model.offer(request)
        assertEquals(request, model.state.value.pending)
        assertTrue(model.complete(request))
        model.offer(request)
        assertNull(model.state.value.pending)
    }

    @Test
    fun oldVerificationCannotConsumeOrReportAnErrorForANewerTap() {
        val model = ReminderNavigationViewModel()
        val first = request()
        val second = request()
        model.offer(first)
        model.offer(second)
        assertFalse(model.complete(first, unavailable = true))
        assertEquals(second, model.state.value.pending)
        assertFalse(model.state.value.unavailable)
        assertTrue(model.complete(second, unavailable = true))
        model.dismissNotice()
        assertFalse(model.state.value.unavailable)
    }

    @Test
    fun malformedAndDiscardedRequestsDoNotBecomePending() {
        val model = ReminderNavigationViewModel()
        model.offer(ReminderTapRequest("events/private", "token"))
        assertNull(model.state.value.pending)
        val old = request()
        val next = request()
        model.offer(old)
        model.offer(next)
        model.complete(next)
        model.offer(old)
        assertNull(model.state.value.pending)
    }

    @Test
    fun verifiedLocalTestHasADistinctDismissibleOutcomeWithoutAnUnavailableError() {
        val model = ReminderNavigationViewModel()
        val request = request()
        model.offer(request)
        assertTrue(model.complete(request, localTestOpened = true))
        assertTrue(model.state.value.localTestOpened)
        assertFalse(model.state.value.unavailable)
        model.dismissNotice()
        assertFalse(model.state.value.localTestOpened)
    }
}
