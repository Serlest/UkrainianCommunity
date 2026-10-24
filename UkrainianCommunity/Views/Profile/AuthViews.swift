import Combine
import FirebaseAuth
import SwiftUI

struct AuthFlowContainerView: View {
    let initialDestination: AuthFlowDestination
    var allowsDismissal = true
    private let legalDocumentRepository: LegalDocumentRepository?
    @StateObject private var interaction = AuthInteractionCoordinator()
    @StateObject private var navigation: AuthEntryNavigation
    @EnvironmentObject private var authState: AuthState

    init(initialDestination: AuthFlowDestination, allowsDismissal: Bool = true, legalDocumentRepository: LegalDocumentRepository? = nil) {
        self.initialDestination = initialDestination
        self.allowsDismissal = allowsDismissal
        self.legalDocumentRepository = legalDocumentRepository
        _navigation = StateObject(wrappedValue: AuthEntryNavigation(root: initialDestination))
    }

    private var requiresResolvedSession: Bool {
        switch initialDestination {
        case .emailVerification, .socialRegistration, .sessionRecovery, .multiFactorChallenge,
             .privilegedMultiFactorRequirement:
            return true
        case .landing, .login, .register, .passwordReset:
            return false
        }
    }

    var body: some View {
        NavigationStack(path: $navigation.path) {
            destinationView(for: initialDestination)
                .navigationDestination(for: AuthEntryRoute.self) { route in
                    switch route {
                    case .methods: AuthLandingView()
                    case .login(let email): LoginView(prefilledEmail: email)
                    case .registration(let email, let method): RegisterView(prefilledEmail: email, startWithEmail: method, legalDocumentRepository: legalDocumentRepository)
                    case .passwordReset(let email): PasswordResetView(prefilledEmail: email)
                    }
                }
                .toolbar {
                    if allowsDismissal && !requiresResolvedSession {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(AppStrings.Common.cancel) {
                                authState.dismissAuthFlow()
                            }
                            .disabled(interaction.isBusy)
                        }
                    }
                }
        }
        .environment(\.authInteraction, interaction)
        .environment(\.authEntryNavigation, navigation)
        .disabled(interaction.isBusy)
        .interactiveDismissDisabled(!allowsDismissal || requiresResolvedSession || interaction.isBusy)
    }

    @ViewBuilder
    private func destinationView(for destination: AuthFlowDestination) -> some View {
        switch destination {
        case .landing:
            AuthLandingView()
        case .login:
            LoginView()
        case .register:
            RegisterView(legalDocumentRepository: legalDocumentRepository)
        case .socialRegistration:
            RegisterView(federated: true, legalDocumentRepository: legalDocumentRepository)
        case .emailVerification:
            EmailVerificationView()
        case .sessionRecovery:
            SessionRecoveryView()
        case .passwordReset:
            PasswordResetView()
        case .multiFactorChallenge:
            MultiFactorSignInView(
                coordinator: AuthService.shared.multiFactorSignIn
            )
        case .privilegedMultiFactorRequirement:
            PrivilegedMultiFactorRequirementView()
        }
    }
}

struct AuthScreenScaffold<Content: View>: View {
    @Environment(\.authInteraction) private var interaction
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                content
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.sectionSpacing)
            .padding(.bottom, AppTheme.sectionSpacing * 2)
            .appCenteredContent()
        }
        .keyboardDismissBackground {
            AppBackgroundView()
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(AppTheme.accentPrimaryForeground)
        .modifier(AuthNavigationBusyState(coordinator: interaction))
    }
}

private struct AuthNavigationBusyState: ViewModifier {
    let coordinator: AuthInteractionCoordinator?
    @ViewBuilder func body(content: Content) -> some View {
        if let coordinator {
            ObservedAuthNavigationState(coordinator: coordinator, content: content)
        } else { content }
    }
}

private struct ObservedAuthNavigationState<Content: View>: View {
    @ObservedObject var coordinator: AuthInteractionCoordinator
    let content: Content
    var body: some View { content.navigationBarBackButtonHidden(coordinator.isBusy) }
}

