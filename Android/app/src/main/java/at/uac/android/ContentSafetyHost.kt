package at.uac.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import at.uac.android.feature.browse.BrowseState
import at.uac.android.feature.personal.PersonalListPage
import at.uac.android.feature.personal.PersonalState
import at.uac.android.feature.safety.SafetyActions
import at.uac.android.feature.safety.SafetyReportDialog
import at.uac.android.feature.safety.SafetyReportTarget
import at.uac.android.feature.safety.SafetyState
import at.uac.android.feature.safety.SafetyViewModel
import at.uac.android.feature.safety.SafetyVisibility

/**
 * A render-time projection prevents a stale frame without destroying the public source snapshot.
 */
fun BrowseState.visibleTo(visibility: SafetyVisibility): BrowseState =
    copy(
        data =
            data.copy(
                items = data.items.filter(visibility::allows),
                detail = data.detail?.takeIf(visibility::allows),
                related = data.related.filter(visibility::allows),
                profiles = data.profiles.filter { visibility.allowsAuthor(it.id) },
            )
    )

fun PersonalState.visibleTo(visibility: SafetyVisibility): PersonalState {
    fun PersonalListPage.project(): PersonalListPage {
        val kept = items.filter(visibility::allows)
        return copy(items = kept, unavailable = unavailable + items.size - kept.size)
    }
    return copy(
        saved = saved.mapValues { it.value.project() },
        subscriptions = subscriptions?.project(),
    )
}

/**
 * Every dialog callback rechecks the live account and server-confirmed target, not its old frame.
 */
@Composable
fun ContentSafetyTools(
    target: SafetyReportTarget,
    state: SafetyState,
    language: String,
    model: SafetyViewModel,
    current: () -> Boolean,
    onAccount: () -> Unit,
) {
    var reporting by remember(state.session, target.key) { mutableStateOf(false) }
    SafetyActions(
        target,
        state,
        language,
        onReport = { if (current()) reporting = true },
        onUserBlock = { id, blocked -> if (current()) model.setUser(id, blocked) },
        onOrganizationBlock = { id, blocked -> if (current()) model.setOrganization(id, blocked) },
        onAccount = onAccount,
    )
    if (reporting && current())
        SafetyReportDialog(
            target,
            state,
            language,
            onSubmit = { draft -> if (current()) model.submit(target, draft) },
            onDismiss = { reporting = false },
        )
}
