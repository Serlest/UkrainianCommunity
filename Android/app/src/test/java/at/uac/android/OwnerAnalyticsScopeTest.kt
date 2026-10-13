package at.uac.android

import at.uac.android.feature.owneranalytics.*
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OwnerAnalyticsScopeTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    @Test
    fun accountRevisionChangeCannotReuseCachedOverview() = runTest {
        var reads = 0
        val source =
            object : OwnerAnalyticsRepository {
                override suspend fun overview(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                ): OwnerAnalyticsSnapshot {
                    reads++
                    return OwnerAnalyticsSnapshot(
                        period,
                        Instant.EPOCH,
                        emptyMap(),
                        emptyMap(),
                        emptyList(),
                        emptyList(),
                        emptyList(),
                        AnalyticsUsers(),
                    )
                }

                override suspend fun detail(
                    session: OwnerAnalyticsSession,
                    period: AnalyticsPeriod,
                    type: String,
                    id: String,
                ): AnalyticsDetail = error("unused")
            }
        val model = OwnerAnalyticsViewModel(source)
        val first = OwnerAnalyticsSession("first", 1, true)
        model.load(first)
        advanceUntilIdle()
        assertEquals(1, reads)
        model.load(first)
        advanceUntilIdle()
        assertEquals(1, reads)
        model.bind(null)
        assertNull(model.state.value.snapshot)
        model.load(first.copy(revision = 2))
        advanceUntilIdle()
        assertEquals(2, reads)
        assertEquals(2L, model.state.value.session?.revision)
    }
}