struct AuthLandingView: View {
    var body: some View {
        AuthScreenScaffold {
            AdaptiveBrandLockupView(layout: .horizontal)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            AuthHeaderView(
                title: AppStrings.Auth.landingTitle,
                subtitle: AppStrings.Auth.landingSubtitle
            )

            VStack(spacing: 12) {
                FederatedSignInButtons(showsHeading: false)
                PasskeySignInButton()

                NavigationLink(value: AuthEntryRoute.login(email: "")) {
                    AuthMethodButtonLabel(
                        title: AppStrings.Auth.continueWithEmail,
                        icon: .system("envelope")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth.landing.signIn")
            }

            NavigationLink(AppStrings.Auth.createAccountInstead, value: AuthEntryRoute.registration(email: "", emailMethod: false))
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("auth.landing.register")
        }
        .navigationTitle(AppStrings.Auth.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.landing.screen")
    }
}

struct LoginView: View {
    @Environment(\.authEntryNavigation) private var navigation
    @Environment(\.authInteraction) private var interaction
    @State private var email: String
    @State private var focus: AuthInput?
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    init(prefilledEmail: String = "") { _email = State(initialValue: prefilledEmail) }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(title: nil, subtitle: AppStrings.Auth.loginSubtitle)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    AuthFormField(title: AppStrings.Auth.email, text: $email, icon: "envelope", field: .email,
                                  focus: $focus, identifier: "auth.login.email", keyboard: .emailAddress,
                                  contentType: .username, onSubmit: { focus = .password })
                    AuthFormField(title: AppStrings.Auth.password, text: $password, icon: "lock", field: .password,
                                  focus: $focus, identifier: "auth.login.password", secure: true, preservesCredentialsOnRemoval: isSubmitting,
                                  contentType: .password, submitLabel: .go, onSubmit: { if canSubmit { submit() } }, returnKey: .go)

                    if let errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
                            .accessibilityIdentifier("auth.login.error")
                    } else if let validationHint {
                        InlineMessageCard(style: .info, message: validationHint)
                    }

                    PrimaryActionButton(
                        title: AppStrings.Auth.signInAction,
                        loadingTitle: AppStrings.Auth.signingIn,
                        isEnabled: canSubmit,
                        isLoading: isSubmitting,
                        systemImage: "arrow.right"
                    ) {
                        submit()
                    }
                    .accessibilityIdentifier("auth.login.submit")

                    NavigationLink(AppStrings.Auth.forgotPassword, value: AuthEntryRoute.passwordReset(email: email))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("auth.login.forgotPassword")
                }
            }
            AuthModeLink(title: AppStrings.Auth.createAccountInstead,
                         route: .registration(email: email, emailMethod: true))
                .accessibilityIdentifier("auth.login.register")
            AuthModeLink(title: AppStrings.Auth.chooseAnotherMethod, route: .methods)
                .accessibilityIdentifier("auth.login.changeMethod")
        }
        .onAppear {
            if let resumedEmail = navigation?.resumedLoginEmail {
                if email != resumedEmail { password = "" }
                email = resumedEmail
                navigation?.resumedLoginEmail = nil
            }
        }
        .onChange(of: email) { _, _ in errorMessage = nil }
        .onChange(of: password) { _, _ in errorMessage = nil }
        .navigationTitle(AppStrings.Auth.loginTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.login.screen")
    }

    private func submit() {
        let errors = validationErrors
        guard errors.isEmpty else {
            errorMessage = errors.first
            return
        }

        guard !isSubmitting, let request = AuthInteractionCoordinator.begin(in: interaction) else { return }
        focus = nil
        isSubmitting = true
        errorMessage = nil

            Task {
                defer { isSubmitting = false; interaction?.finish(request) }

                do {
                    _ = try await AuthService.shared.signIn(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                } catch {
                    if error as? AuthMultiFactorFlowError == .secondFactorRequired {
                        errorMessage = nil
                        return
                    }

                    if let verificationError = error as? AuthVerificationError {
                        switch verificationError {
                        case .emailNotVerified:
                            errorMessage = nil
                        case .accountDeletionCompleted:
                            errorMessage = AppStrings.Profile.deleteAccountCompleted
                        default:
                            errorMessage = readableAuthErrorMessage(error, fallback: AppStrings.Auth.signInFailed)
                        }
                    } else {
                        errorMessage = readableAuthErrorMessage(error, fallback: AppStrings.Auth.signInFailed)
                    }
                }
            }
        }

    private var validationErrors: [String] {
        validationService.validateLogin(email: email, password: password)
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty
    }

    private var validationHint: String? {
        guard hasStartedEnteringCredentials, focus == nil, !canSubmit else { return nil }
        return validationErrors.first
    }

    private var hasStartedEnteringCredentials: Bool {
        !email.isEmpty || !password.isEmpty
    }
}

struct RegisterView: View {
    @Environment(\.authInteraction) private var interaction
    @Environment(\.authEntryNavigation) private var navigation
    @State private var focus: AuthInput?
    @State private var isShowingConsents = false
    @State private var isShowingRegionPicker = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasEnteredBackground = false
    @StateObject private var appLockChoice = RegistrationAppLockChoice()
    @StateObject private var legalDocuments: RegistrationLegalDocumentsViewModel
    @State private var email: String
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var displayName = ""
    @State private var telegramUsername = ""
    @State private var selectedFederalState: AustrianFederalState? = nil
    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
    @State private var reviewedTermsVersion: String?
    @State private var reviewedPrivacyVersion: String?
    @State private var confirmedMinimumAge = false
    @State private var analyticsConsentEnabled = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isEmailMethodSelected: Bool
    private let validationService = AuthValidationService()
    private let federated: Bool

