package at.uac.android.design

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier

/** Account destinations share the host toolbar rather than drawing a second back arrow. */
val LocalEmbeddedNavigation = staticCompositionLocalOf { false }

@Composable
fun UacBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    if (LocalEmbeddedNavigation.current) {
        BackHandler { if (enabled) onClick() }
    } else {
        TextButton(onClick = onClick, modifier = modifier, enabled = enabled, content = content)
    }
}
