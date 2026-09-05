package at.uac.android

import at.uac.android.feature.dsastatement.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DsaStatementViewModelTest {
    private val owner = DsaStatementSession("ordinary-author", 1, "synthetic-backend", true)
    private var authority: DsaStatementSession? = owner
    private var reads = 0
    private var operation: suspend (String) -> Any? = { wire(it) }

    private fun wire(id: String) =
        mapOf(
            "id" to id,
            "caseNumber" to "PRIVATE-CASE",
            "status" to "underReview",
            "sourceType" to "comment",
            "sourceId" to "PRIVATE-CONTENT",
            "decision" to null,
            "appealDecision" to null,
        )

    private fun model() =
        DsaStatementViewModel(
            DsaStatementSource { _, id ->
                reads++
                operation(id)
            },
            { authority },
            object : DsaStatementReadGate {
                override suspend fun <T> withSession(
                    session: DsaStatementSession,
                    action: suspend () -> T,
                ): T = withContext(NonCancellable) { action() }
            },
        )

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    @Test
    fun showReadsOnceAndRepeatedShowDoesNotReadAgain() = runTest {
        val m = model()
        m.show("report")
        advanceUntilIdle()
        m.show("report")
        advanceUntilIdle()
        assertEquals(1, reads)
        assertEquals("report", m.state.value.statement!!.id)
        assertFalse(m.state.value.loading)
    }

    @Test
    fun refreshClearsOldPrivateDataBeforeReadingAndBlocksDoubleTap() = runTest {
        val m = model()
        m.show("report")
        advanceUntilIdle()
        val release = CompletableDeferred<Unit>()
        operation = {
            release.await()
            wire(it)
        }
        m.refresh()
        m.refresh()
        runCurrent()
        assertNull(m.state.value.statement)
        assertTrue(m.state.value.loading)
        assertEquals(2, reads)
        release.complete(Unit)
        advanceUntilIdle()
        assertEquals("report", m.state.value.statement!!.id)
    }

    @Test
    fun hideClearsEverythingAndLateReadCannotRestoreIt() = runTest {
        val release = CompletableDeferred<Unit>()
        operation = {
            release.await()
            wire(it)
        }
        val m = model()
        m.show("report")
        runCurrent()
        m.hide("report")
        assertFalse(m.state.value.visible)
        assertNull(m.state.value.reportId)
        assertNull(m.state.value.statement)
        release.complete(Unit)
        advanceUntilIdle()
        assertNull(m.state.value.statement)
    }

    @Test
    fun switchingTargetsDiscardsOldNonCancellableReply() = runTest {
        val release = CompletableDeferred<Unit>()
        operation = {
            if (it == "first") release.await()
            wire(it)
        }
        val m = model()
        m.show("first")
        runCurrent()
        m.show("second")
        runCurrent()
        assertEquals("second", m.state.value.statement!!.id)
        release.complete(Unit)
        advanceUntilIdle()
        assertEquals("second", m.state.value.statement!!.id)
    }

    @Test
    fun delayedHideForAnotherTargetDoesNotClearCurrentPage() = runTest {
        val m = model()
        m.show("second")
        advanceUntilIdle()
        m.hide("first")
        assertTrue(m.state.value.visible)
        assertEquals("second", m.state.value.statement!!.id)
    }

    @Test
    fun sessionBindingClearsPrivateDataWithoutAutomaticFetch() = runTest {
        val m = model()
        m.show("report")
        advanceUntilIdle()
        authority = owner.copy(revision = 2)
        m.bind(authority)
        advanceUntilIdle()
        assertNull(m.state.value.statement)
        assertFalse(m.state.value.visible)
        assertEquals(1, reads)
    }

    @Test
    fun renderMaskIsImmediateBeforeObserverProcessesRevocation() = runTest {
        val m = model()
        m.show("report")
        advanceUntilIdle()
        for (next in
            listOf(
                null,
                owner.copy(uid = "other"),
                owner.copy(ready = false),
                owner.copy(backend = "other"),
            )) assertNull(m.state.value.forSession(next).statement)
        assertNotNull(m.state.value.forSession(owner).statement)
    }

    @Test
    fun offlineDeniedMissingAndInvalidNeverKeepOldDataOrRetry() = runTest {
        for (failure in DsaStatementFailure.entries) {
            val m = model()
            operation = { wire(it) }
            m.show("report")
            advanceUntilIdle()
            val before = reads
            operation = { throw DsaStatementException(failure) }
            m.refresh()
            advanceUntilIdle()
            assertEquals(failure, m.state.value.error)
            assertNull(m.state.value.statement)
            assertFalse(m.state.value.loading)
            assertEquals(before + 1, reads)
        }
    }

    @Test
    fun invalidIdShowsErrorWithoutReadOrEndlessLoading() = runTest {
        val m = model()
        m.show("wrong/path")
        advanceUntilIdle()
        assertEquals(DsaStatementFailure.INVALID, m.state.value.error)
        assertFalse(m.state.value.loading)
        assertEquals(0, reads)
    }

    @Test
    fun unreadyScopeDoesNotRead() = runTest {
        authority = owner.copy(ready = false)
        val m = model()
        m.show("report")
        advanceUntilIdle()
        assertEquals(DsaStatementFailure.ACCESS, m.state.value.error)
        assertEquals(0, reads)
    }

    @Test
    fun canceledReadCanBeRetriedExplicitlyAndDoesNotSpin() = runTest {
        val m = model()
        operation = { throw CancellationException("synthetic") }
        m.show("report")
        advanceUntilIdle()
        assertFalse(m.state.value.loading)
        assertNull(m.state.value.statement)
        assertEquals(1, reads)
        operation = { wire(it) }
        m.refresh()
        advanceUntilIdle()
        assertEquals(2, reads)
        assertNotNull(m.state.value.statement)
    }

    @Test
    fun stateDiagnosticsNeverPrintPrivateLabels() = runTest {
        val m = model()
        m.show("report")
        advanceUntilIdle()
        assertFalse(m.state.value.toString().contains("PRIVATE"))
        assertFalse(m.state.value.toString().contains("ordinary-author"))
    }
}
