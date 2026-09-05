package at.uac.android.feature.inbox

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.feedback.feedbackScope
import java.time.Instant

@Composable
fun InboxPopupDestination(
    state: InboxPopupState,
    language: String,
    auth: AuthStore,
    popup: InboxPopupViewModel,
    browse: BrowseViewModel,
    canInteract: Boolean = true,
    canStillInteract: () -> Boolean = { true },
) {
    val account = state.account
    var external by remember(account) { mutableStateOf<String?>(null) }
    fun current() =
        canInteract &&
            canStillInteract() &&
            account.session != null &&
            auth.state.value.inboxPopupAccount() == account
    LaunchedEffect(account, state.action?.sequence, canInteract) {
        // Do not consume a queued destination while a newer status has not recomposed yet.
        if (!current()) return@LaunchedEffect
        val action = state.action?.let { popup.takeAction(it.sequence) } ?: return@LaunchedEffect
        if (!current()) return@LaunchedEffect
        val live = auth.state.value
        when (
            val target =
                resolveInboxNavigation(
                    action.notice,
                    action.destination,
                    action.session,
                    live.inboxScope(),
                    live.feedbackScope()?.canManage == true,
                    Instant.now(),
                )
        ) {
            is InboxNavigationTarget.Route -> {
                if (target.publicContent) browse.preference("mode", "emulator")
                browse.navigate(target.path)
            }
            is InboxNavigationTarget.External -> external = target.url
            null -> Unit
        }
    }
    if (canInteract)
        InboxPopupHost(
            state,
            language,
            onDismiss = { if (current()) popup.dismiss(it) },
            onOpen = { if (current()) popup.dismiss(it, open = true) },
            onClearError = { if (current()) popup.clearError() },
            onInbox = { if (current()) browse.navigate("profile/inbox") },
            destinationAvailable = ::availableInboxDestination,
        )
    external
        ?.takeIf { current() }
        ?.let { url ->
            InboxExternalConfirmation(url, language, canOpen = ::current) { external = null }
        }
}
