import Combine
import FirebaseAuth
import SwiftUI

struct AuthFlowContainerView: View {
    let initialDestination: AuthFlowDestination
    @EnvironmentObject private var authState: AuthState

    private var requiresResolvedSession: Bool {
        switch initialDestination {
        case .emailVerification, .sessionRecovery, .multiFactorChallenge,
             .privilegedMultiFactorRequirement:
            return true
        case .landing, .login, .register, .passwordReset:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            destinationView(for: initialDestination)
                .toolbar {
                    if !requiresResolvedSession {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(AppStrings.Common.cancel) {
                                authState.dismissAuthFlow()
                            }
                        }
                    }
                }
        }
        .interactiveDismissDisabled(requiresResolvedSession)
    }

    @ViewBuilder
    private func destinationView(for destination: AuthFlowDestination) -> some View {
        switch destination {
        case .landing:
            AuthLandingView()
        case .login:
            LoginView()
        case .register:
            RegisterView()
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
        .observesKeyboardDismissTaps()
    }
}

struct AuthLandingView: View {
    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: AppStrings.Auth.landingTitle,
                subtitle: AppStrings.Auth.landingSubtitle
            )

            AppEditorSectionCard {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    NavigationLink {
                        LoginView()
                    } label: {
                        Text(AppStrings.Auth.signIn)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.iconButtonSize)
                            .background(AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("auth.landing.signIn")

                    NavigationLink {
                        RegisterView()
                    } label: {
                        Text(AppStrings.Auth.createAccount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: AppTheme.iconButtonSize)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                                    .strokeBorder(AppTheme.borderSubtle)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("auth.landing.register")
                }
            }
        }
        .navigationTitle(AppStrings.Auth.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.landing.screen")
    }
}

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(title: AppStrings.Auth.loginTitle, subtitle: AppStrings.Auth.loginSubtitle)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    EditorTextField(
                        AppStrings.Auth.email,
                        text: $email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )

                    EditorSecureField(AppStrings.Auth.password, text: $password, textContentType: .password)

                    if let errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
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

                    VStack(spacing: AppTheme.eventsMetadataSpacing) {
                        NavigationLink(AppStrings.Auth.forgotPassword) {
                            PasswordResetView(prefilledEmail: email)
                        }

                        NavigationLink(AppStrings.Auth.createAccountInstead) {
                            RegisterView(prefilledEmail: email)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }
        }
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

        isSubmitting = true
        errorMessage = nil

            Task {
                defer { isSubmitting = false }

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
        guard hasStartedEnteringCredentials, !canSubmit else { return nil }
        return validationErrors.first
    }

    private var hasStartedEnteringCredentials: Bool {
        !email.isEmpty || !password.isEmpty
    }
}