    init(prefilledEmail: String = "", federated: Bool = false, startWithEmail: Bool = false, legalDocumentRepository: LegalDocumentRepository? = nil) {
        self.federated = federated
        _legalDocuments = StateObject(wrappedValue: RegistrationLegalDocumentsViewModel(repository: legalDocumentRepository))
        _email = State(initialValue: federated ? AuthService.shared.currentUser?.email ?? "" : prefilledEmail)
        _displayName = State(initialValue: federated ? AuthService.shared.currentUser?.displayName ?? "" : "")
        _isEmailMethodSelected = State(initialValue: federated || startWithEmail || !prefilledEmail.isEmpty)
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: nil,
                subtitle: federated
                    ? AppStrings.Auth.finishRegistrationSubtitle
                    : (isEmailMethodSelected ? AppStrings.Auth.registerSubtitle : AppStrings.Auth.registerMethodsSubtitle)
            )

            if !federated && !isEmailMethodSelected {
                FederatedSignInButtons(showsHeading: false)

                NavigationLink(value: AuthEntryRoute.registration(email: email, emailMethod: true)) {
                    AuthMethodButtonLabel(
                        title: AppStrings.Auth.continueWithEmail,
                        icon: .system("envelope")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth.register.emailMethod")

                AuthModeLink(title: AppStrings.Auth.signInInstead, route: .login(email: email))
                    .accessibilityIdentifier("auth.register.signIn")
            } else {
                if !federated {
                    Button(AppStrings.Auth.chooseAnotherMethod) {
                        focus = nil
                        withAnimation { navigation?.switchMode(to: .registration(email: email, emailMethod: false)) }
                    }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("auth.register.changeMethod")
                }

                registrationForm
            }
        }
        .navigationDestination(isPresented: $isShowingConsents) { confirmationScreen }
        .navigationDestination(isPresented: $isShowingRegionPicker) { AuthFederalStatePicker(selection: $selectedFederalState) }
        .disabled(isSubmitting || appLockChoice.isAuthenticating)
        .onChange(of: email) { _, _ in errorMessage = nil }
        .onChange(of: password) { _, _ in errorMessage = nil }
        .onChange(of: displayName) { _, _ in errorMessage = nil }
        .onChange(of: selectedFederalState) { _, _ in errorMessage = nil }
        .onDisappear { appLockChoice.cancelPendingAuthentication() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                hasEnteredBackground = true
                appLockChoice.cancelPendingAuthentication()
            }
            if phase == .active, hasEnteredBackground {
                hasEnteredBackground = false
                appLockChoice.refreshAvailability()
                Task { await legalDocuments.refreshIfStale() }
            }
        }
        .onChange(of: legalDocuments.versionKey) { _, _ in
            acceptedTerms = false
            acceptedPrivacy = false
            reviewedTermsVersion = nil
            reviewedPrivacyVersion = nil
        }
        .task {
            guard isEmailMethodSelected else { return }
            await legalDocuments.refreshIfStale()
        }
        .navigationTitle(federated ? AppStrings.Auth.finishRegistrationTitle : AppStrings.Auth.registerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.register.screen")
    }

