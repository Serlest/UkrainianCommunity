package at.uac.android

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import at.uac.android.design.*
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.legalevidence.*
import at.uac.android.feature.moderation.*
import at.uac.android.feature.organizationreview.*
import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.usermanagement.*
import at.uac.android.feature.userstatusmanagement.*
import java.io.File
import java.time.Instant
import java.time.ZoneId
import org.junit.Rule
import org.junit.Test

/** Synthetic presentation of every people-management action; no repository or cloud writes. */
class Build86PeopleVisualUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val time = Instant.parse("2026-09-10T10:00:00Z")
    private val actor = ModerationSession("synthetic-visual-owner", 86, "owner", true)
    private val id = "synthetic-visual-person"
    private var suffix = ""

    private fun fields(role: String = "user", status: String = "active") =
        mapOf<String, Any?>(
            "id" to id,
            "displayName" to "Олена Коваль / Olena Kowal",
            "fullName" to "Олена Марія Коваль",
            "email" to "olena@example.invalid",
            "globalRole" to role,
            "accountStatus" to status,
            "blockState" to status,
            "warningCount" to 2L,
            "statusReason" to "Попереднє звернення перевірено / Vorherige Meldung geprüft",
            "updatedAt" to time,
            "createdAt" to time.minusSeconds(86400),
            "city" to "Innsbruck",
            "selectedFederalState" to "tirol",
        )

    @Composable
    private fun Host(language: String, content: @Composable () -> Unit) {
        val dark = language == "uk"
        SideEffect {
            WindowCompat.getInsetsController(
                    compose.activity.window,
                    compose.activity.window.decorView,
                )
                .apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
        }
        UacTheme(if (dark) "dark" else "light") {
            UacPageBackground(Modifier.fillMaxSize(), plain = true) {
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    UacHeader(
                        language,
                        true,
                        { compose.activity.onBackPressedDispatcher.onBackPressed() },
                        {},
                        compact = true,
                    )
                    Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp)) {
                        CompositionLocalProvider(
                            LocalEmbeddedNavigation provides true,
                            content = content,
                        )
                    }
                }
            }
        }
    }

    private fun capture(name: String, tag: String? = null) {
        compose.waitForIdle()
        // Compose capture includes protected synthetic dialogs without weakening production flags.
        val bitmap =
            (if (tag == null) compose.onRoot() else compose.onNodeWithTag(tag))
                .captureToImage()
                .asAndroidBitmap()
        File(compose.activity.cacheDir, "build86-people-$name-$suffix.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }

    private fun scroll(list: String, target: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(target))
        compose.onNodeWithTag(target).assertIsDisplayed()
    }

    private fun users(language: String) {
        suffix = language
        val person = ManagedUsersContract.user(id, fields())
        val state =
            mutableStateOf(
                ManagedUsersState(
                    session = actor,
                    visible = true,
                    users = listOf(person),
                    consumed = 1,
                )
            )
        val legal = mutableStateOf(false)
        val events =
            listOf(
                    "termsAccepted",
                    "privacyAcknowledged",
                    "minimumAgeConfirmed",
                    "organizationRulesAccepted",
                    "analyticsGranted",
                    "analyticsWithdrawn",
                )
                .mapIndexed { index, type ->
                    LegalEvidenceEvent(
                        "event-$index",
                        id,
                        type,
                        time,
                        if (type.startsWith("analytics")) "analyticsConsent" else "registration",
                        mapOf(
                            "version" to "2026-09",
                            "locale" to "uk",
                            "appVersion" to "1.1",
                            "acceptedFromPlatform" to "iOS",
                            "contentHash" to "a".repeat(64),
                            "organizationName" to "Українська спільнота Тіролю",
                        ),
                    )
                }
        compose.setContent {
            Host(language) {
                // ManagedUsersScreen owns this handler outside its lazy content in production.
                BackHandler {
                    if (legal.value) legal.value = false
                    else state.value = state.value.copy(selectedId = null, detail = null)
                }
                if (legal.value)
                    LegalEvidenceContent(id, true, events, false, language, { legal.value = false })
                else
                    ManagedUsersContent(
                        state.value,
                        language,
                        ManagedUsersActions(
                            back = {
                                state.value = state.value.copy(selectedId = null, detail = null)
                            },
                            open = {
                                state.value =
                                    state.value.copy(
                                        selectedId = id,
                                        detail = person,
                                        security =
                                            ManagedUserSecurity(
                                                id,
                                                true,
                                                false,
                                                time.minusSeconds(86400),
                                                time,
                                                listOf("password", "apple.com"),
                                            ),
                                    )
                            },
                            filter = { state.value = state.value.copy(filter = it) },
                            search = { state.value = state.value.copy(query = it) },
                            legalEvidence = { legal.value = true },
                        ),
                    )
            }
        }
        compose.onNodeWithTag("managed-users-back").assertDoesNotExist()
        capture("users-list")
        scroll("managed-users-list", "managed-user-row-$id")
        capture("users-row")
        compose.onNodeWithTag("managed-user-row-$id").performClick()
        scroll("managed-users-list", "managed-user-detail")
        capture("users-detail")
        scroll("managed-users-list", "managed-user-security")
        capture("users-security")
        scroll("managed-users-list", "managed-user-presence")
        capture("users-presence")
        scroll("managed-users-list", "managed-user-legal-evidence")
        compose.onNodeWithTag("managed-user-legal-evidence").performClick()
        capture("legal-top")
        events.forEach { event ->
            scroll("legal-evidence", "legal-evidence-event-${event.id}")
            capture("legal-${event.eventType}")
        }
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("managed-users-list").assertIsDisplayed()
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    selectedId = null,
                    detail = null,
                    error = ManagedUsersFailure.OFFLINE,
                )
        }
        scroll("managed-users-list", "managed-users-error")
        capture("users-error")
        compose.runOnIdle { state.value = state.value.copy(error = null, users = emptyList()) }
        scroll("managed-users-list", "managed-users-empty")
        capture("users-empty")
        compose.runOnIdle { state.value = state.value.copy(session = null) }
        capture("users-denied")
    }

    @Test fun usersAndLegalUk() = users("uk")

    @Test fun usersAndLegalDe() = users("de")

    private fun statuses(language: String) {
        suffix = language
        fun ready(action: UserStatusAction? = null) =
            UserStatusState(
                session = actor,
                targetId = id,
                snapshot =
                    UserStatusContract.snapshot(
                        id,
                        fields(
                            status =
                                if (action == UserStatusAction.RESTORE) "suspendedUntil"
                                else "active"
                        ),
                    ),
                fresh = true,
                journalReady = true,
                confirmation = action,
                confirmationStartedAt = time,
                reason = "Перевірено повідомлення спільноти. Die Meldung wurde sorgfältig geprüft.",
                suspensionZoneId = ZoneId.of("Europe/Vienna"),
            )
        val state = mutableStateOf(ready())
        compose.setContent {
            Host(language) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    UacCard {
                        UserStatusPanel(
                            state.value,
                            language,
                            UserStatusActions(
                                request = { state.value = ready(it) },
                                cancel = { state.value = ready() },
                                editReason = { state.value = state.value.copy(reason = it) },
                                chooseDays = {
                                    state.value = state.value.copy(suspensionDays = it)
                                },
                            ),
                        )
                    }
                }
            }
        }
        capture("status-actions")
        UserStatusAction.entries.forEach { action ->
            compose.runOnIdle { state.value = ready(action) }
            compose.onNodeWithTag("user-status-confirm-scroll").assertIsDisplayed()
            capture("status-${action.name}-top", "user-status-confirm-scroll")
            compose.onNodeWithTag("user-status-confirm").performScrollTo().assertIsEnabled()
            capture("status-${action.name}-confirm", "user-status-confirm-scroll")
            compose.onNodeWithTag("user-status-cancel").performScrollTo().performClick()
        }
        compose.runOnIdle {
            state.value = ready().copy(error = UserStatusFailure.OFFLINE, fresh = false)
        }
        capture("status-stale")
        val pending =
            UserStatusPending(
                "0".repeat(64),
                ready().snapshot!!.version,
                UserStatusAction.WARN,
                "0".repeat(64),
                "0".repeat(64),
                "0".repeat(64),
                "0".repeat(64),
                "synthetic-operation",
                "owner",
                UserStatusPhase.PREPARED,
            )
        compose.runOnIdle { state.value = ready().copy(pending = listOf(pending)) }
        compose.onNodeWithTag("user-status-reconcile-0").performScrollTo()
        capture("status-recovery")
        compose.runOnIdle { state.value = ready(UserStatusAction.WARN).copy(busy = true) }
        compose.onNodeWithTag("user-status-confirm").performScrollTo().assertIsNotEnabled()
        capture("status-busy", "user-status-confirm-scroll")
        compose.runOnIdle {
            state.value = ready(UserStatusAction.WARN).copy(reason = "", reasonRejected = true)
        }
        compose.onNodeWithTag("user-status-reason-rejected").performScrollTo()
        capture("status-validation", "user-status-confirm-scroll")
    }

    @Test fun allStatusBranchesUk() = statuses("uk")

    @Test fun allStatusBranchesDe() = statuses("de")

    private fun roles(language: String) {
        suffix = language
        fun ready(action: PlatformRoleAction? = null) =
            PlatformRoleState(
                session = actor,
                targetId = id,
                snapshot =
                    PlatformRoleRecovery.snapshot(
                        id,
                        fields(role = if (action == PlatformRoleAction.REMOVE) "admin" else "user"),
                    ),
                fresh = true,
                journalReady = true,
                confirmation = action,
                targetAuth = PlatformRoleTargetAuth(id, true, false),
                reason = "Призначення погоджено / Die Zuständigkeit wurde abgestimmt.",
            )
        val state = mutableStateOf(ready())
        compose.setContent {
            Host(language) {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    UacCard {
                        PlatformRolePanel(
                            state.value,
                            language,
                            PlatformRoleActions(
                                request = { state.value = ready(it) },
                                cancel = { state.value = ready() },
                            ),
                        )
                    }
                }
            }
        }
        capture("role-actions")
        PlatformRoleAction.entries.forEach { action ->
            compose.runOnIdle { state.value = ready(action) }
            capture("role-${action.name}-top", "platform-role-confirm-scroll")
            compose.onNodeWithTag("platform-role-confirm").performScrollTo().assertIsEnabled()
            capture("role-${action.name}-confirm", "platform-role-confirm-scroll")
            compose.onNodeWithTag("platform-role-cancel").performScrollTo().performClick()
        }
        compose.runOnIdle {
            state.value = ready().copy(targetAuth = PlatformRoleTargetAuth(id, false, false))
        }
        capture("role-ineligible")
        compose.runOnIdle {
            state.value =
                ready()
                    .copy(
                        pending =
                            listOf(
                                PlatformRolePending(
                                    "0".repeat(64),
                                    ready().snapshot!!.version,
                                    PlatformRoleAction.ASSIGN,
                                    "0".repeat(64),
                                    "synthetic-operation",
                                    PlatformRolePhase.PREPARED,
                                )
                            )
                    )
        }
        compose.onNodeWithTag("platform-role-reconcile-0").performScrollTo()
        capture("role-recovery")
        compose.runOnIdle { state.value = ready(PlatformRoleAction.ASSIGN).copy(busy = true) }
        compose.onNodeWithTag("platform-role-confirm").performScrollTo().assertIsNotEnabled()
        capture("role-busy", "platform-role-confirm-scroll")
        compose.runOnIdle {
            state.value = ready(PlatformRoleAction.ASSIGN).copy(reason = "", reasonRejected = true)
        }
        compose.onNodeWithTag("platform-role-reason-rejected").performScrollTo()
        capture("role-validation", "platform-role-confirm-scroll")
    }

    @Test fun allRoleBranchesUk() = roles("uk")

    @Test fun allRoleBranchesDe() = roles("de")

    private fun moderation(language: String, organization: Boolean) {
        suffix = language
        val kinds =
            if (organization) listOf(ModerationKind.ORGANIZATION)
            else listOf(ModerationKind.NEWS, ModerationKind.EVENT)
        val previews = kinds.map { kind ->
            val target = ModerationTarget(kind, "visual-${kind.name.lowercase()}")
            ModerationContract.preview(
                target,
                RawDocument(
                    target.id,
                    mapOf(
                        "id" to target.id,
                        "title" to "Зустріч спільноти / Begegnung der Gemeinschaft",
                        "name" to "Українська спільнота Тіролю",
                        "summary" to "Знайомство, корисні контакти та взаємодопомога.",
                        "description" to "Gemeinsam ankommen und Kontakte finden.",
                        "body" to
                            "Запрошуємо родини на зустріч. Wir laden Familien zu einem gemeinsamen Nachmittag ein.",
                        "fullDescription" to
                            "Допомога родинам, зустрічі та культурні події в Тіролі.",
                        "sourceType" to "organization",
                        "organizationId" to "visual-org",
                        "moderationStatus" to "pendingReview",
                        "createdAt" to time,
                        "updatedAt" to time,
                        "submittedByUserId" to "visual-applicant",
                        "email" to "community@example.invalid",
                        "city" to "Innsbruck",
                        "address" to "Musterstraße 10",
                        "startDate" to time,
                        "endDate" to time.plusSeconds(7200),
                    ),
                ),
            )
        }
        val section =
            if (organization) ModerationSection.ORGANIZATION_REQUESTS else ModerationSection.CONTENT
        val initial =
            ModerationState(
                session = actor,
                section = section,
                visible = true,
                parts =
                    previews.associate {
                        it.item.target.kind to
                            ModerationPart(
                                head = ModerationHead(it.item.target.kind, listOf(it.item), 1)
                            )
                    },
            )
        val state = mutableStateOf(initial)
        val decision = mutableStateOf(ModerationDecisionState(session = actor, journalReady = true))
        val orgSnapshot =
            OrganizationReviewContract.snapshot(
                "visual-organization",
                mapOf(
                    "id" to "visual-organization",
                    "name" to "Українська спільнота Тіролю",
                    "submittedByUserId" to "visual-applicant",
                    "moderationStatus" to "pendingReview",
                    "updatedAt" to time,
                    "fullDescription" to "Освітні та культурні зустрічі.",
                ),
            )
        val review =
            mutableStateOf(
                OrganizationReviewState(
                    session = actor,
                    snapshot = orgSnapshot,
                    fresh = true,
                    journalReady = true,
                    text =
                        "Будь ласка, додайте адресу та контактну особу. Bitte Adresse und Kontaktperson ergänzen.",
                )
            )
        compose.setContent {
            Host(language) {
                // Match ModerationScreen's persistent handler, not its recycled lazy header.
                BackHandler { state.value = initial }
                ModerationContent(
                    state.value,
                    language,
                    ModerationActions(
                        back = { state.value = initial },
                        open = { target ->
                            state.value =
                                initial.copy(
                                    selected = target,
                                    preview = previews.first { it.item.target == target },
                                )
                        },
                        search = { state.value = state.value.copy(search = it) },
                        filter = { state.value = state.value.copy(filter = it) },
                        sort = { state.value = state.value.copy(sort = it) },
                    ),
                    decisionContent = {
                        if (organization)
                            OrganizationReviewPanel(
                                if (state.value.selected == null) review.value.copy(snapshot = null)
                                else review.value,
                                language,
                                OrganizationReviewActions(
                                    request = {
                                        review.value =
                                            review.value.copy(
                                                confirmation = it,
                                                text =
                                                    if (it == OrganizationReviewAction.APPROVE) ""
                                                    else
                                                        "Будь ласка, додайте адресу та контактну особу. Bitte Adresse und Kontaktperson ergänzen.",
                                            )
                                    },
                                    cancel = {
                                        review.value = review.value.copy(confirmation = null)
                                    },
                                ),
                            )
                        else
                            ModerationDecisionPanel(
                                decision.value,
                                state.value.preview?.reviewVersion,
                                language,
                                ModerationDecisionActions(
                                    request = {
                                        decision.value = decision.value.copy(confirmation = it)
                                    },
                                    cancel = {
                                        decision.value = decision.value.copy(confirmation = null)
                                    },
                                ),
                            )
                    },
                )
            }
        }
        val prefix = if (organization) "organizations" else "moderation"
        capture("$prefix-queue")
        previews.forEach { preview ->
            val open = "moderation-open-${preview.item.target.kind.name}-${preview.item.target.id}"
            scroll("moderation-list", open)
            capture("$prefix-row-${preview.item.target.kind}")
            compose.onNodeWithTag(open).performClick()
            scroll("moderation-list", "moderation-preview-title")
            capture("$prefix-detail-${preview.item.target.kind}")
            scroll("moderation-list", "moderation-field-address")
            capture("$prefix-fields-${preview.item.target.kind}")
            if (organization) {
                OrganizationReviewAction.entries.forEach { action ->
                    scroll("moderation-list", "organization-review-${action.name.lowercase()}")
                    compose
                        .onNodeWithTag("organization-review-${action.name.lowercase()}")
                        .performClick()
                    capture("organization-${action.name}-top", "organization-review-confirm-scroll")
                    compose
                        .onNodeWithTag("organization-review-confirm")
                        .performScrollTo()
                        .assertIsEnabled()
                    capture(
                        "organization-${action.name}-confirm",
                        "organization-review-confirm-scroll",
                    )
                    compose
                        .onNodeWithTag("organization-review-cancel")
                        .performScrollTo()
                        .performClick()
                }
            } else {
                ModerationDecision.entries.forEach { choice ->
                    val tag =
                        if (choice == ModerationDecision.APPROVE) "moderation-approve"
                        else "moderation-reject"
                    scroll("moderation-list", tag)
                    compose.onNodeWithTag(tag).performClick()
                    scroll("moderation-list", "moderation-decision-confirm")
                    capture("${preview.item.target.kind}-${choice.name}-confirm")
                    compose
                        .onNodeWithTag("moderation-decision-cancel")
                        .performScrollTo()
                        .performClick()
                }
            }
            compose.onNodeWithTag("back").performClick()
            // At large font sizes the lazy queue search is outside the viewport after returning.
            // Assert its actual reachability rather than requiring off-screen composition.
            scroll("moderation-list", "moderation-search")
        }
        compose.runOnIdle {
            state.value =
                initial.copy(
                    parts =
                        kinds.associateWith { ModerationPart(error = ModerationFailure.OFFLINE) }
                )
        }
        scroll("moderation-list", "moderation-error-${kinds.first().name}")
        capture("$prefix-error")
        compose.runOnIdle {
            state.value =
                initial.copy(
                    parts =
                        kinds.associateWith {
                            ModerationPart(head = ModerationHead(it, emptyList(), 0))
                        }
                )
        }
        scroll("moderation-list", "moderation-empty")
        capture("$prefix-empty")
        compose.runOnIdle {
            state.value = initial
            if (organization)
                review.value =
                    review.value.copy(
                        snapshot = null,
                        pending =
                            listOf(
                                OrganizationReviewPending(
                                    "0".repeat(64),
                                    orgSnapshot.version,
                                    OrganizationReviewAction.REJECT,
                                    "0".repeat(64),
                                    "synthetic-operation",
                                    "owner",
                                    OrganizationReviewPhase.PREPARED,
                                )
                            ),
                    )
            else
                decision.value =
                    decision.value.copy(
                        pending =
                            listOf(
                                ModerationPending(
                                    "0".repeat(64),
                                    previews.first().reviewVersion!!,
                                    "synthetic-operation",
                                    "owner",
                                    ModerationDecision.APPROVE,
                                    time,
                                    ModerationDecisionPhase.PREPARED,
                                )
                            )
                    )
        }
        scroll(
            "moderation-list",
            if (organization) "organization-review-reconcile-0" else "moderation-reconcile-0",
        )
        capture("$prefix-recovery")
    }

    @Test fun moderationEveryDecisionUk() = moderation("uk", false)

    @Test fun moderationEveryDecisionDe() = moderation("de", false)

    @Test fun organizationEveryDecisionUk() = moderation("uk", true)

    @Test fun organizationEveryDecisionDe() = moderation("de", true)
}
