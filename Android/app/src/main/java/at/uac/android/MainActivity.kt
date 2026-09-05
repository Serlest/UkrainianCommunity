package at.uac.android

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import androidx.core.view.WindowCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.compose.viewModel
import at.uac.android.core.AppInteractionViewModel
import at.uac.android.core.AuthRemediationHost
import at.uac.android.core.AuthRemediationPriority
import at.uac.android.core.LocalAuthRemediationHost
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.ReminderNavigationViewModel
import at.uac.android.core.backend.AppBackend
import at.uac.android.design.LocalUacDark
import at.uac.android.design.UacTheme
import at.uac.android.feature.accountdeletion.*
import at.uac.android.feature.accountstatus.*
import at.uac.android.feature.applock.*
import at.uac.android.feature.attendees.*
import at.uac.android.feature.auth.AuthImagePickerAuthorization
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.*
import at.uac.android.feature.community.*
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.dsastatement.*
import at.uac.android.feature.feedback.*
import at.uac.android.feature.gallery.*
import at.uac.android.feature.history.*
import at.uac.android.feature.inbox.*
import at.uac.android.feature.moderation.*
import at.uac.android.feature.organization.*
import at.uac.android.feature.organizationreview.*
import at.uac.android.feature.personal.*
import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.profilemedia.*
import at.uac.android.feature.registrations.*
import at.uac.android.feature.reminders.*
import at.uac.android.feature.safety.*
import at.uac.android.feature.startup.*
import at.uac.android.feature.subscribers.*
import at.uac.android.feature.usermanagement.*
import at.uac.android.feature.userstatusmanagement.*
import java.util.Locale
import kotlinx.coroutines.flow.map

