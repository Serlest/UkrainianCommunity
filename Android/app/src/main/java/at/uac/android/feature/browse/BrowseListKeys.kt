package at.uac.android.feature.browse

import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable

/** Records actual rendered keys, including headers, without duplicating the layout rules. */
internal class RecordingLazyListScope(
    private val target: LazyListScope,
    private val keys: MutableList<Any>,
) : LazyListScope by target {
    override fun item(key: Any?, contentType: Any?, content: @Composable LazyItemScope.() -> Unit) {
        keys += key ?: keys.size
        target.item(key, contentType, content)
    }

    override fun items(count: Int, key: ((Int) -> Any)?, contentType: (Int) -> Any?,
        itemContent: @Composable LazyItemScope.(Int) -> Unit) {
        val start = keys.size
        repeat(count) { index -> keys += key?.invoke(index) ?: start + index }
        target.items(count, key, contentType, itemContent)
    }
}

internal data class RenderedBrowseKeys(val data: BrowseData, val query: String, val keys: List<Any>)