struct RegisterView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLockChoice = RegistrationAppLockChoice()
    @StateObject private var legalDocuments = RegistrationLegalDocumentsViewModel()
    @State private var email: String
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var displayName = ""
    @State private var telegramUsername = ""
    @State private var selectedFederalState: AustrianFederalState? = nil
    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
    @State private var confirmedMinimumAge = false
    @State private var analyticsConsentEnabled = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(title: AppStrings.Auth.registerTitle, subtitle: AppStrings.Auth.registerSubtitle)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    EditorTextField(AppStrings.Auth.displayName, text: $displayName, systemImage: "person", textContentType: .nickname, autocapitalization: .words)
                    EditorTextField(
                        AppStrings.Auth.email,
                        text: $email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )
                    EditorSecureField(AppStrings.Auth.password, text: $password, textContentType: .newPassword)
                    EditorSecureField(AppStrings.Auth.passwordRepeat, text: $repeatedPassword, systemImage: "lock.fill", textContentType: .newPassword)
                    EditorTextField(AppStrings.Auth.telegramUsername, text: $telegramUsername, systemImage: "paperplane", autocapitalization: .never, autocorrectionDisabled: true)

                    Picker(AppStrings.Auth.federalState, selection: $selectedFederalState) {
                        Text(AppStrings.Auth.selectFederalState).tag(Optional<AustrianFederalState>.none)
                        ForEach(AustrianFederalState.allCases) { state in
                            Text(AppStrings.FederalStates.title(for: state)).tag(Optional(state))
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("auth.register.federalState")
                }
            }

            AppEditorSectionCard {
                TermsPrivacyConsentView(
                    acceptedTerms: $acceptedTerms,
                    acceptedPrivacy: $acceptedPrivacy,
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

                    NavigationLink(AppStrings.Auth.signInInstead) {
                        LoginView()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .disabled(isSubmitting || appLockChoice.isAuthenticating)
        .onDisappear { appLockChoice.cancelPendingAuthentication() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { appLockChoice.cancelPendingAuthentication() }
            if phase == .active { appLockChoice.refreshAvailability() }
        }
        .onChange(of: legalDocuments.versionKey) { _, _ in
            acceptedTerms = false
            acceptedPrivacy = false
        }
        .task {
            await legalDocuments.load()
        }
        .navigationTitle(AppStrings.Auth.registerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.register.screen")
    }

    private func submit() {
        let errors = validationErrors

        guard errors.isEmpty,
              let selectedFederalState,
              let termsDocument = legalDocuments.terms,
              let privacyDocument = legalDocuments.privacy else {
            errorMessage = errors.first ?? AppStrings.Validation.authFederalStateRequired
            if legalDocuments.terms == nil || legalDocuments.privacy == nil {
                errorMessage = AppStrings.LegalCompliance.loadFailed
            }
            return
        }

        isSubmitting = true
        errorMessage = nil
        let now = Date()
        let draft = RegistrationProfileDraft(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            telegramUsername: telegramUsername,
            selectedFederalState: selectedFederalState,
            acceptedTermsAt: now,
            acceptedPrivacyAt: now,
            termsVersion: termsDocument.version,
            privacyVersion: privacyDocument.version,
            termsContentHash: termsDocument.contentHash,
            privacyContentHash: privacyDocument.contentHash,
            minimumAgeConfirmedAt: now,
            minimumAgeVersion: AuthService.currentMinimumAgeVersion,
            analyticsConsentEnabled: analyticsConsentEnabled,
            appLockAuthorization: appLockChoice.authorization
        )

        Task {
            defer { isSubmitting = false }

            do {
                try await AuthService.shared.register(draft: draft, password: password)
            } catch {
                errorMessage = readableRegistrationErrorMessage(error)
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
            confirmedMinimumAge: confirmedMinimumAge
        )
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty && legalDocuments.isReady
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
                    .accessibilityIdentifier("auth.register.analyticsConsent")
            } else {
                Toggle(isOn: $isEnabled) { consentTitle }
                    .accessibilityIdentifier("auth.register.analyticsConsent")
            }

            Text(AppStrings.Profile.analyticsCollectionSubtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.Auth.analyticsConsentHelp)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var consentTitle: some View {
        Text(AppStrings.Auth.analyticsConsentTitle)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmailVerificationView: View {
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
                title: AppStrings.Auth.emailVerificationTitle,
                subtitle: emailWasSent
                    ? AppStrings.Auth.emailVerificationDescription
                    : AppStrings.Auth.emailVerificationStillPending
            )

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    InlineMessageCard(style: messageStyle, message: displayedMessage)

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
    }

    private func resendVerification() {
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

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: AppStrings.Auth.title,
                subtitle: AppStrings.Auth.loadUserProfileFailed
            )

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    InlineMessageCard(
                        style: .error,
                        message: message ?? authState.errorMessage ?? AppStrings.Auth.loadUserProfileFailed
                    )

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
            }
        }
        .navigationTitle(AppStrings.Auth.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.session_recovery.screen")
        .onAppear {
            message = authState.errorMessage
        }
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
    @State private var email: String
    @State private var message: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(title: AppStrings.Auth.resetPasswordTitle, subtitle: AppStrings.Auth.resetPasswordSubtitle)

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    EditorTextField(
                        AppStrings.Auth.email,
                        text: $email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )

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
        }
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

        isSubmitting = true
        message = nil

        Task {
            defer { isSubmitting = false }

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
        validationErrors.isEmpty
    }

    private var validationHint: String? {
        guard !email.isEmpty, !canSubmit else { return nil }
        return validationErrors.first
    }
}

struct TermsPrivacyConsentView: View {
    @Binding var acceptedTerms: Bool
    @Binding var acceptedPrivacy: Bool
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

            Toggle(AppStrings.Auth.acceptTerms, isOn: $acceptedTerms)
                .accessibilityLabel(AppStrings.Auth.acceptTerms)
                .disabled(termsDocument == nil)

            Toggle(AppStrings.Auth.acceptPrivacy, isOn: $acceptedPrivacy)
                .accessibilityLabel(AppStrings.Auth.acceptPrivacy)
                .disabled(privacyDocument == nil)

            Toggle(AppStrings.Auth.confirmMinimumAge, isOn: $confirmedMinimumAge)
                .accessibilityLabel(AppStrings.Auth.confirmMinimumAge)

            VStack(alignment: .leading, spacing: 8) {
                if let termsDocument {
                    NavigationLink {
                        LegalMarkdownDocumentView(document: termsDocument)
                    } label: {
                        Label(AppStrings.Auth.reviewTerms, systemImage: "doc.text")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("auth.consent.termsLink")
                }

                if let privacyDocument {
                    NavigationLink {
                        LegalMarkdownDocumentView(document: privacyDocument)
                    } label: {
                        Label(AppStrings.Auth.reviewPrivacy, systemImage: "lock.doc")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("auth.consent.privacyLink")
                }
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

@MainActor
private final class RegistrationLegalDocumentsViewModel: ObservableObject {
    @Published private(set) var terms: LegalDocument?
    @Published private(set) var privacy: LegalDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: LegalDocumentRepository

    init(repository: LegalDocumentRepository? = nil) {
        self.repository = repository ?? FirestoreLegalDocumentRepository()
    }

    var isReady: Bool { terms != nil && privacy != nil }

    var versionKey: String {
        [terms?.version ?? "", privacy?.version ?? ""].joined(separator: "|")
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let termsDocument = repository.fetchAuthoritativeActiveDocument(type: .terms)
            async let privacyDocument = repository.fetchAuthoritativeActiveDocument(type: .privacy)
            let documents = try await (termsDocument, privacyDocument)
            guard documents.0.type == .terms,
                  documents.1.type == .privacy,
                  documents.0.contentHash != nil,
                  documents.1.contentHash != nil else {
                throw AppError.validationFailed
            }
            terms = documents.0
            privacy = documents.1
        } catch {
            terms = nil
            privacy = nil
            errorMessage = AppStrings.LegalCompliance.loadFailed
        }

        isLoading = false
    }
}

private func readableAuthErrorMessage(_ error: Error, fallback: String) -> String {
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
