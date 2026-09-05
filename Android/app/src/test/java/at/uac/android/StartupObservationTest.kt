package at.uac.android

import at.uac.android.feature.startup.StartupViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class StartupObservationTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    @Test
    fun anAlreadyRestoredSessionNeverShowsAStartupFrame() = runTest {
        val model = StartupViewModel()
        model.observeSessions(MutableStateFlow(false))
        assertFalse(model.state.value.covered)
    }

    @Test
    fun sessionObservationEndsAtFirstCompletionAndCannotReopen() = runTest {
        val flow = MutableStateFlow(true)
        val model = StartupViewModel()
        model.observeSessions(flow)
        assertTrue(model.state.value.covered)
        flow.value = false
        runCurrent()
        assertFalse(model.state.value.covered)
        flow.value = true
        runCurrent()
        model.observeSessions(MutableStateFlow(true))
        assertFalse(model.state.value.covered)
    }

    @Test
    fun rebindingCannotLetAnObsoleteObservationDismissTheCurrentGate() = runTest {
        val obsolete = MutableStateFlow(true)
        val current = MutableStateFlow(true)
        val model = StartupViewModel()
        model.observeSessions(obsolete)
        model.observeSessions(current)
        obsolete.value = false
        runCurrent()
        assertTrue(model.state.value.covered)
        current.value = false
        runCurrent()
        assertFalse(model.state.value.covered)
    }
}