    private var registrationForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            AuthRegistrationProgress(step: 1)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    AuthFormField(title: AppStrings.Auth.displayName, text: $displayName, icon: "person", field: .displayName,
                                  focus: $focus, identifier: "auth.register.displayName", contentType: .nickname,
                                  capitalization: .words, onSubmit: { focus = federated ? nil : .email })
                    AuthFormField(title: AppStrings.Auth.email, text: $email, icon: "envelope", field: .email,
                                  focus: $focus, identifier: "auth.register.email", keyboard: .emailAddress,
                                  contentType: .emailAddress, onSubmit: { focus = .password })
                        .disabled(federated)
                    if federated && email.isEmpty {
                        InlineMessageCard(style: .error, message: AppStrings.Auth.providerEmailMissing)
                    }
                    if !federated {
                        AuthFormField(title: AppStrings.Auth.password, text: $password, icon: "lock", field: .password,
                                      focus: $focus, identifier: "auth.register.password", secure: true, preservesCredentialsOnRemoval: isSubmitting,
                                      contentType: .newPassword, onSubmit: { focus = .repeatedPassword })
                        Text(AuthPresentationStrings.passwordHelp).font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        AuthFormField(title: AppStrings.Auth.passwordRepeat, text: $repeatedPassword, icon: "lock.fill", field: .repeatedPassword,
                                      focus: $focus, identifier: "auth.register.repeatedPassword", secure: true, preservesCredentialsOnRemoval: isSubmitting,
                                      contentType: .newPassword, submitLabel: .done, onSubmit: { focus = nil }, returnKey: .done)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Auth.federalState).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                            .accessibilityHidden(true)
                        Button {
                            focus = nil
                            isShowingRegionPicker = true
                        } label: {
                            HStack {
                                Text(selectedFederalState.map { AppStrings.FederalStates.title(for: $0) } ?? AppStrings.Auth.selectFederalState)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius))
                            .overlay { RoundedRectangle(cornerRadius: AppTheme.inputRadius).strokeBorder(AppTheme.borderSubtle) }
                        }
                        .accessibilityLabel(AppStrings.Auth.federalState)
                        .accessibilityValue(selectedFederalState.map { AppStrings.FederalStates.title(for: $0) } ?? AppStrings.Auth.selectFederalState)
                        .accessibilityIdentifier("auth.register.federalState")
                    }

                    DisclosureGroup(AuthPresentationStrings.optionalDetails) {
                        AuthFormField(title: AppStrings.Auth.telegramUsername, text: $telegramUsername, icon: "paperplane", field: .telegram,
                                      focus: $focus, identifier: "auth.register.telegram", submitLabel: .done, onSubmit: { focus = nil })
                            .padding(.top, 10)
                    }
                    .font(.subheadline)
                }
            }

            if let detailHint { InlineMessageCard(style: .info, message: detailHint) }
            PrimaryActionButton(title: AuthPresentationStrings.continueAction,
                                isEnabled: credentialsValidationErrors.isEmpty, systemImage: "arrow.right") {
                focus = nil
                isShowingConsents = true
            }
            .accessibilityIdentifier("auth.register.continue")
            AuthModeLink(title: AppStrings.Auth.signInInstead, route: .login(email: email))
                .accessibilityIdentifier("auth.register.signIn")
        }
    }

    private var confirmationScreen: some View {
        AuthScreenScaffold {
            AuthRegistrationProgress(step: 2)
            Text(email).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled).accessibilityIdentifier("auth.register.confirmationEmail")
            InlineMessageCard(style: .info, message: AppStrings.Auth.registrationExpiryNotice)
            AppEditorSectionCard {
                TermsPrivacyConsentView(
                    acceptedTerms: $acceptedTerms,
                    acceptedPrivacy: $acceptedPrivacy,
                    reviewedTermsVersion: $reviewedTermsVersion,
                    reviewedPrivacyVersion: $reviewedPrivacyVersion,
                    confirmedMinimumAge: $confirmedMinimumAge,
                    termsDocument: legalDocuments.terms,
                    privacyDocument: legalDocuments.privacy,
                    isLoadingDocuments: legalDocuments.isLoading,
                    documentErrorMessage: legalDocuments.errorMessage,
                    retryDocuments: {
                        Task { await legalDocuments.load() }
                    }
                )
            }

            AppEditorSectionCard {
                RegistrationAnalyticsConsentView(isEnabled: $analyticsConsentEnabled)
            }

            AppEditorSectionCard {
                RegistrationBiometricLockView(choice: appLockChoice)
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    if let errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
                    } else if let validationHint {
                        InlineMessageCard(style: .info, message: validationHint)
                    }

                    PrimaryActionButton(
                        title: AppStrings.Auth.createAccountAction,
                        loadingTitle: AppStrings.Auth.creatingAccount,
                        isEnabled: canSubmit,
                        isLoading: isSubmitting,
                        systemImage: "person.badge.plus"
                    ) {
                        submit()
                    }
                    .accessibilityIdentifier("auth.register.submit")

                    if federated {
                        Button(AppStrings.Auth.changeAccount) {
                            Task { _ = await AuthService.shared.signOut() }
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    } else {
                        AuthModeLink(title: AppStrings.Auth.signInInstead, route: .login(email: email))
                            .accessibilityIdentifier("auth.register.signIn")
                    }
                }
            }
        }
        .navigationTitle(AuthPresentationStrings.confirmationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSubmitting || appLockChoice.isAuthenticating)
        .accessibilityIdentifier("auth.register.confirmation")
    }


    private func submit() {
        let errors = validationErrors

        guard errors.isEmpty,
              let selectedFederalState,
              let termsDocument = legalDocuments.terms,
              let privacyDocument = legalDocuments.privacy,
              reviewedTermsVersion == termsDocument.version,
              reviewedPrivacyVersion == privacyDocument.version else {
            errorMessage = errors.first
                ?? (legalDocuments.terms == nil || legalDocuments.privacy == nil
                    ? AppStrings.LegalCompliance.loadFailed
                    : AppStrings.LegalCompliance.reviewInstruction)
            return
        }

        guard !isSubmitting, let request = AuthInteractionCoordinator.begin(in: interaction) else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false; interaction?.finish(request) }

            // A legal version may change while the registration form is open.
            // Keep the form, but require review of the newly published text.
            let currentDocuments: (terms: LegalDocument, privacy: LegalDocument)
            do {
                currentDocuments = try await legalDocuments.refreshForSubmission()
            } catch {
                errorMessage = AuthFailureMessage.text(for: error, fallback: AppStrings.LegalCompliance.loadFailed)
                return
            }
            let currentTerms = currentDocuments.terms
            let currentPrivacy = currentDocuments.privacy
            guard currentTerms.version == termsDocument.version,
                  currentPrivacy.version == privacyDocument.version else {
                errorMessage = AppStrings.Auth.registrationLegalChanged
                return
            }

            let now = Date()
            let draft = RegistrationProfileDraft(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                telegramUsername: telegramUsername,
                selectedFederalState: selectedFederalState,
                acceptedTermsAt: now,
                acceptedPrivacyAt: now,
                termsVersion: currentTerms.version,
                privacyVersion: currentPrivacy.version,
                termsContentHash: currentTerms.contentHash,
                privacyContentHash: currentPrivacy.contentHash,
                minimumAgeConfirmedAt: now,
                minimumAgeVersion: AuthService.currentMinimumAgeVersion,
                analyticsConsentEnabled: analyticsConsentEnabled,
                appLockAuthorization: appLockChoice.authorization
            )

            do {
                if federated {
                    try await AuthService.shared.completeFederatedRegistration(draft: draft)
                } else {
                    try await AuthService.shared.register(draft: draft, password: password)
                }
            } catch {
                if let registrationError = error as? RegistrationError,
                   case .profilePermission = registrationError {
                    await legalDocuments.load()
                    errorMessage = legalDocuments.versionKey != "\(currentTerms.version)|\(currentPrivacy.version)"
                        ? AppStrings.Auth.registrationLegalChanged
                        : readableRegistrationErrorMessage(error)
                } else {
                    errorMessage = readableRegistrationErrorMessage(error)
                }
            }
        }
    }

    private var validationErrors: [String] {
        validationService.validateRegistration(
            email: email,
            password: password,
            repeatedPassword: repeatedPassword,
            displayName: displayName,
            selectedFederalState: selectedFederalState,
            acceptedTerms: acceptedTerms,
            acceptedPrivacy: acceptedPrivacy,
            confirmedMinimumAge: confirmedMinimumAge,
            requiresPassword: !federated
        )
    }

    private var credentialsValidationErrors: [String] {
        validationService.validateRegistration(email: email, password: password, repeatedPassword: repeatedPassword,
            displayName: displayName, selectedFederalState: selectedFederalState, acceptedTerms: true,
            acceptedPrivacy: true, confirmedMinimumAge: true, requiresPassword: !federated)
    }
    private var detailHint: String? {
        guard hasStartedRegistration, focus == nil else { return nil }
        return credentialsValidationErrors.first
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty
            && legalDocuments.isReady
            && reviewedTermsVersion == legalDocuments.terms?.version
            && reviewedPrivacyVersion == legalDocuments.privacy?.version
    }

    private var validationHint: String? {
        guard hasStartedRegistration, !canSubmit else { return nil }
        return validationErrors.first
    }

    private var hasStartedRegistration: Bool {
        !email.isEmpty
            || !password.isEmpty
            || !repeatedPassword.isEmpty
            || !displayName.isEmpty
            || !telegramUsername.isEmpty
            || selectedFederalState != nil
            || acceptedTerms
            || acceptedPrivacy
            || confirmedMinimumAge
    }
}

