package at.uac.android.feature.owneranalytics

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class OwnerAnalyticsState(
    val period: AnalyticsPeriod = AnalyticsPeriod.TODAY,
    val loading: Boolean = false,
    val snapshot: OwnerAnalyticsSnapshot? = null,
    val detail: AnalyticsDetail? = null,
    val detailTarget: Pair<String, String>? = null,
    val search: String = "",
    val failure: OwnerAnalyticsFailure? = null,
)

class OwnerAnalyticsViewModel(private val repository: OwnerAnalyticsRepository) : ViewModel() {
    private val mutable = MutableStateFlow(OwnerAnalyticsState())
    val state = mutable.asStateFlow()
    private var job: Job? = null

    fun load(session: OwnerAnalyticsSession?, force: Boolean = false) {
        if (session?.ready != true) {
            job?.cancel()
            mutable.value = OwnerAnalyticsState(failure = OwnerAnalyticsFailure.ACCESS)
            return
        }
        if (
            !force &&
                mutable.value.snapshot?.period == mutable.value.period &&
                mutable.value.failure == null
        )
            return
        job?.cancel()
        val period = mutable.value.period
        job = viewModelScope.launch {
            mutable.value = mutable.value.copy(loading = true, failure = null)
            try {
                val result = repository.overview(session, period)
                mutable.value =
                    mutable.value.copy(loading = false, snapshot = result, failure = null)
            } catch (error: CancellationException) {
                throw error
            } catch (error: OwnerAnalyticsException) {
                mutable.value = mutable.value.copy(loading = false, failure = error.failure)
            }
        }
    }

    fun period(value: AnalyticsPeriod, session: OwnerAnalyticsSession?) {
        if (mutable.value.period == value) return
        mutable.value =
            mutable.value.copy(period = value, snapshot = null, detail = null, detailTarget = null)
        load(session, true)
    }

    fun search(value: String) {
        mutable.value = mutable.value.copy(search = value.take(100))
    }

    fun open(session: OwnerAnalyticsSession?, type: String, id: String) {
        if (session?.ready != true) return
        job?.cancel()
        val period = mutable.value.period
        job = viewModelScope.launch {
            mutable.value =
                mutable.value.copy(
                    loading = true,
                    failure = null,
                    detailTarget = type to id,
                    detail = null,
                )
            try {
                val result = repository.detail(session, period, type, id)
                mutable.value = mutable.value.copy(loading = false, detail = result, failure = null)
            } catch (error: CancellationException) {
                throw error
            } catch (error: OwnerAnalyticsException) {
                mutable.value = mutable.value.copy(loading = false, failure = error.failure)
            }
        }
    }

    fun closeDetail() {
        job?.cancel()
        mutable.value =
            mutable.value.copy(detail = null, detailTarget = null, failure = null, loading = false)
    }

    fun filteredTop(): List<AnalyticsTopItem> {
        val query = mutable.value.search.trim().lowercase(Locale.ROOT)
        return mutable.value.snapshot?.top.orEmpty().filter {
            query.isEmpty() ||
                it.title.lowercase(Locale.ROOT).contains(query) ||
                it.type.contains(query)
        }
    }

    fun filteredRegions(): List<AnalyticsRegion> {
        val query = mutable.value.search.trim().lowercase(Locale.ROOT)
        return mutable.value.snapshot?.regions.orEmpty().filter {
            query.isEmpty() || it.id.lowercase(Locale.ROOT).contains(query)
        }
    }
}
