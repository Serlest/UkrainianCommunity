import FirebaseAuth
import SwiftUI

struct AuthFlowContainerView: View {
    let initialDestination: AuthFlowDestination
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        NavigationStack {
            destinationView(for: initialDestination)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppStrings.Common.cancel) {
                            authState.dismissAuthFlow()
                        }
                    }
                }
        }
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
        case .passwordReset:
            PasswordResetView()
        }
    }
}

private struct AuthScreenScaffold<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                content
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.sectionSpacing)
            .padding(.bottom, AppTheme.sectionSpacing * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.iconButtonSize)
                            .background(AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("auth.landing.signIn")

                    NavigationLink {
                        RegisterView()
                    } label: {
                        Text(AppStrings.Auth.createAccount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.iconButtonSize)
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
                errorMessage = readableAuthErrorMessage(error, fallback: AppStrings.Auth.signInFailed)
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
        guard !canSubmit else { return nil }
        return validationErrors.first
    }
}

struct RegisterView: View {
    @State private var email: String
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var displayName = ""
    @State private var telegramUsername = ""
    @State private var selectedFederalState: AustrianFederalState = .tirol
    @State private var acceptedTerms = false
    @State private var acceptedPrivacy = false
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
                        ForEach(AustrianFederalState.allCases) { state in
                            Text(AppStrings.FederalStates.title(for: state)).tag(state)
                        }
                    }
                    .font(.subheadline)
                }
            }

            AppEditorSectionCard {
                TermsPrivacyConsentView(acceptedTerms: $acceptedTerms, acceptedPrivacy: $acceptedPrivacy)
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
        .navigationTitle(AppStrings.Auth.registerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.register.screen")
    }

    private func submit() {
        let errors = validationErrors

        guard errors.isEmpty else {
            errorMessage = errors.first
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
            termsVersion: AuthService.currentTermsVersion,
            privacyVersion: AuthService.currentPrivacyVersion
        )

        Task {
            defer { isSubmitting = false }

            do {
                _ = try await AuthService.shared.register(draft: draft, password: password)
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
            acceptedTerms: acceptedTerms,
            acceptedPrivacy: acceptedPrivacy
        )
    }

    private var canSubmit: Bool {
        validationErrors.isEmpty
    }

    private var validationHint: String? {
        guard !canSubmit else { return nil }
        return validationErrors.first
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
        guard !canSubmit else { return nil }
        return validationErrors.first
    }
}

struct TermsPrivacyConsentView: View {
    @Binding var acceptedTerms: Bool
    @Binding var acceptedPrivacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Auth.consentTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Auth.consentSubtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(AppStrings.Auth.acceptTerms, isOn: $acceptedTerms)
                .accessibilityLabel(AppStrings.Auth.acceptTerms)

            Toggle(AppStrings.Auth.acceptPrivacy, isOn: $acceptedPrivacy)
                .accessibilityLabel(AppStrings.Auth.acceptPrivacy)

            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    LegalDocumentView(document: .terms)
                } label: {
                    Label(AppStrings.Auth.reviewTerms, systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("auth.consent.termsLink")

                NavigationLink {
                    LegalDocumentView(document: .privacy)
                } label: {
                    Label(AppStrings.Auth.reviewPrivacy, systemImage: "lock.doc")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("auth.consent.privacyLink")
            }

            Text("\(AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion)) · \(AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion))")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}

private func readableAuthErrorMessage(_ error: Error, fallback: String) -> String {
    guard let authError = error as NSError? else { return fallback }
    guard let code = AuthErrorCode(rawValue: authError.code) else { return fallback }

    switch code {
    case .wrongPassword, .invalidCredential, .invalidEmail, .userNotFound:
        return fallback
    case .emailAlreadyInUse:
        return AppStrings.Auth.registrationFailed
    case .tooManyRequests:
        return fallback
    default:
        return fallback
    }
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