struct RegistrationAnalyticsConsentView: View {
    @Binding var isEnabled: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                consentTitle
                Toggle(AppStrings.Auth.analyticsConsentTitle, isOn: $isEnabled)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(AppStrings.Auth.analyticsConsentTitle)
                    .tint(AppTheme.accentPrimary)
                    .accessibilityIdentifier("auth.register.analyticsConsent")
            } else {
                Toggle(isOn: $isEnabled) { consentTitle }
                    .tint(AppTheme.accentPrimary)
                    .accessibilityIdentifier("auth.register.analyticsConsent")
            }

            Text(AppStrings.Auth.analyticsConsentHelp)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(AppStrings.Auth.analyticsDetails) {
                Text(AppStrings.Profile.analyticsCollectionSubtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("auth.register.analyticsDetails")
        }
    }

    private var consentTitle: some View {
        Text(AppStrings.Auth.analyticsConsentTitle)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmailVerificationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasEnteredBackground = false
    @EnvironmentObject private var authState: AuthState
    @State private var message: String?
    @State private var isResending = false
    @State private var isChecking = false
    @State private var isSigningOut = false

    private var pendingEmail: String {
        authState.pendingVerificationEmail ?? authState.user?.email ?? ""
    }

    private var isBusy: Bool {
        isResending || isChecking || isSigningOut
    }

    private var emailWasSent: Bool {
        authState.emailVerificationNotice == .emailSent
    }

    private var displayedMessage: String {
        if let message { return message }
        if let authError = authState.errorMessage { return authError }
        return emailWasSent
            ? AppStrings.Auth.emailVerificationSent
            : AppStrings.Auth.emailVerificationStillPending
    }

    private var messageStyle: InlineMessageStyle {
        let successMessages = [
            AppStrings.Auth.emailVerificationSent,
            AppStrings.Auth.emailVerificationResent,
            AppStrings.Auth.emailVerificationSuccess,
            AppStrings.Auth.emailVerificationAlreadyVerified
        ]

        if successMessages.contains(displayedMessage) {
            return .success
        }

        if displayedMessage == AppStrings.Auth.emailVerificationStillPending {
            return .info
        }

        return .error
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: nil,
                subtitle: emailWasSent
                    ? AppStrings.Auth.emailVerificationDescription
                    : AppStrings.Auth.emailVerificationStillPending
            )

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    InlineMessageCard(style: messageStyle, message: displayedMessage)
                    InlineMessageCard(style: .info, message: AppStrings.Auth.registrationExpiryNotice)

                    if !pendingEmail.isEmpty {
                        if emailWasSent {
                            Text(AppStrings.Auth.emailVerificationSentTo)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Text(pendingEmail)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    if emailWasSent {
                        InlineMessageCard(style: .info, message: AppStrings.Auth.emailVerificationSpamHint)
                    }

                    PrimaryActionButton(
                        title: AppStrings.Auth.emailVerificationCheck,
                        loadingTitle: AppStrings.Auth.emailVerificationChecking,
                        isEnabled: !isBusy,
                        isLoading: isChecking,
                        systemImage: "checkmark.seal"
                    ) {
                        checkVerification()
                    }
                    .accessibilityIdentifier("auth.verification.check")

                    PrimaryActionButton(
                        title: AppStrings.Auth.emailVerificationResend,
                        loadingTitle: AppStrings.Auth.emailVerificationResending,
                        isEnabled: !isBusy,
                        isLoading: isResending,
                        systemImage: "arrow.clockwise"
                    ) {
                        resendVerification()
                    }
                    .accessibilityIdentifier("auth.verification.resend")

                    Button(AppStrings.Auth.emailVerificationChangeAccount) {
                        signOutAndChangeAccount()
                    }
                    .appActionButtonStyle(.secondary)
                    .frame(minHeight: AppTheme.iconButtonSize)
                    .disabled(isBusy)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(AppStrings.Auth.emailVerificationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.verify.screen")
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { hasEnteredBackground = true }
            if phase == .active, hasEnteredBackground {
                hasEnteredBackground = false
                guard authState.isVerificationPending, !isBusy else { return }
                checkVerification()
            }
        }
    }

    private func resendVerification() {
        guard !isBusy else { return }
        isResending = true

        Task {
            defer { isResending = false }

            do {
                try await AuthService.shared.sendEmailVerification()
                message = AppStrings.Auth.emailVerificationResent
            } catch {
                message = readableVerificationErrorMessage(error, fallback: AppStrings.Auth.emailVerificationResendFailed)
            }
        }
    }

    private func checkVerification() {
        guard !isBusy else { return }
        isChecking = true

        Task {
            defer { isChecking = false }

            do {
                _ = try await AuthService.shared.verifyEmailAndAuthenticate()
                message = AppStrings.Auth.emailVerificationSuccess
            } catch {
                if error is AuthVerificationError {
                    message = readableVerificationErrorMessage(error, fallback: AppStrings.Auth.emailVerificationCheckFailed)
                    return
                }

                message = readableAuthErrorMessage(error, fallback: AppStrings.Auth.emailVerificationCheckFailed)
            }
        }
    }

    private func signOutAndChangeAccount() {
        isSigningOut = true
        message = nil

        Task {
            defer { isSigningOut = false }
            if await AuthService.shared.signOut() {
                authState.dismissAuthFlow()
            } else {
                message = AppStrings.Profile.signOutFailed
            }
        }
    }
}

struct SessionRecoveryView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var isRetrying = false
    @State private var isSigningOut = false
    @State private var message: String?

    private var isBusy: Bool {
        isRetrying || isSigningOut
    }

    private var isConnectionFailure: Bool { authState.sessionRecoveryFailure == .connection }

    var body: some View {
        AuthScreenScaffold {
            if isConnectionFailure {
                UnifiedEmptyStateCard(
                    systemImage: "wifi.slash",
                    title: AppStrings.Startup.connectionTitle,
                    message: AppStrings.Startup.connectionMessage,
                    messageLineLimit: nil
                ) {
                    recoveryActions
                }
            } else {
                AuthHeaderView(
                    title: nil,
                    subtitle: AppStrings.Auth.loadUserProfileFailed
                )

                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        InlineMessageCard(
                            style: .error,
                            message: message ?? authState.errorMessage ?? AppStrings.Auth.loadUserProfileFailed
                        )
                        recoveryActions
                    }
                }
            }
        }
        .navigationTitle(AppStrings.Auth.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.session_recovery.screen")
        .onAppear { message = authState.errorMessage }
    }

    @ViewBuilder
    private var recoveryActions: some View {
        if isConnectionFailure, message == AppStrings.Profile.signOutFailed {
            InlineMessageCard(style: .error, message: AppStrings.Profile.signOutFailed)
        }
        PrimaryActionButton(
            title: AppStrings.Action.retry,
            isEnabled: !isBusy,
            isLoading: isRetrying,
            systemImage: "arrow.clockwise"
        ) {
            retrySession()
        }
        .accessibilityIdentifier("auth.session_recovery.retry")

        Button(AppStrings.Auth.emailVerificationChangeAccount) {
            signOut()
        }
        .appActionButtonStyle(.secondary)
        .frame(minHeight: AppTheme.iconButtonSize)
        .disabled(isBusy)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("auth.session_recovery.sign_out")
    }

    private func retrySession() {
        isRetrying = true
        message = nil

        Task {
            await AuthService.shared.retryUnavailableSession()
            message = authState.errorMessage
            isRetrying = false
        }
    }

    private func signOut() {
        isSigningOut = true
        message = nil

        Task {
            if await AuthService.shared.signOut() {
                authState.dismissAuthFlow()
            } else {
                message = AppStrings.Profile.signOutFailed
            }
            isSigningOut = false
        }
    }
}

