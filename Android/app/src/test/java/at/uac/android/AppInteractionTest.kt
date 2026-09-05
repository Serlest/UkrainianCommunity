package at.uac.android

import at.uac.android.core.AppInteractionViewModel
import org.junit.Assert.*
import org.junit.Test

class AppInteractionTest {
    @Test
    fun foregroundAndAnUncoveredFrameAreBothRequired() {
        val model = AppInteractionViewModel()
        val host = model.attach()
        model.rendered(host, true)
        assertFalse(model.interactive.value)
        model.resume(host)
        assertTrue(model.interactive.value)
        model.rendered(host, false)
        assertFalse(model.interactive.value)
        model.rendered(host, true)
        assertTrue(model.interactive.value)
        model.pause(host)
        assertFalse(model.interactive.value)
    }

    @Test
    fun replacementHostCannotInheritOrResurrectAnOldFrame() {
        val model = AppInteractionViewModel()
        val old = model.attach()
        model.resume(old)
        model.rendered(old, true)
        val next = model.attach()
        assertFalse(model.interactive.value)
        model.resume(old)
        model.rendered(old, true)
        assertFalse(model.interactive.value)
        model.resume(next)
        assertFalse(model.interactive.value)
        model.rendered(next, true)
        assertTrue(model.interactive.value)
    }

    @Test
    fun oldActivityTeardownCannotDisableTheNewCurrentHost() {
        val model = AppInteractionViewModel()
        val old = model.attach()
        val next = model.attach()
        model.resume(next)
        model.rendered(next, true)
        model.pause(old)
        model.detach(old)
        assertTrue(model.interactive.value)
        model.detach(next)
        assertFalse(model.interactive.value)
        model.resume(next)
        model.rendered(next, true)
        assertFalse(model.interactive.value)
    }
}