class MainActivity : FragmentActivity() {
    private var appLockHost: ActivityAppLockHost? = null
    private var interaction: AppInteractionViewModel? = null
    private var interactionHost: Long? = null
    private var reminders: LocalReminderRuntime? = null
    private var reminderNavigation: ReminderNavigationViewModel? = null
    private val reminderPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            reminders?.controller?.permissionReturned()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val preferences = applicationContext.getSharedPreferences("uac-local", MODE_PRIVATE)
        val language =
            preferences.getString("language", null)
                ?: if (Locale.getDefault().language == "uk") "uk" else "de"
        val auth = LocalAuthSession.get(applicationContext)
        val reminderRuntime =
            LocalReminders.get(applicationContext).also {
                reminders = it
                it.attachAuth { auth.state.value }
                it.controller.bindAuth(auth.state.value)
            }
        val reminderRoutes =
            ViewModelProvider(this)[ReminderNavigationViewModel::class.java].also {
                reminderNavigation = it
            }
        acceptReminderIntent(intent)
        val lockHost = ActivityAppLockHost(this, auth).also { appLockHost = it }
        val lockModel = lockHost.model
        val interactionModel =
            ViewModelProvider(this)[AppInteractionViewModel::class.java].also { interaction = it }
        val host = interactionModel.attach().also { interactionHost = it }
        val remediation =
            ViewModelProvider(this)[AuthRemediationPriority::class.java].also { it.attach(host) }
        val accountStatus =
            ViewModelProvider(
                this,
                object : ViewModelProvider.Factory {
                    @Suppress("UNCHECKED_CAST")
                    override fun <T : ViewModel> create(modelClass: Class<T>): T {
                        check(modelClass == AccountStatusViewModel::class.java)
                        val nativeAuth = AppBackend.auth(applicationContext)
                        val statusGate = AuthAccountStatusGate(auth)
                        return AccountStatusViewModel(
                                AccountStatusRepository(
                                    localAccountStatusSource(applicationContext),
                                    statusGate,
                                    statusGate,
                                ),
                                {
                                    val current = auth.state.value
                                    current.accountStatusScope().takeIf {
                                        interactionModel.interactive.value &&
                                            !remediation.active.value &&
                                            lockModel.state.value
                                                .forSession(current.appLockSession())
                                                .canRoute
                                    }
                                },
                                signOut = { captured ->
                                    val current = auth.state.value
                                    if (
                                        current.identity?.uid != captured.uid ||
                                            current.revision != captured.revision
                                    )
                                        false
                                    else {
                                        auth.signOut().join()
                                        auth.state.value.stage ==
                                            at.uac.android.feature.auth.AuthStage.GUEST &&
                                            nativeAuth.currentUser == null
                                    }
                                },
                                refreshSession = { auth.refresh() },
                            )
                            .also { it.observeAuthSessions(auth.state) } as T
                    }
                },
            )[AccountStatusViewModel::class.java]
        fun statusCoversContent(): Boolean {
            val current = auth.state.value
            val notice = accountStatus.state.value
            return !remediation.active.value &&
                !current.mfa.interactive &&
                !current.mfa.unconfirmed &&
                notice.coversContent(current.accountStatusScope())
        }
        fun contentCanInteract(): Boolean =
            interactionModel.interactive.value &&
                !remediation.active.value &&
                !statusCoversContent() &&
                !auth.state.value.mfa.interactive &&
                !auth.state.value.mfa.unconfirmed
        // Safety is a dependency of personal target resolution, not just a visual filter.
        val safety =
            ViewModelProvider(
                this,
                object : ViewModelProvider.Factory {
                    @Suppress("UNCHECKED_CAST")
                    override fun <T : ViewModel> create(modelClass: Class<T>): T {
                        check(modelClass == SafetyViewModel::class.java)
                        return SafetyViewModel(
                                localSafetySource(applicationContext),
                                { auth.state.value.safetyScope() },
                                AuthSafetyMutationGate(auth),
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.safetyScope() }
                                )
                            } as T
                    }
                },
            )[SafetyViewModel::class.java]
        fun currentSafety() = safety.state.value.forSession(auth.state.value.safetyScope())
        // The ViewModel survives recreation. Only its factory initializes the data layer.
        val factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(
                    modelClass: Class<T>,
                    extras: CreationExtras,
                ): T {
                    if (modelClass == StartupViewModel::class.java) {
                        return StartupViewModel().also { startup ->
                            startup.observeSessions(
                                auth.state.map {
                                    it.stage == at.uac.android.feature.auth.AuthStage.RESTORING
                                }
                            )
                        } as T
                    }
                    if (modelClass == PersonalProfileEditorViewModel::class.java) {
                        return localPersonalProfileEditor(auth) as T
                    }
                    if (modelClass == HistoryViewModel::class.java) {
                        val startup =
                            ViewModelProvider(this@MainActivity)[StartupViewModel::class.java]
                        return HistoryViewModel(
                                localHistorySource(applicationContext),
                                sessionAuthority = { auth.state.value.historyScope() },
                                visibility = { currentSafety().visibility.allows(it) },
                                mutationGate = AuthHistoryMutationGate(auth),
                                writeEligibility = {
                                    contentCanInteract() &&
                                        !startup.state.value.covered &&
                                        lockModel.state.value
                                            .forSession(auth.state.value.appLockSession())
                                            .canRoute
                                },
                            )
                            .also { history ->
                                history.observeSessions(auth.state.map { it.historyScope() })
                            } as T
                    }
                    if (modelClass == PersonalViewModel::class.java) {
                        val history =
                            ViewModelProvider(this@MainActivity)[HistoryViewModel::class.java]
                        val navigation =
                            ViewModelProvider(this@MainActivity)[BrowseViewModel::class.java]
                        return PersonalViewModel(
                                localPersonalSource(applicationContext),
                                visibility = { currentSafety().visibility.allows(it) },
                                sessionAuthority = { auth.state.value.personalScope() },
                                mutationGate = AuthPersonalMutationGate(auth),
                                onConfirmedChange = {
                                    history.personalChanged(it, navigation.state.value.language)
                                },
                            )
                            .also { personal ->
                                personal.observeSessions(auth.state.map { it.personalScope() })
                            } as T
                    }
                    if (modelClass == RegistrationsViewModel::class.java) {
                        return RegistrationsViewModel(
                                localRegistrationsSource(applicationContext),
                                { auth.state.value.personalScope() },
                            )
                            .also { registrations ->
                                registrations.observeSessions(auth.state.map { it.personalScope() })
                            } as T
                    }
                    if (modelClass == AttendeesViewModel::class.java) {
                        return AttendeesViewModel(
                                localAttendeesSource(applicationContext),
                                { auth.state.value.attendeesScope() },
                            )
                            .also { attendees ->
                                attendees.observeSessions(auth.state.map { it.attendeesScope() })
                            } as T
                    }
                    if (modelClass == AttendeesAccessViewModel::class.java) {
                        return AttendeesAccessViewModel(
                                localAttendeesSource(applicationContext),
                                { auth.state.value.attendeesScope() },
                            )
                            .also { access ->
                                access.observeSessions(auth.state.map { it.attendeesScope() })
                            } as T
                    }
                    if (modelClass == SubscribersViewModel::class.java) {
                        return SubscribersViewModel(
                                localSubscribersSource(
                                    applicationContext,
                                    current = { auth.state.value.subscribersScope() },
                                ),
                                authority = { auth.state.value.subscribersScope() },
                                visibleOrganization = { currentSafety().visibility.allows(it) },
                                visibleAuthor = { currentSafety().visibility.allowsAuthor(it) },
                            )
                            .also { subscribers ->
                                subscribers.observeSessions(
                                    auth.state.map { it.subscribersScope() }
                                )
                            } as T
                    }
                    if (modelClass == ManagedUsersViewModel::class.java) {
                        return ManagedUsersViewModel(
                                ManagedUsersRepository(
                                    localManagedUsersSource(applicationContext),
                                    { auth.state.value.moderationScope() },
                                    AuthModerationDecisionGate(auth),
                                )
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == UserStatusViewModel::class.java) {
                        return UserStatusViewModel(
                                UserStatusRepository(
                                    localUserStatusSource(applicationContext),
                                    LocalUserStatusJournal.get(applicationContext),
                                    authority = { auth.state.value.moderationScope() },
                                    gate = AuthModerationDecisionGate(auth),
                                )
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == PlatformRoleViewModel::class.java) {
                        return PlatformRoleViewModel(
                                PlatformRoleRepository(
                                    localPlatformRoleSource(applicationContext),
                                    LocalPlatformRoleJournal.get(applicationContext),
                                    authority = { auth.state.value.moderationScope() },
                                    gate = AuthModerationDecisionGate(auth),
                                )
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == ModerationViewModel::class.java) {
                        return ModerationViewModel(
                                localModerationSource(applicationContext),
                                { auth.state.value.moderationScope() },
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == ModerationDecisionViewModel::class.java) {
                        return ModerationDecisionViewModel(
                                ModerationDecisionRepository(
                                    localModerationDecisionSource(applicationContext),
                                    LocalModerationDecisionJournal.get(applicationContext),
                                    authority = { auth.state.value.moderationScope() },
                                    gate = AuthModerationDecisionGate(auth),
                                )
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == OrganizationReviewViewModel::class.java) {
                        return OrganizationReviewViewModel(
                                OrganizationReviewRepository(
                                    localOrganizationReviewSource(applicationContext),
                                    LocalOrganizationReviewJournal.get(applicationContext),
                                    authority = { auth.state.value.moderationScope() },
                                    gate = AuthModerationDecisionGate(auth),
                                )
                            )
                            .also {
                                it.observeSessions(
                                    auth.state.map { session -> session.moderationScope() }
                                )
                            } as T
                    }
                    if (modelClass == GalleryViewModel::class.java) {
                        return GalleryViewModel(
                                localGallerySource(applicationContext) {
                                    auth.state.value.organizationScope()
                                },
                                LocalGalleryJournal.get(applicationContext),
                                LocalGalleryPreparation(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                                AuthImagePickerAuthorization(auth),
                                visibleOrganization = { currentSafety().visibility.allows(it) },
                            )
                            .also { gallery ->
                                gallery.observeSessions(auth.state.map { it.organizationScope() })
                            } as T
                    }
                    if (modelClass == InboxViewModel::class.java) {
                        return InboxViewModel(
                                localInboxSource(applicationContext),
                                { auth.state.value.inboxScope() },
                                AuthInboxMutationGate(auth),
                                onPreferencesConfirmed = { session, _ ->
                                    if (auth.state.value.inboxScope() == session)
                                        reminderRuntime.controller.preferencesChanged()
                                },
                            )
                            .also { inbox ->
                                inbox.observeSessions(auth.state.map { it.inboxScope() })
                            } as T
                    }
                    if (modelClass == InboxPopupViewModel::class.java) {
                        return InboxPopupViewModel(
                                localInboxSource(applicationContext),
                                { auth.state.value.inboxPopupAccount() },
                                AuthInboxMutationGate(auth),
                            )
                            .also { popup ->
                                popup.observeAccounts(auth.state.map { it.inboxPopupAccount() })
                            } as T
                    }
                    if (modelClass == CommunityViewModel::class.java) {
                        val history =
                            ViewModelProvider(this@MainActivity)[HistoryViewModel::class.java]
                        val navigation =
                            ViewModelProvider(this@MainActivity)[BrowseViewModel::class.java]
                        return CommunityViewModel(
                                localCommunitySource(applicationContext),
                                { auth.state.value.communityScope() },
                                AuthCommunityMutationGate(auth),
                                onConfirmedRegistration = {
                                    history.registrationChanged(it, navigation.state.value.language)
                                    reminderRuntime.controller.registrationChanged(it.target.id)
                                },
                            )
                            .also { community ->
                                community.observeSessions(auth.state.map { it.communityScope() })
                            } as T
                    }
                    if (modelClass == DsaAppealReviewViewModel::class.java) {
                        return DsaAppealReviewViewModel(
                                localDsaAppealReadSource(applicationContext),
                                { auth.state.value.dsaAppealScope() },
                                AuthDsaAppealReadGate(auth),
                            )
                            .also { review ->
                                review.observeSessions(auth.state.map { it.dsaAppealScope() })
                            } as T
                    }
                    if (modelClass == DsaStatementViewModel::class.java) {
                        return DsaStatementViewModel(
                                localDsaStatementSource(applicationContext),
                                { auth.state.value.dsaStatementScope() },
                                AuthDsaStatementReadGate(auth),
                            )
                            .also { statement ->
                                statement.observeSessions(auth.state.map { it.dsaStatementScope() })
                            } as T
                    }
                    if (modelClass == FeedbackViewModel::class.java) {
                        return FeedbackViewModel(
                                localFeedbackSource(applicationContext),
                                { auth.state.value.feedbackScope() },
                                AuthFeedbackMutationGate(auth),
                            )
                            .also { feedback ->
                                feedback.observeSessions(auth.state.map { it.feedbackScope() })
                            } as T
                    }
                    if (modelClass == OrganizationViewModel::class.java) {
                        return OrganizationViewModel(
                                localOrganizationSource(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                                AuthImagePickerAuthorization(auth),
                            )
                            .also { organizations ->
                                organizations.observeSessions(
                                    auth.state.map { it.organizationScope() }
                                )
                            } as T
                    }
                    if (modelClass == OrganizationManagementViewModel::class.java) {
                        return OrganizationManagementViewModel(
                                localOrganizationManagementSource(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                                AuthImagePickerAuthorization(auth),
                            )
                            .also { management ->
                                management.observeSessions(
                                    auth.state.map { it.organizationScope() }
                                )
                            } as T
                    }
                    if (modelClass == AuthoringViewModel::class.java) {
                        return AuthoringViewModel(
                                localAuthoringSource(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                                recoveryStore = localAuthoringRecoveryStore(applicationContext),
                            )
                            .also { authoring ->
                                authoring.observeSessions(auth.state.map { it.organizationScope() })
                            } as T
                    }
                    if (modelClass == ContentCoverViewModel::class.java) {
                        return ContentCoverViewModel(
                                localContentCoverSource(applicationContext),
                                LocalContentCoverPreparation(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                                AuthImagePickerAuthorization(auth),
                            )
                            .also { cover ->
                                cover.observeSessions(auth.state.map { it.organizationScope() })
                            } as T
                    }
                    if (modelClass == ContentLifecycleViewModel::class.java) {
                        return ContentLifecycleViewModel(
                                localContentLifecycleSource(applicationContext),
                                { auth.state.value.organizationScope() },
                                AuthOrganizationMutationGate(auth),
                            )
                            .also { lifecycle ->
                                lifecycle.observeSessions(auth.state.map { it.organizationScope() })
                            } as T
                    }
                    if (modelClass == ProfileMediaViewModel::class.java) {
                        return ProfileMediaViewModel(
                                localProfileMediaSource(applicationContext),
                                localProfilePhotoPreparation(applicationContext),
                                { auth.state.value.personalScope() },
                                AuthPersonalMutationGate(auth),
                                AuthImagePickerAuthorization(auth),
                            )
                            .also { media ->
                                media.observeSessions(auth.state.map { it.personalScope() })
                            } as T
                    }
                    if (modelClass == AccountDeletionViewModel::class.java) {
                        // Retain the navigation model, never this Activity, across a long
                        // deletion/rotation.
                        val navigation =
                            ViewModelProvider(this@MainActivity)[BrowseViewModel::class.java]
                        return localAccountDeletionViewModel(applicationContext, auth) { deleted, _
                            ->
                            val current = auth.state.value
                            if (
                                current.identity?.uid == deleted.uid ||
                                    current.stage == at.uac.android.feature.auth.AuthStage.GUEST
                            ) {
                                navigation.showDeletionCompletion(deleted.uid)
                            }
                        }
                            as T
                    }
                    check(modelClass == BrowseViewModel::class.java)
                    val (synthetic, emulator) = localContentRepositories(applicationContext)
                    return BrowseViewModel(
                            synthetic,
                            emulator,
                            extras.createSavedStateHandle(),
                            language,
                            preferences.getString("region", "").orEmpty(),
                            preferences.getString("theme", "system")!!,
                            { key, selected -> preferences.edit { putString(key, selected) } },
                        )
                        .also { navigation ->
                            navigation.observeAccounts(
                                auth.state.map { session ->
                                    NavigationAccount(
                                        session.identity?.takeUnless { it.anonymous }?.uid,
                                        session.stage ==
                                            at.uac.android.feature.auth.AuthStage.RESTORING,
                                    )
                                }
                            )
                        } as T
                }
            }
        setContent {
            val startup: StartupViewModel = viewModel(factory = factory)
            val model: BrowseViewModel = viewModel(factory = factory)
            val history: HistoryViewModel = viewModel(factory = factory)
            val personal: PersonalViewModel = viewModel(factory = factory)
            val profileEditor: PersonalProfileEditorViewModel = viewModel(factory = factory)
            val registrations: RegistrationsViewModel = viewModel(factory = factory)
            val attendees: AttendeesViewModel = viewModel(factory = factory)
            val attendeesAccess: AttendeesAccessViewModel = viewModel(factory = factory)
            val subscribers: SubscribersViewModel = viewModel(factory = factory)
            val gallery: GalleryViewModel = viewModel(factory = factory)
            val moderation: ModerationViewModel = viewModel(factory = factory)
            val managedUsers: ManagedUsersViewModel = viewModel(factory = factory)
            val userStatuses: UserStatusViewModel = viewModel(factory = factory)
            val platformRoles: PlatformRoleViewModel = viewModel(factory = factory)
            val moderationDecisions: ModerationDecisionViewModel = viewModel(factory = factory)
            val organizationReviews: OrganizationReviewViewModel = viewModel(factory = factory)
            val inbox: InboxViewModel = viewModel(factory = factory)
            val popup: InboxPopupViewModel = viewModel(factory = factory)
            val community: CommunityViewModel = viewModel(factory = factory)
            val feedback: FeedbackViewModel = viewModel(factory = factory)
            val dsaStatement: DsaStatementViewModel = viewModel(factory = factory)
            val dsaReview: DsaAppealReviewViewModel = viewModel(factory = factory)
            val organizations: OrganizationViewModel = viewModel(factory = factory)
            val organizationManagement: OrganizationManagementViewModel =
                viewModel(factory = factory)
            val authoring: AuthoringViewModel = viewModel(factory = factory)
            val contentCover: ContentCoverViewModel = viewModel(factory = factory)
            val contentLifecycle: ContentLifecycleViewModel = viewModel(factory = factory)
            val media: ProfileMediaViewModel = viewModel(factory = factory)
            val deletion: AccountDeletionViewModel = viewModel(factory = factory)
            val authSession by auth.state.collectAsStateWithLifecycle()
            val lockSnapshot by lockHost.model.state.collectAsStateWithLifecycle()
            val lockState = lockSnapshot.forSession(authSession.appLockSession())
            SideEffect { lockHost.rendered(authSession.appLockSession()) }
            val safetySnapshot by safety.state.collectAsStateWithLifecycle()
            val safetyState = safetySnapshot.forSession(authSession.safetyScope())
            val personalSnapshot by personal.state.collectAsStateWithLifecycle()
            val personalState =
                personalSnapshot
                    .forSession(authSession.personalScope())
                    .visibleTo(safetyState.visibility)
            val registrationsSnapshot by registrations.state.collectAsStateWithLifecycle()
            val registrationsState =
                registrationsSnapshot
                    .forSession(authSession.personalScope())
                    .visibleTo(safetyState.visibility::allows)
            val inboxSnapshot by inbox.state.collectAsStateWithLifecycle()
            val inboxState = inboxSnapshot.forSession(authSession.inboxScope())
            val popupSnapshot by popup.state.collectAsStateWithLifecycle()
            val popupState = popupSnapshot.forAccount(authSession.inboxPopupAccount())
            val feedbackSnapshot by feedback.state.collectAsStateWithLifecycle()
            val feedbackState = feedbackSnapshot.forSession(authSession.feedbackScope())
            val dsaSnapshot by dsaStatement.state.collectAsStateWithLifecycle()
            val dsaState = dsaSnapshot.forSession(authSession.dsaStatementScope())
            val reviewSnapshot by dsaReview.state.collectAsStateWithLifecycle()
            val reviewState =
                reviewSnapshot.forSession(authSession.dsaAppealScope(), java.time.Instant.now())
            val mediaSnapshot by media.state.collectAsStateWithLifecycle()
            val mediaState = mediaSnapshot.forSession(authSession.personalScope())
            val deletionSnapshot by deletion.state.collectAsStateWithLifecycle()
            val deletionState = deletionSnapshot.forSession(authSession.accountDeletionScope())
            val browseState by model.state.collectAsStateWithLifecycle()
            val startupState by startup.state.collectAsStateWithLifecycle()
            val hostInteractive by interactionModel.interactive.collectAsStateWithLifecycle()
            val remediationActive by remediation.active.collectAsStateWithLifecycle()
            val statusSnapshot by accountStatus.state.collectAsStateWithLifecycle()
            val statusSession = authSession.accountStatusScope()
            val securityRemediation = authSession.mfa.interactive || authSession.mfa.unconfirmed
            val statusCovered =
                !remediationActive &&
                    !securityRemediation &&
                    statusSnapshot.coversContent(statusSession)
            val interactive =
                hostInteractive && !remediationActive && !securityRemediation && !statusCovered
            val focusManager = LocalFocusManager.current
            val keyboardController = LocalSoftwareKeyboardController.current
            LaunchedEffect(statusCovered) {
                if (statusCovered) {
                    focusManager.clearFocus(force = true)
                    keyboardController?.hide()
                }
            }
            val reminderSnapshot by reminderRuntime.controller.state.collectAsStateWithLifecycle()
            val reminderState = reminderSnapshot.forSession(authSession.reminderSession())
            val reminderRouteState by reminderRoutes.state.collectAsStateWithLifecycle()
            SideEffect {
                interactionModel.rendered(host, !startupState.covered && lockState.canRoute)
            }
            SideEffect { reminderRuntime.controller.bindAuth(authSession) }
            LaunchedEffect(safetyState.session, safetyState.visibility) {
                personal.visibilityChanged()
                history.visibilityChanged()
                subscribers.visibilityChanged()
                gallery.visibilityChanged()
                reminderRuntime.controller.visibilityChanged()
            }
            LaunchedEffect(
                reminderRouteState.pending,
                authSession.revision,
                authSession.readyForActions,
                interactive,
                startupState.covered,
                lockState.canRoute,
                safetyState.visibility,
            ) {
                val request = reminderRouteState.pending ?: return@LaunchedEffect
                if (
                    !interactive ||
                        startupState.covered ||
                        !lockState.canRoute ||
                        !authSession.readyForActions ||
                        !safetyState.visibility.loaded
                )
                    return@LaunchedEffect
                val captured = authSession.reminderSession()
                val entry = model.state.value.entryRevision
                val accountEpoch = model.state.value.navigationEpoch
                reminderRuntime.controller.bindAuth(auth.state.value)
                val outcome = reminderRuntime.controller.resolveTapOutcome(request)
                val current = auth.state.value
                if (
                    current.reminderSession() != captured ||
                        !current.readyForActions ||
                        !contentCanInteract() ||
                        startup.state.value.covered ||
                        !lockModel.state.value.forSession(current.appLockSession()).canRoute ||
                        !currentSafety().visibility.loaded ||
                        currentSafety().visibility != safetyState.visibility
                )
                    return@LaunchedEffect
                // A delayed reminder must not interrupt a destination the person chose while
                // verification was running.
                if (
                    model.state.value.entryRevision != entry ||
                        model.state.value.navigationEpoch != accountEpoch
                ) {
                    reminderRoutes.complete(request)
                    return@LaunchedEffect
                }
                if (outcome == ReminderTapOutcome.LocalTest) {
                    if (reminderRoutes.complete(request, localTestOpened = true))
                        model.navigate("profile/inbox-settings")
                    return@LaunchedEffect
                }
                val visible =
                    (outcome as? ReminderTapOutcome.Event)?.content?.takeIf {
                        currentSafety().visibility.allows(it)
                    }
                if (reminderRoutes.complete(request, unavailable = visible == null))
                    visible?.let(model::openPersonalContent)
            }
            // Data/session owners initialize above, but no account UI, popup or click target
            // exists under initial restoration. This avoids a second competing window lock.
            if (startupState.covered) {
                BackHandler {}
                UacTheme(browseState.theme) {
                    val dark = LocalUacDark.current
                    SideEffect {
                        WindowCompat.getInsetsController(window, window.decorView).apply {
                            isAppearanceLightStatusBars = !dark
                            isAppearanceLightNavigationBars = !dark
                        }
                    }
                    StartupScreen(
                        browseState.language,
                        rememberStartupReducedMotion(),
                        !lockState.blocksInteraction,
                    )
                }
            } else {
                CompositionLocalProvider(
                    LocalWindowPrivacy provides lockHost.privacy,
                    LocalAuthRemediationHost provides AuthRemediationHost(remediation, host),
                ) {
                    BrowseScreen(
                        browseState.visibleTo(safetyState.visibility),
                        model,
                        diagnostics = {
                            startActivity(Intent(this, FoundationActivity::class.java))
                        },
                        overlay = {
                            InboxPopupDestination(
                                popupState,
                                browseState.language,
                                auth,
                                popup,
                                model,
                                lockState.canRoute && interactive,
                                canStillInteract = ::contentCanInteract,
                            )
                            AccountStatusHost(
                                accountStatus,
                                statusSession,
                                browseState.language,
                                interactive =
                                    hostInteractive &&
                                        lockState.canRoute &&
                                        !remediationActive &&
                                        !securityRemediation &&
                                        !lockHost.privacy.interactionBlocked,
                                onVerification = { model.navigate("profile") },
                                onMfa = { model.navigate("profile") },
                            )
                        },
                        visibilityNotice = {
                            if (reminderRouteState.unavailable)
                                Column(Modifier.testTag("reminder-destination-unavailable")) {
                                    Text(
                                        tr(
                                            browseState.language,
                                            "Dieses Erinnerungsziel konnte nicht aktuell bestätigt werden.",
                                            "Не вдалося підтвердити актуальну доступність цієї події.",
                                        )
                                    )
                                    OutlinedButton(reminderRoutes::dismissNotice) {
                                        Text(tr(browseState.language, "Schließen", "Закрити"))
                                    }
                                }
                            if (reminderRouteState.pending != null && !authSession.readyForActions)
                                Column(Modifier.testTag("reminder-awaiting-account")) {
                                    Text(
                                        tr(
                                            browseState.language,
                                            "Prüfe dein Konto, um die Erinnerung sicher zu öffnen.",
                                            "Перевірте стан акаунта, щоб безпечно відкрити нагадування.",
                                        )
                                    )
                                    OutlinedButton({ model.navigate("profile") }) {
                                        Text(
                                            tr(
                                                browseState.language,
                                                "Konto öffnen",
                                                "Відкрити акаунт",
                                            )
                                        )
                                    }
                                }
                            SafetyAvailabilityNotice(
                                safetyState,
                                browseState.language,
                                safety::refresh,
                                { model.navigate("profile") },
                            )
                            browseState.data.detail?.let { detail ->
                                safetyState.visibility
                                    .reason(detail)
                                    ?.takeIf { safetyState.visibility.loaded }
                                    ?.let { reason ->
                                        Column(Modifier.testTag("safety-hidden-detail")) {
                                            Text(safetyVisibilityText(reason, browseState.language))
                                            OutlinedButton({ model.navigate("profile/blocked") }) {
                                                Text(
                                                    tr(
                                                        browseState.language,
                                                        "Blockierungen verwalten",
                                                        "Керувати блокуваннями",
                                                    )
                                                )
                                            }
                                        }
                                    }
                            }
                        },
                        accountContent = { route, selectedLanguage ->
                            if (route == "profile/deleted") {
                                Column(
                                    Modifier.fillMaxSize()
                                        .verticalScroll(rememberScrollState())
                                        .padding(20.dp)
                                        .testTag("account-deletion-complete")
                                ) {
                                    Text(
                                        if (
                                            model.deletionCompletionVisible(
                                                authSession.identity?.uid
                                            )
                                        )
                                            tr(
                                                selectedLanguage,
                                                "Dein Konto wurde gelöscht.",
                                                "Ваш обліковий запис видалено.",
                                            )
                                        else
                                            tr(
                                                selectedLanguage,
                                                "Für diese Sitzung liegt keine aktuelle Löschbestätigung vor.",
                                                "Для цього сеансу немає актуального підтвердження видалення.",
                                            )
                                    )
                                    OutlinedButton({ model.navigate("profile", true) }) {
                                        Text(tr(selectedLanguage, "Weiter", "Продовжити"))
                                    }
                                }
                            } else if (route == "profile/delete") {
                                Column(
                                    Modifier.fillMaxSize()
                                        .verticalScroll(rememberScrollState())
                                        .padding(20.dp)
                                ) {
                                    OutlinedButton(
                                        { model.navigate("profile") },
                                        enabled = !deletionState.busy,
                                    ) {
                                        Text(
                                            tr(
                                                selectedLanguage,
                                                "Zurück zum Konto",
                                                "Назад до облікового запису",
                                            )
                                        )
                                    }
                                    AccountDeletionPanel(
                                        deletionState,
                                        selectedLanguage,
                                        deletion,
                                        { model.navigate("profile") },
                                        { model.navigate("profile/organizations") },
                                    )
                                }
                            } else if (route == "profile/recent" || route == "profile/history") {
                                HistoryScreen(
                                    history,
                                    if (route == "profile/recent") HistorySection.RECENT
                                    else HistorySection.ACTIVITY,
                                    authSession.historyScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                    { content ->
                                        if (currentSafety().visibility.allows(content))
                                            model.openPersonalContent(content)
                                    },
                                    visibleContent = safetyState.visibility::allows,
                                )
                            } else if (route.startsWith("profile/attendees/")) {
                                AttendeesScreen(
                                    attendees,
                                    route.removePrefix("profile/attendees/"),
                                    authSession.attendeesScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                )
                            } else if (route.startsWith("profile/subscribers/")) {
                                SubscribersScreen(
                                    subscribers,
                                    route.removePrefix("profile/subscribers/"),
                                    authSession.subscribersScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                    visibleOrganization = safetyState.visibility::allows,
                                    visibleAuthor = safetyState.visibility::allowsAuthor,
                                )
                            } else if (route == "profile/registrations") {
                                val captured = registrationsState.session
                                fun current() =
                                    captured != null && captured == auth.state.value.personalScope()
                                Column {
                                    SafetyAvailabilityNotice(
                                        safetyState,
                                        selectedLanguage,
                                        safety::refresh,
                                        { model.navigate("profile") },
                                    )
                                    RegistrationsScreen(
                                        registrationsState,
                                        selectedLanguage,
                                        { more -> if (current()) registrations.refresh(more) },
                                        { if (current()) registrations.segment(it) },
                                        { event ->
                                            if (
                                                current() &&
                                                    currentSafety().visibility.allows(event)
                                            ) {
                                                model.preference("mode", "emulator")
                                                model.navigate("events/${event.id}")
                                            }
                                        },
                                        { model.navigate("profile") },
                                    )
                                }
                            } else if (route.startsWith("profile/organizations/gallery/")) {
                                GalleryScreen(
                                    gallery,
                                    route.removePrefix("profile/organizations/gallery/"),
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                )
                            } else if (route.startsWith("profile/organizations/lifecycle/")) {
                                val parts = route.split('/')
                                ContentLifecycleScreen(
                                    contentLifecycle,
                                    ContentLifecycleTarget(
                                        parts[3],
                                        if (parts[4] == "events") ContentKind.EVENTS
                                        else ContentKind.NEWS,
                                        parts[5],
                                    ),
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                )
                            } else if (route.startsWith("profile/organizations/cover/")) {
                                val parts = route.split('/')
                                ContentCoverScreen(
                                    contentCover,
                                    ContentCoverTarget(
                                        parts[3],
                                        if (parts[4] == "events") ContentKind.EVENTS
                                        else ContentKind.NEWS,
                                        parts[5],
                                    ),
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                )
                            } else if (route.startsWith("profile/organizations/author/")) {
                                val parts = route.split('/')
                                AuthoringScreen(
                                    authoring,
                                    parts[3],
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                    model::openPersonalContent,
                                    initialKind =
                                        if (parts[4] == "events") ContentKind.EVENTS
                                        else ContentKind.NEWS,
                                    onCover = { item ->
                                        model.navigate(
                                            "profile/organizations/cover/${parts[3]}/${item.kind.collection}/${item.id}"
                                        )
                                    },
                                    onLifecycle = { item ->
                                        model.navigate(
                                            "profile/organizations/lifecycle/${parts[3]}/${item.kind.collection}/${item.id}"
                                        )
                                    },
                                )
                            } else if (route.startsWith("profile/organizations/manage/")) {
                                OrganizationManagementScreen(
                                    organizationManagement,
                                    route.removePrefix("profile/organizations/manage/"),
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                    {
                                        model.preference("mode", "emulator")
                                        model.navigate("organizations/$it")
                                    },
                                    onAuthoring = { kind ->
                                        model.navigate(
                                            "profile/organizations/author/${route.removePrefix("profile/organizations/manage/")}/${kind.collection}"
                                        )
                                    },
                                )
                            } else if (
                                route == "profile/organizations" ||
                                    route.startsWith("profile/organizations/")
                            ) {
                                OrganizationScreen(
                                    organizations,
                                    authSession.organizationScope(),
                                    selectedLanguage,
                                    model::back,
                                    { model.navigate("profile") },
                                    {
                                        model.preference("mode", "emulator")
                                        model.navigate("organizations/$it")
                                    },
                                    initialRequestId =
                                        route.removePrefix("profile/organizations/").takeUnless {
                                            route == "profile/organizations"
                                        },
                                    onManageOrganization = {
                                        model.navigate("profile/organizations/manage/$it")
                                    },
                                )
                            } else if (route == "profile/users") {
                                ManagedUsersScreen(
                                    managedUsers,
                                    authSession.moderationScope(),
                                    selectedLanguage,
                                    onBack = model::back,
                                    onAccount = { model.navigate("profile") },
                                    interactive = interactive,
                                    statuses = userStatuses,
                                    roles = platformRoles,
                                )
                            } else if (
                                route == "profile/moderation" ||
                                    route == "profile/organization-review" ||
                                    route.startsWith("profile/organization-review/")
                            ) {
                                val requests = route != "profile/moderation"
                                ModerationScreen(
                                    moderation,
                                    authSession.moderationScope(),
                                    if (requests) ModerationSection.ORGANIZATION_REQUESTS
                                    else ModerationSection.CONTENT,
                                    selectedLanguage,
                                    onBack = model::back,
                                    requestedOrganizationId =
                                        route
                                            .takeIf {
                                                it.startsWith("profile/organization-review/")
                                            }
                                            ?.removePrefix("profile/organization-review/"),
                                    interactive = interactive,
                                    decisions = if (requests) null else moderationDecisions,
                                    organizationReviews =
                                        if (requests) organizationReviews else null,
                                )
                            } else if (route.startsWith("profile/dsa-review/")) {
                                DsaAppealReviewDestination(
                                    route.removePrefix("profile/dsa-review/"),
                                    selectedLanguage,
                                    reviewState,
                                    dsaReview,
                                    { model.navigate("profile") },
                                )
                            } else if (route.startsWith("profile/dsa-statement/")) {
                                DsaStatementDestination(
                                    route.removePrefix("profile/dsa-statement/"),
                                    selectedLanguage,
                                    dsaState,
                                    dsaStatement,
                                    { model.navigate("profile") },
                                )
                            } else if (
                                route == "profile/feedback" ||
                                    route.startsWith("profile/feedback/") ||
                                    route == "profile/support" ||
                                    route.startsWith("profile/support/")
                            ) {
                                val management =
                                    route == "profile/support" ||
                                        route.startsWith("profile/support/")
                                val base = if (management) "profile/support" else "profile/feedback"
                                val id = route.removePrefix("$base/").takeUnless { route == base }
                                FeedbackDestination(
                                    if (management) FeedbackAudience.MANAGEMENT
                                    else FeedbackAudience.OWN,
                                    id,
                                    selectedLanguage,
                                    feedbackState,
                                    feedback,
                                    { model.navigate("$base/$it") },
                                    { model.navigate("profile") },
                                    onReadDecision = { reportId ->
                                        if (DsaStatementContract.validId(reportId))
                                            model.navigate("profile/dsa-review/$reportId")
                                    },
                                )
                            } else if (
                                route == "profile/blocked" &&
                                    authSession.identity?.anonymous != false
                            ) {
                                PersonalDestination(
                                    "profile",
                                    selectedLanguage,
                                    auth,
                                    personalState,
                                    personal,
                                    model,
                                )
                            } else if (route == "profile/blocked") {
                                Column {
                                    SafetyAvailabilityNotice(
                                        safetyState,
                                        selectedLanguage,
                                        safety::refresh,
                                        { model.navigate("profile") },
                                    )
                                    val captured = authSession.safetyScope()
                                    SafetyBlockedScreen(
                                        safetyState,
                                        selectedLanguage,
                                        safety::refresh,
                                        { id, blocked ->
                                            if (auth.state.value.safetyScope() == captured)
                                                safety.setUser(id, blocked)
                                        },
                                        { id, blocked ->
                                            if (auth.state.value.safetyScope() == captured)
                                                safety.setOrganization(id, blocked)
                                        },
                                        onAccount = { model.navigate("profile") },
                                    )
                                }
                            } else if (
                                route in
                                    setOf(
                                        "profile/inbox",
                                        "profile/inbox-settings",
                                        "profile/legal",
                                    )
                            ) {
                                InboxDestinationScreen(
                                    route,
                                    selectedLanguage,
                                    inboxState,
                                    authSession,
                                    auth,
                                    inbox,
                                    model,
                                ) {
                                    fun allowed() =
                                        contentCanInteract() &&
                                            auth.state.value.readyForActions &&
                                            auth.state.value.reminderSession() ==
                                                authSession.reminderSession()
                                    if (reminderRouteState.localTestOpened) {
                                        Text(
                                            tr(
                                                selectedLanguage,
                                                "Lokales Test-Erinnerungsziel bestätigt. Dies ist kein Cloud-Push-Test.",
                                                "Відкриття локального тестового нагадування підтверджено. Це не перевірка хмарного push.",
                                            ),
                                            Modifier.testTag("reminder-local-test-opened"),
                                        )
                                    }
                                    ReminderSettingsCard(
                                        reminderState,
                                        selectedLanguage,
                                        onRequestPermission = {
                                            if (allowed()) {
                                                reminderRuntime.ensureChannel()
                                                if (Build.VERSION.SDK_INT >= 33)
                                                    reminderPermission.launch(
                                                        Manifest.permission.POST_NOTIFICATIONS
                                                    )
                                                else reminderRuntime.controller.permissionReturned()
                                            }
                                        },
                                        onOpenSettings = {
                                            if (allowed())
                                                startActivity(
                                                    Intent(
                                                            Settings
                                                                .ACTION_APP_NOTIFICATION_SETTINGS
                                                        )
                                                        .putExtra(
                                                            Settings.EXTRA_APP_PACKAGE,
                                                            packageName,
                                                        )
                                                )
                                        },
                                        onRetry = {
                                            if (allowed()) reminderRuntime.controller.reconcile()
                                        },
                                        onLocalTest = {
                                            if (allowed())
                                                reminderRuntime.controller.scheduleLocalTest()
                                        },
                                    )
                                }
                            } else
                                PersonalDestination(
                                    route,
                                    selectedLanguage,
                                    auth,
                                    personalState,
                                    personal,
                                    model,
                                    visibilityNotice = {
                                        SafetyAvailabilityNotice(
                                            safetyState,
                                            selectedLanguage,
                                            safety::refresh,
                                            { model.navigate("profile") },
                                        )
                                    },
                                    avatarBusy = mediaState.busy,
                                    editor = profileEditor,
                                    avatarEditor = { url, enabled, onUrl ->
                                        ProfileAvatarEditor(
                                            mediaState,
                                            selectedLanguage,
                                            enabled,
                                            url,
                                            media,
                                            onUrl,
                                        )
                                    },
                                ) {
                                    InboxAccountLink(inboxState, selectedLanguage) {
                                        if (auth.state.value.inboxScope() != null)
                                            model.navigate("profile/inbox")
                                    }
                                    if (lockState.session != null)
                                        AppLockSettingsSection(lockState, selectedLanguage) {
                                            enabled ->
                                            if (
                                                lockHost.model.state.value.session ==
                                                    auth.state.value.appLockSession()
                                            )
                                                lockHost.model.setEnabled(enabled, selectedLanguage)
                                        }
                                    if (authSession.identity?.anonymous == false)
                                        OutlinedButton(
                                            { model.navigate("profile/blocked") },
                                            Modifier.fillMaxWidth().testTag("account-open-blocked"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Blockierte Konten und Organisationen",
                                                    "Заблоковані користувачі й організації",
                                                )
                                            )
                                        }
                                    if (authSession.feedbackScope() != null)
                                        OutlinedButton(
                                            { model.navigate("profile/feedback") },
                                            Modifier.fillMaxWidth()
                                                .testTag("account-open-feedback"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Meine Anfragen und Support",
                                                    "Мої звернення та підтримка",
                                                )
                                            )
                                        }
                                    if (authSession.readyForActions)
                                        OutlinedButton(
                                            { model.navigate("profile/organizations") },
                                            Modifier.fillMaxWidth()
                                                .testTag("account-open-organizations"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Meine Organisationen und Anträge",
                                                    "Мої організації та заявки",
                                                )
                                            )
                                        }
                                    if (authSession.readyForActions)
                                        OutlinedButton(
                                            { model.navigate("profile/registrations") },
                                            Modifier.fillMaxWidth()
                                                .testTag("account-open-registrations"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Meine Veranstaltungen",
                                                    "Мої події",
                                                )
                                            )
                                        }
                                    if (authSession.readyForActions) {
                                        OutlinedButton(
                                            { model.navigate("profile/recent") },
                                            Modifier.fillMaxWidth().testTag("account-open-recent"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Zuletzt angesehen",
                                                    "Нещодавно переглянуте",
                                                )
                                            )
                                        }
                                        OutlinedButton(
                                            { model.navigate("profile/history") },
                                            Modifier.fillMaxWidth().testTag("account-open-history"),
                                        ) {
                                            Text(
                                                tr(selectedLanguage, "Meine Aktivitäten", "Мої дії")
                                            )
                                        }
                                    }
                                    val moderationScope = authSession.moderationScope()
                                    if (moderationScope?.allowed == true) {
                                        OutlinedButton(
                                            {
                                                if (
                                                    auth.state.value.moderationScope() ==
                                                        moderationScope
                                                )
                                                    model.navigate("profile/users")
                                            },
                                            Modifier.fillMaxWidth().testTag("account-open-users"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Nutzerverwaltung",
                                                    "Керування користувачами",
                                                )
                                            )
                                        }
                                        OutlinedButton(
                                            {
                                                if (
                                                    auth.state.value.moderationScope() ==
                                                        moderationScope
                                                )
                                                    model.navigate("profile/moderation")
                                            },
                                            Modifier.fillMaxWidth()
                                                .testTag("account-open-moderation"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Inhalte prüfen",
                                                    "Перевірка матеріалів",
                                                )
                                            )
                                        }
                                        OutlinedButton(
                                            {
                                                if (
                                                    auth.state.value.moderationScope() ==
                                                        moderationScope
                                                )
                                                    model.navigate("profile/organization-review")
                                            },
                                            Modifier.fillMaxWidth()
                                                .testTag("account-open-organization-review"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Organisationsanträge prüfen",
                                                    "Перевірка заявок організацій",
                                                )
                                            )
                                        }
                                    }
                                    if (authSession.feedbackScope()?.canManage == true)
                                        OutlinedButton(
                                            { model.navigate("profile/support") },
                                            Modifier.fillMaxWidth().testTag("account-open-support"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Support-Postfach verwalten",
                                                    "Керувати скринькою підтримки",
                                                )
                                            )
                                        }
                                    if (authSession.accountDeletionScope() != null)
                                        OutlinedButton(
                                            { model.navigate("profile/delete") },
                                            Modifier.fillMaxWidth().testTag("account-open-delete"),
                                        ) {
                                            Text(
                                                tr(
                                                    selectedLanguage,
                                                    "Konto löschen",
                                                    "Видалити обліковий запис",
                                                )
                                            )
                                        }
                                }
                        },
                        publicGallery = { content, currentBrowse ->
                            val capturedUid = authSession.identity?.uid
                            val capturedRevision = authSession.revision
                            val capturedEntry = currentBrowse.entryRevision
                            fun publicTargetVisible(): Boolean {
                                val current = model.state.value
                                val account = auth.state.value
                                return contentCanInteract() &&
                                    !startup.state.value.covered &&
                                    lockModel.state.value
                                        .forSession(account.appLockSession())
                                        .canRoute &&
                                    account.identity?.uid == capturedUid &&
                                    account.revision == capturedRevision &&
                                    current.entryRevision == capturedEntry &&
                                    current.route == currentBrowse.route &&
                                    current.kind == ContentKind.ORGANIZATIONS &&
                                    current.data.detail == content &&
                                    !current.data.loading &&
                                    currentSafety().visibility.allows(content)
                            }
                            at.uac.android.feature.publicgallery.PublicOrganizationGallery(
                                organizationId = content.id,
                                photos = currentBrowse.data.photos,
                                language = currentBrowse.language,
                                cachedAt = currentBrowse.data.cachedAt,
                                failure =
                                    currentBrowse.data.warnings
                                        .firstOrNull { it.first == "photos" }
                                        ?.second,
                                onRefresh = { if (publicTargetVisible()) model.refresh() },
                                displayable = ::publicTargetVisible,
                                scopeKey = Triple(capturedUid, capturedRevision, capturedEntry),
                            )
                        },
                        personalActions = { content, currentBrowse ->
                            PersonalDetailActions(
                                content,
                                currentBrowse,
                                personalState,
                                auth,
                                personal,
                                model,
                            ) {
                                contentCanInteract() && currentSafety().visibility.allows(it)
                            }
                            if (
                                currentBrowse.mode == "emulator" &&
                                    currentBrowse.data.cachedAt == null &&
                                    !currentBrowse.data.loading
                            ) {
                                val capturedScope = authSession.communityScope()
                                val capturedSafety = authSession.safetyScope()
                                fun currentTarget(): Boolean {
                                    val actual = model.state.value
                                    return contentCanInteract() &&
                                        actual.mode == "emulator" &&
                                        actual.data.cachedAt == null &&
                                        !actual.data.loading &&
                                        actual.data.detail?.id == content.id &&
                                        actual.kind == content.kind &&
                                        auth.state.value.communityScope() == capturedScope &&
                                        auth.state.value.safetyScope() == capturedSafety &&
                                        currentSafety().visibility.allows(content)
                                }
                                if (interactive)
                                    HistoryViewRecorder(
                                        history,
                                        content,
                                        authSession.historyScope(),
                                        currentBrowse.entryRevision.toString(),
                                        currentBrowse.language,
                                    ) {
                                        contentCanInteract() &&
                                            !startup.state.value.covered &&
                                            lockModel.state.value
                                                .forSession(auth.state.value.appLockSession())
                                                .canRoute &&
                                            currentTarget()
                                    }
                                ContentSafetyTools(
                                    SafetyReportTarget.content(content, currentBrowse.language),
                                    safetyState,
                                    currentBrowse.language,
                                    safety,
                                    ::currentTarget,
                                    { model.navigate("profile") },
                                )
                                AttendeesAccessPanel(
                                    attendeesAccess,
                                    content,
                                    authSession.attendeesScope(),
                                    currentBrowse.language,
                                    ::currentTarget,
                                ) {
                                    model.navigate("profile/attendees/$it")
                                }
                                SubscribersAccessPanel(
                                    content,
                                    authSession.subscribersScope(),
                                    currentBrowse.language,
                                    { model.navigate("profile/subscribers/$it") },
                                    { model.navigate("profile") },
                                    ::currentTarget,
                                )
                                val galleryScope = authSession.organizationScope()
                                GalleryAccessPanel(
                                    content,
                                    galleryScope,
                                    currentBrowse.language,
                                    { model.navigate("profile/organizations/gallery/$it") },
                                    {
                                        currentTarget() &&
                                            auth.state.value.organizationScope() == galleryScope
                                    },
                                )
                                CommunityDetailPanel(
                                    content,
                                    currentBrowse.language,
                                    community,
                                    capturedScope,
                                    { model.navigate("profile") },
                                    ::currentTarget,
                                    visibleAuthor = { currentSafety().visibility.allowsAuthor(it) },
                                    commentActions = { comment ->
                                        val target =
                                            SafetyReportTarget(
                                                SafetyTargetType.COMMENT,
                                                comment.id,
                                                comment.text.take(160),
                                                comment.authorId,
                                                SafetyTargetType.content(content.kind),
                                                content.id,
                                            )
                                        ContentSafetyTools(
                                            target,
                                            safetyState,
                                            currentBrowse.language,
                                            safety,
                                            {
                                                currentTarget() &&
                                                    currentSafety()
                                                        .visibility
                                                        .allowsAuthor(comment.authorId) &&
                                                    community.state.value.page?.let {
                                                        !it.cached &&
                                                            it.comments.any { row ->
                                                                row.id == comment.id
                                                            }
                                                    } == true
                                            },
                                            { model.navigate("profile") },
                                        )
                                    },
                                )
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        interactionHost?.let { interaction?.resume(it) }
        appLockHost?.onResume()
        LocalAuthSession.get(applicationContext).onForeground()
        reminders?.controller?.bindAuth(LocalAuthSession.get(applicationContext).state.value)
        reminders?.controller?.permissionReturned()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptReminderIntent(intent)
    }

    private fun acceptReminderIntent(intent: Intent?) {
        if (intent?.action != ReminderIntents.TAP) return
        ReminderIntents.request(intent)?.let { reminderNavigation?.offer(it) }
    }

    override fun onPause() {
        interactionHost?.let { interaction?.pause(it) }
        appLockHost?.onPause()
        LocalAuthSession.get(applicationContext).onHostPause()
        super.onPause()
    }

    override fun onStop() {
        appLockHost?.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        interactionHost?.let { interaction?.detach(it) }
        interactionHost = null
        interaction = null
        reminders = null
        reminderNavigation = null
        appLockHost?.close()
        appLockHost = null
        super.onDestroy()
    }
}
