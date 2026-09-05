package at.uac.android.feature.personal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.feature.auth.AccountScreen
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.BrowseState
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.PrimaryTab
import at.uac.android.feature.browse.tr
import kotlinx.coroutines.CancellationException

class AuthPersonalMutationGate(private val auth: AuthStore) : PersonalMutationGate {
    override suspend fun <T> withSession(session: PersonalSession, operation: suspend () -> T): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Account scope changed")
            throw PersonalException(
                if (error.problem == AuthProblem.PERMISSION_DENIED) PersonalFailure.DENIED
                else PersonalFailure.UNKNOWN,
                error,
            )
        }
}

fun AuthSession.personalScope(): PersonalSession? {
    val identity = identity ?: return null
    val profile = profile ?: return null
    if (stage != AuthStage.AUTHENTICATED || identity.anonymous || profile.uid != identity.uid)
        return null
    return PersonalSession(profile.uid, identity.emailVerified, readyForActions, revision)
}

/**
 * The observer clears memory on the main dispatcher; this mask additionally prevents a stale UI
 * frame.
 */
fun PersonalState.forSession(authority: PersonalSession?): PersonalState =
    if (session == authority) this else PersonalState(session = authority)

@Composable
fun PersonalDestination(
    route: String,
    language: String,
    auth: AuthStore,
    state: PersonalState,
    personal: PersonalViewModel,
    browse: BrowseViewModel,
    visibilityNotice: (@Composable () -> Unit)? = null,
    avatarBusy: Boolean = false,
    avatarEditor: (@Composable (String, Boolean, (String) -> Unit) -> Unit)? = null,
    editor: PersonalProfileEditorViewModel? = null,
    supplementaryContent: (@Composable () -> Unit)? = null,
) {
    val authSession by auth.state.collectAsStateWithLifecycle()
    val captured = state.session
    fun current(): Boolean = captured != null && auth.state.value.personalScope() == captured
    // Lists own their LazyColumn. Never place them in another vertical scrolling container.
    if (captured?.ready == true && route == "profile/saved") {
        Column(Modifier.fillMaxSize()) {
            visibilityNotice?.invoke()
            Box(Modifier.weight(1f)) {
                PersonalSavedScreen(
                    state,
                    language,
                    { more -> if (current()) personal.loadSaved(more) },
                    browse::openPersonalContent,
                )
            }
        }
    } else if (captured?.ready == true && route == "profile/subscriptions") {
        Column(Modifier.fillMaxSize()) {
            visibilityNotice?.invoke()
            Box(Modifier.weight(1f)) {
                PersonalSubscriptionsScreen(
                    state,
                    language,
                    { more -> if (current()) personal.loadSubscriptions(more) },
                    browse::openPersonalContent,
                )
            }
        }
    } else {
        Column(
            Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .testTag("account-scroll")
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (route == "profile" && authSession.stage == AuthStage.GUEST) {
                GuestProfileContent(
                    language,
                    { browse.navigate("profile/login") },
                    { browse.navigate("profile/register") },
                    { destination ->
                        val tab = PrimaryTab.entries.firstOrNull { it.route == destination }
                        if (tab != null) {
                            browse.selectTab(tab)
                            browse.navigate(destination, true)
                        } else if (destination == "settings") {
                            browse.navigate("settings")
                        }
                    },
                )
            } else if (route == "profile/edit" && captured?.ready == true) {
                Column(Modifier.widthIn(max = 760.dp).fillMaxWidth()) {
                    PersonalProfilePanel(
                        state,
                        language,
                        { if (current()) personal.loadProfile() },
                        { draft -> if (current()) personal.saveProfile(draft) },
                        avatarBusy,
                        avatarEditor,
                        editor,
                    )
                }
            } else {
                AccountScreen(
                    auth,
                    language,
                    initialPage =
                        route.removePrefix("profile/").takeIf {
                            it in setOf("login", "register", "reset")
                        } ?: "login",
                    onNavigateAuth = { page -> browse.navigate("profile/$page") },
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        for ((destination, title) in
                            listOf(
                                "edit" to tr(language, "Profil bearbeiten", "Редагувати профіль"),
                                "saved" to
                                    tr(language, "Gespeicherte Inhalte", "Збережені матеріали"),
                                "subscriptions" to
                                    tr(language, "Meine Abonnements", "Мої підписки"),
                            )) OutlinedButton(
                            onClick = {
                                if (auth.state.value.readyForActions)
                                    browse.navigate("profile/$destination")
                            },
                            modifier = Modifier.fillMaxWidth().testTag("account-open-$destination"),
                        ) {
                            Text(title)
                        }
                    }
                }
                supplementaryContent?.invoke()
            }
        }
    }
}

@Composable
fun PersonalDetailActions(
    content: Content,
    browseState: BrowseState,
    state: PersonalState,
    auth: AuthStore,
    personal: PersonalViewModel,
    browse: BrowseViewModel,
    visible: (Content) -> Boolean = { true },
) {
    val language = browseState.language
    if (browseState.mode != "emulator") {
        Text(
            tr(
                language,
                "Eingebaute Beispiele sind schreibgeschützt. Wechsle zum lokalen Server, um persönliche Aktionen zu testen.",
                "Вбудовані приклади доступні лише для читання. Перейдіть на локальний сервер, щоб перевірити особисті дії.",
            ),
            Modifier.testTag("personal-synthetic-readonly"),
        )
        OutlinedButton(
            onClick = { browse.preference("mode", "emulator") },
            modifier = Modifier.testTag("personal-open-emulator"),
        ) {
            Text(
                tr(
                    language,
                    "Diesen Inhalt vom lokalen Server laden",
                    "Завантажити цей матеріал з локального сервера",
                )
            )
        }
    } else if (browseState.data.cachedAt != null || browseState.data.loading) {
        Text(
            tr(
                language,
                "Persönliche Aktionen benötigen einen aktuell bestätigten Inhalt vom Server.",
                "Для особистих дій потрібен матеріал, щойно підтверджений сервером.",
            )
        )
        OutlinedButton(
            onClick = browse::refresh,
            modifier = Modifier.testTag("personal-revalidate"),
        ) {
            Text(tr(language, "Verbindung prüfen", "Перевірити з’єднання"))
        }
    } else {
        val target = PersonalTarget(content.kind, content.id)
        val captured = state.session
        fun current(): Boolean =
            captured != null &&
                auth.state.value.personalScope() == captured &&
                browse.state.value.mode == "emulator" &&
                browse.state.value.data.detail?.id == target.id &&
                browse.state.value.data.detail?.kind == target.kind &&
                browse.state.value.data.cachedAt == null &&
                visible(content)
        PersonalActionsRow(
            target,
            state,
            language,
            onLoad = { if (current()) personal.loadActions(target) },
            onChange = { action, enabled -> if (current()) personal.set(target, action, enabled) },
            onAccount = { browse.navigate("profile") },
        )
    }
}
