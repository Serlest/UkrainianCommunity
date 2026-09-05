package at.uac.android

import at.uac.android.feature.startup.*
import org.junit.Assert.*
import org.junit.Test

class StartupTest {
    @Test
    fun initialRestorationRemainsCoveredWithoutATimer() {
        var state = StartupState()
        repeat(100) { state = state.observe(restoring = true) }
        assertTrue(state.covered)
    }

    @Test
    fun firstRestorationCompletionIsImmediate() {
        assertFalse(StartupState().observe(restoring = false).covered)
    }

    @Test
    fun laterForegroundRefreshLoginAndLogoutNeverReopenStartup() {
        var state = StartupState().observe(restoring = false)
        for (restoring in listOf(true, false, false, true, false)) {
            state = state.observe(restoring)
            assertFalse(state.covered)
        }
    }

    @Test
    fun retainedViewModelKeepsLaunchLatchThroughHostRebinding() {
        val model = StartupViewModel()
        model.observe(true)
        assertTrue(model.state.value.covered)
        model.observe(false)
        assertFalse(model.state.value.covered)
        model.observe(true)
        assertFalse(model.state.value.covered)
    }

    @Test
    fun mediaNeverStartsWithoutBothForegroundPermissionAndSurface() {
        val policy = StartupPlaybackPolicy()
        assertNull(policy.update(false, false).startToken)
        assertNull(policy.update(false, true).startToken)
        assertNull(policy.update(true, false).startToken)
        assertNotNull(policy.update(true, true).startToken)
    }

    @Test
    fun repeatedUpdatesNeverCreateASecondPlayer() {
        val policy = StartupPlaybackPolicy()
        val token = policy.update(true, true).startToken!!
        repeat(10) { assertEquals(StartupPlaybackChange(), policy.update(true, true)) }
        assertTrue(policy.current(token))
    }

    @Test
    fun pauseReleasesAndRejectsPreparedCallbackFromOldPlayer() {
        val policy = StartupPlaybackPolicy()
        val first = policy.update(true, true).startToken!!
        assertTrue(policy.update(false, true).release)
        assertFalse(policy.current(first))
        assertFalse(policy.update(false, true).release)
        val second = policy.update(true, true).startToken!!
        assertNotEquals(first, second)
        assertFalse(policy.current(first))
        assertTrue(policy.current(second))
    }

    @Test
    fun destroyedSurfaceReleasesAndNewSurfaceGetsNewGeneration() {
        val policy = StartupPlaybackPolicy()
        val first = policy.update(true, true).startToken!!
        assertTrue(policy.update(true, false).release)
        assertFalse(policy.current(first))
        val second = policy.update(true, true).startToken!!
        assertNotEquals(first, second)
        assertTrue(policy.current(second))
    }

    @Test
    fun codecOrAssetFailureRemainsStaticWithoutAutomaticRetry() {
        val policy = StartupPlaybackPolicy()
        val token = policy.update(true, true).startToken!!
        assertTrue(policy.fail(token))
        assertFalse(policy.current(token))
        for (allowed in listOf(true, false, true)) assertNull(
            policy.update(allowed, true).startToken
        )
    }

    @Test
    fun obsoleteErrorCannotStopReplacementPlayer() {
        val policy = StartupPlaybackPolicy()
        val first = policy.update(true, true).startToken!!
        policy.update(false, true)
        val second = policy.update(true, true).startToken!!
        assertFalse(policy.fail(first))
        assertTrue(policy.current(second))
    }

    @Test
    fun disposingBeforePrepareIsTerminalAndIdempotent() {
        val policy = StartupPlaybackPolicy()
        val token = policy.update(true, true).startToken!!
        policy.close()
        policy.close()
        assertFalse(policy.current(token))
        assertFalse(policy.fail(token))
        assertNull(policy.update(true, true).startToken)
    }

    @Test
    fun originalPortraitIsAspectFitWithoutCroppingOrStretching() {
        val fit = startupAspectFit(1080, 2400, 1896, 4096)!!
        assertEquals(1f, fit.scaleX, .0001f)
        assertTrue(fit.scaleY < 1f)
        assertEquals(1896f / 4096f, 1080f * fit.scaleX / (2400f * fit.scaleY), .0001f)
    }

    @Test
    fun landscapeViewportPreservesTheWholeOriginalPortrait() {
        val fit = startupAspectFit(2400, 1080, 1896, 4096)!!
        assertEquals(1f, fit.scaleY, .0001f)
        assertTrue(fit.scaleX < 1f)
        assertEquals(1896f / 4096f, 2400f * fit.scaleX / (1080f * fit.scaleY), .0001f)
    }

    @Test
    fun invalidMetadataNeverProducesInvalidTransform() {
        assertNull(startupAspectFit(0, 10, 10, 10))
        assertNull(startupAspectFit(10, -1, 10, 10))
        assertNull(startupAspectFit(10, 10, 0, 10))
        assertNull(startupAspectFit(10, 10, 10, -1))
        assertEquals(
            StartupFit(1f, 1f),
            startupAspectFit(Int.MAX_VALUE, Int.MAX_VALUE, Int.MAX_VALUE, Int.MAX_VALUE),
        )
    }
}