struct PasswordResetView: View {
    @Environment(\.authInteraction) private var interaction
    @State private var focus: AuthInput?
    @State private var email: String
    @State private var message: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(title: nil, subtitle: AppStrings.Auth.resetPasswordSubtitle)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    AuthFormField(title: AppStrings.Auth.email, text: $email, icon: "envelope", field: .email,
                                  focus: $focus, identifier: "auth.reset.email", keyboard: .emailAddress,
                                  contentType: .emailAddress, submitLabel: .send, onSubmit: { if canSubmit { submit() } })

                    if let message {
                        InlineMessageCard(
                            style: message == AppStrings.Auth.resetPasswordSuccess ? .success : .error,
                            message: message
                        )
                    } else if let validationHint {
                        InlineMessageCard(style: .info, message: validationHint)
                    }

                    PrimaryActionButton(
                        title: AppStrings.Auth.sendResetLink,
                        loadingTitle: AppStrings.Auth.resetPasswordSending,
                        isEnabled: canSubmit,
                        isLoading: isSubmitting,
                        systemImage: "envelope.badge"
                    ) {
                        submit()
                    }
                    .accessibilityIdentifier("auth.reset.submit")
                }
            }
            if message == AppStrings.Auth.resetPasswordSuccess {
                AuthModeLink(title: AuthPresentationStrings.backToSignIn, route: .login(email: email))
                    .accessibilityIdentifier("auth.reset.backToSignIn")
            }
        }
        .onChange(of: email) { _, _ in message = nil }
        .navigationTitle(AppStrings.Auth.resetPasswordTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.reset.screen")
    }

    private func submit() {
        let errors = validationErrors
        guard errors.isEmpty else {
            message = errors.first
            return
        }

        guard !isSubmitting, let request = AuthInteractionCoordinator.begin(in: interaction) else { return }
        focus = nil
        isSubmitting = true
        message = nil

        Task {
            defer { isSubmitting = false; interaction?.finish(request) }

            do {
                try await AuthService.shared.sendPasswordReset(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                message = AppStrings.Auth.resetPasswordSuccess
            } catch {
                message = readableAuthErrorMessage(error, fallback: AppStrings.Auth.resetPasswordFailed)
            }
        }
    }

    private var validationErrors: [String] {
        validationService.validatePasswordReset(email: email)
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty && message != AppStrings.Auth.resetPasswordSuccess
    }

    private var validationHint: String? {
        guard !email.isEmpty, focus == nil, message == nil, !canSubmit else { return nil }
        return validationErrors.first
    }
}

