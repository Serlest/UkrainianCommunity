package at.uac.android.feature.attendees

import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.tr

@Composable
fun AttendeesAccessPanel(
    model: AttendeesAccessViewModel,
    content: Content,
    session: AttendeesSession?,
    language: String,
    currentTarget: () -> Boolean,
    onOpen: (String) -> Unit,
) {
    if (content.kind != ContentKind.EVENTS) return
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state = stored.forSession(session, content.id)
    val confirmedTarget = currentTarget()
    LifecycleResumeEffect(session, content.id, confirmedTarget) {
        if (confirmedTarget) model.show(content.id) else model.hide()
        onPauseOrDispose { model.hide() }
    }
    if (
        confirmedTarget &&
            state.visible &&
            state.permitted &&
            !state.checking &&
            session?.ready == true
    ) {
        TextButton(
            onClick = {
                if (currentTarget() && model.canOpen(content.id, session)) onOpen(content.id)
            },
            modifier = Modifier.testTag("attendees-open"),
        ) {
            Text(tr(language, "Teilnehmende ansehen", "Переглянути учасників"))
        }
    }
}
