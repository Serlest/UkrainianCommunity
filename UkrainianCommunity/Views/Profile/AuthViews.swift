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
                        Button(AppStrings.Common.ok) {
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

struct AuthLandingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStrings.Auth.landingTitle)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Auth.landingSubtitle)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    NavigationLink {
                        LoginView()
                    } label: {
                        Text(AppStrings.Auth.signIn)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentPrimary)
                    .accessibilityIdentifier("auth.landing.signIn")

                    NavigationLink {
                        RegisterView()
                    } label: {
                        Text(AppStrings.Auth.createAccount)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("auth.landing.register")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(AppStrings.Auth.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.landing.screen")
    }
}

struct LoginView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    private let validationService = AuthValidationService()

    var body: some View {
        Form {
            Section {
                TextField(AppStrings.Auth.email, text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Auth.email)

                SecureField(AppStrings.Auth.password, text: $password)
                    .textContentType(.password)
                    .accessibilityLabel(AppStrings.Auth.password)
            } footer: {
                Text(AppStrings.Auth.landingSubtitle)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView(AppStrings.Auth.signingIn)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(AppStrings.Auth.signInAction)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.login.submit")

                NavigationLink(AppStrings.Auth.forgotPassword) {
                    PasswordResetView(prefilledEmail: email)
                }

                NavigationLink(AppStrings.Auth.createAccountInstead) {
                    RegisterView(prefilledEmail: email)
                }
            }
        }
        .navigationTitle(AppStrings.Auth.loginTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.login.screen")
    }

    private func submit() {
        let errors = validationService.validateLogin(email: email, password: password)
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
}

struct RegisterView: View {
    @EnvironmentObject private var authState: AuthState
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
        Form {
            Section {
                TextField(AppStrings.Auth.displayName, text: $displayName)
                    .textInputAutocapitalization(.words)
                    .textContentType(.nickname)
                    .accessibilityLabel(AppStrings.Auth.displayName)

                TextField(AppStrings.Auth.email, text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Auth.email)

                SecureField(AppStrings.Auth.password, text: $password)
                    .textContentType(.newPassword)
                    .accessibilityLabel(AppStrings.Auth.password)

                SecureField(AppStrings.Auth.passwordRepeat, text: $repeatedPassword)
                    .textContentType(.newPassword)
                    .accessibilityLabel(AppStrings.Auth.passwordRepeat)

                TextField(AppStrings.Auth.telegramUsername, text: $telegramUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Auth.telegramUsername)

                Picker(AppStrings.Auth.federalState, selection: $selectedFederalState) {
                    ForEach(AustrianFederalState.allCases) { state in
                        Text(AppStrings.FederalStates.title(for: state)).tag(state)
                    }
                }
            }

            Section {
                TermsPrivacyConsentView(
                    acceptedTerms: $acceptedTerms,
                    acceptedPrivacy: $acceptedPrivacy
                )
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                            Text(AppStrings.Auth.creatingAccount)
                                .fontWeight(.semibold)
                        } else {
                            Text(AppStrings.Auth.createAccountAction)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(canSubmit ? AppTheme.accentPrimary : AppTheme.borderSubtle)
                .disabled(isSubmitting || !canSubmit)
                .accessibilityIdentifier("auth.register.submit")
            } footer: {
                if let validationHint {
                    Text(validationHint)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                NavigationLink(AppStrings.Auth.signInInstead) {
                    LoginView()
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
        Form {
            Section {
                TextField(AppStrings.Auth.email, text: $email)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityLabel(AppStrings.Auth.email)
            } footer: {
                Text(AppStrings.Auth.resetPasswordSubtitle)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(message == AppStrings.Auth.resetPasswordSuccess ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView(AppStrings.Auth.resetPasswordSending)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(AppStrings.Auth.sendResetLink)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.reset.submit")
            }
        }
        .navigationTitle(AppStrings.Auth.resetPasswordTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auth.reset.screen")
    }

    private func submit() {
        let errors = validationService.validatePasswordReset(email: email)
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
}

struct TermsPrivacyConsentView: View {
    @Binding var acceptedTerms: Bool
    @Binding var acceptedPrivacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.Auth.consentTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Auth.consentSubtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                Label(AppStrings.Auth.reviewTerms, systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("auth.consent.termsLink")

            Text(AppStrings.authCurrentTermsVersion(AuthService.currentTermsVersion))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Toggle(AppStrings.Auth.acceptTerms, isOn: $acceptedTerms)
                .accessibilityLabel(AppStrings.Auth.acceptTerms)

            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                Label(AppStrings.Auth.reviewPrivacy, systemImage: "lock.doc")
                    .font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("auth.consent.privacyLink")

            Text(AppStrings.authCurrentPrivacyVersion(AuthService.currentPrivacyVersion))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Toggle(AppStrings.Auth.acceptPrivacy, isOn: $acceptedPrivacy)
                .accessibilityLabel(AppStrings.Auth.acceptPrivacy)
        }
        .padding(.vertical, 4)
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
