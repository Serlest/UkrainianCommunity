package at.uac.android

import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.foundation.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FoundationTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun model(
        emulator: FoundationRepository = SyntheticFoundationRepository(),
        save: (String) -> Unit = {},
    ) = FoundationViewModel(SyntheticFoundationRepository(), emulator, "de", save)

    @Test
    fun productionAndOtherHostsAreRejected() {
        LocalEnvironment.requireSafe()
        for (project in listOf("ukrainiancommunity-dbd5f", "demo-other", "")) {
            assertThrows(IllegalArgumentException::class.java) {
                LocalEnvironment.requireSafe(project)
            }
        }
        for (host in listOf("googleapis.com", "localhost", "10.0.2.2.evil.test")) {
            assertThrows(IllegalArgumentException::class.java) {
                LocalEnvironment.requireSafe(host = host)
            }
        }
    }

    @Test
    fun syntheticContentLoadsWithoutNetwork() = runTest {
        val vm = model()
        assertEquals(LoadState.Loading, vm.state.value.load)
        advanceUntilIdle()
        assertTrue(vm.state.value.load is LoadState.Ready)
    }

    @Test
    fun languageChangesContentImmediatelyAndPersists() = runTest {
        var saved = ""
        val vm = model(save = { saved = it })
        advanceUntilIdle()
        vm.selectLanguage("uk")
        assertEquals("uk", saved)
        assertEquals(
            "Разом в Австрії",
            (vm.state.value.load as LoadState.Ready).content.title.resolve(vm.state.value.language),
        )
    }

    @Test
    fun errorRetriesAndRecovers() = runTest {
        var fail = true
        val vm =
            model(
                object : FoundationRepository {
                    override suspend fun load(): FoundationContent {
                        if (fail) error("local unavailable")
                        return SyntheticFoundationRepository().load()
                    }
                }
            )
        vm.selectMode(DataMode.EMULATOR)
        advanceUntilIdle()
        assertEquals(LoadState.Unavailable, vm.state.value.load)
        fail = false
        vm.reload()
        advanceUntilIdle()
        assertTrue(vm.state.value.load is LoadState.Ready)
    }

    @Test
    fun timeoutIsVisible() = runTest {
        val vm =
            model(
                object : FoundationRepository {
                    override suspend fun load(): FoundationContent {
                        delay(20_000)
                        return SyntheticFoundationRepository().load()
                    }
                }
            )
        vm.selectMode(DataMode.EMULATOR)
        advanceUntilIdle()
        assertEquals(LoadState.Unavailable, vm.state.value.load)
    }

    @Test
    fun switchingSourceCancelsStaleResult() = runTest {
        val vm =
            model(
                object : FoundationRepository {
                    override suspend fun load(): FoundationContent {
                        delay(4_000)
                        error("stale failure")
                    }
                }
            )
        vm.selectMode(DataMode.EMULATOR)
        runCurrent()
        vm.selectMode(DataMode.SYNTHETIC)
        advanceUntilIdle()
        assertEquals(DataMode.SYNTHETIC, vm.state.value.mode)
        assertTrue(vm.state.value.load is LoadState.Ready)
    }

    @Test
    fun malformedAndPrivateFixturesFailClosed() {
        assertThrows(InvalidFixtureException::class.java) { decodeFoundationFixture(emptyMap()) }
        assertThrows(InvalidFixtureException::class.java) {
            decodeFoundationFixture(mapOf("moderationStatus" to "pendingReview"))
        }
        assertThrows(InvalidFixtureException::class.java) {
            decodeFoundationFixture(
                mapOf(
                    "moderationStatus" to "approved",
                    "localizations" to mapOf("de" to mapOf("title" to "missing body")),
                )
            )
        }
    }

    @Test
    fun deniedAccessIsNotReportedAsOffline() = runTest {
        val vm =
            model(
                object : FoundationRepository {
                    override suspend fun load(): FoundationContent =
                        throw FixtureAccessDeniedException()
                }
            )
        vm.selectMode(DataMode.EMULATOR)
        advanceUntilIdle()
        assertEquals(LoadState.AccessDenied, vm.state.value.load)
    }
}