struct TermsPrivacyConsentView: View {
    @Binding var acceptedTerms: Bool
    @Binding var acceptedPrivacy: Bool
    @Binding var reviewedTermsVersion: String?
    @Binding var reviewedPrivacyVersion: String?
    @Binding var confirmedMinimumAge: Bool
    let termsDocument: LegalDocument?
    let privacyDocument: LegalDocument?
    let isLoadingDocuments: Bool
    let documentErrorMessage: String?
    let retryDocuments: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Auth.consentTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Auth.consentSubtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.LegalCompliance.reviewInstruction)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLoadingDocuments {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let documentErrorMessage {
                InlineMessageCard(style: .error, message: documentErrorMessage)
                Button(action: retryDocuments) {
                    Label(AppStrings.Action.retry, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                if let termsDocument {
                    NavigationLink {
                        LegalMarkdownDocumentView(document: termsDocument) { reviewedTermsVersion = termsDocument.version }
                    } label: {
                        Label(AppStrings.Auth.reviewTerms, systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("auth.consent.termsLink")
                }
                Toggle(AppStrings.Auth.acceptTerms, isOn: $acceptedTerms)
                    .tint(AppTheme.accentPrimary)
                    .disabled(termsDocument == nil || reviewedTermsVersion != termsDocument?.version)
                    .accessibilityIdentifier("auth.consent.terms")
                Divider()
                if let privacyDocument {
                    NavigationLink {
                        LegalMarkdownDocumentView(document: privacyDocument) { reviewedPrivacyVersion = privacyDocument.version }
                    } label: {
                        Label(AppStrings.Auth.reviewPrivacy, systemImage: "lock.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("auth.consent.privacyLink")
                }
                Toggle(AppStrings.Auth.acceptPrivacy, isOn: $acceptedPrivacy)
                    .tint(AppTheme.accentPrimary)
                    .disabled(privacyDocument == nil || reviewedPrivacyVersion != privacyDocument?.version)
                    .accessibilityIdentifier("auth.consent.privacy")
                Divider()
                Toggle(AppStrings.Auth.confirmMinimumAge, isOn: $confirmedMinimumAge)
                    .tint(AppTheme.accentPrimary)
                    .accessibilityIdentifier("auth.consent.age")
            }

            if let termsDocument, let privacyDocument {
                Text("\(AppStrings.authCurrentTermsVersion(termsDocument.version)) · \(AppStrings.authCurrentPrivacyVersion(privacyDocument.version))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private func readableAuthErrorMessage(_ error: Error, fallback: String) -> String {
    let mapped = AuthFailureMessage.text(for: error, fallback: fallback)
    if mapped != fallback { return mapped }
    if let verificationError = error as? AuthVerificationError {
        switch verificationError {
        case .alreadyVerified:
            return AppStrings.Auth.emailVerificationAlreadyVerified
        case .emailNotVerified:
            return AppStrings.Auth.emailVerificationStillPending
        case .checkFailed:
            return AppStrings.Auth.emailVerificationCheckFailed
        case .tooManyRequests:
            return AppStrings.Auth.emailVerificationTooManyRequests
        case .accountDeletionCompleted:
            return AppStrings.Profile.deleteAccountCompleted
        case .noCurrentUser, .unknown:
            return fallback
        }
    }

    guard let authError = error as NSError? else { return fallback }
    guard let code = AuthErrorCode(rawValue: authError.code) else { return fallback }

    switch code {
    case .wrongPassword, .invalidCredential, .invalidEmail, .userNotFound:
        return fallback
    case .tooManyRequests:
        return AppStrings.Auth.emailVerificationTooManyRequests
    case .emailAlreadyInUse:
        return AppStrings.Auth.registrationFailed
    default:
        return fallback
    }
}

private func readableVerificationErrorMessage(_ error: Error, fallback: String) -> String {
    readableAuthErrorMessage(error, fallback: fallback)
}

private func readableRegistrationErrorMessage(_ error: Error) -> String {
    switch error {
    case RegistrationError.invalidEmail:
        return AppStrings.Auth.registrationInvalidEmail
    case RegistrationError.emailAlreadyInUse:
        return AppStrings.Auth.registrationEmailAlreadyInUse
    case RegistrationError.weakPassword:
        return AppStrings.Auth.registrationWeakPassword
    case RegistrationError.network:
        return AppStrings.Auth.registrationNetworkError
    case RegistrationError.operationNotAllowed:
        return AppStrings.Auth.registrationOperationNotAllowed
    case RegistrationError.profilePermission:
        return AppStrings.Auth.registrationProfilePermissionError
    case RegistrationError.profileNetwork:
        return AppStrings.Auth.registrationProfileNetworkError
    case RegistrationError.profileUnknown:
        return AppStrings.Auth.registrationProfileUnknownError
    case RegistrationError.unknownAuth:
        return AppStrings.Auth.registrationUnknownError
    default:
        return AppStrings.Auth.registrationFailed
    }
}
