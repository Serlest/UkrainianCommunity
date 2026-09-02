import Combine
import CoreImage.CIFilterBuiltins
import FirebaseAuth
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MultiFactorSignInView: View {
    @ObservedObject var coordinator: AuthMultiFactorSignInCoordinator
    @State private var code = ""

    private var selectedFactorID: String? {
        coordinator.selectedFactorID ?? coordinator.factors.first?.id
    }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: AppStrings.Auth.multiFactorTitle,
                subtitle: AppStrings.Auth.multiFactorSubtitle
            )

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    if coordinator.factors.count > 1 {
                        Picker(
                            AppStrings.AccountSecurity.multiFactorSection,
                            selection: $coordinator.selectedFactorID
                        ) {
                            ForEach(coordinator.factors) { factor in
                                Text(factor.displayName ?? AppStrings.AccountSecurity.multiFactorSection)
                                    .tag(Optional(factor.id))
                            }
                        }
                    }

                    EditorTextField(
                        AppStrings.Auth.multiFactorCode,
                        text: $code,
                        systemImage: "number",
                        keyboardType: .numberPad,
                        textContentType: .oneTimeCode,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )
                    .onChange(of: code) { _, newValue in
                        let normalized = String(
                            AuthMultiFactorService.normalizedCode(newValue).prefix(6)
                        )
                        if normalized != newValue { code = normalized }
                    }
                    .accessibilityIdentifier("auth.mfa.code")

                    if let errorMessage = coordinator.errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
                    }

                    PrimaryActionButton(
                        title: AppStrings.Auth.multiFactorVerify,
                        loadingTitle: AppStrings.Auth.multiFactorVerifying,
                        isEnabled: canSubmit,
                        isLoading: coordinator.isResolving,
                        systemImage: "checkmark.shield"
                    ) {
                        submit()
                    }
                    .accessibilityIdentifier("auth.mfa.submit")

                    Button(AppStrings.Common.cancel) {
                        Task { await AuthService.shared.cancelMultiFactorSignIn() }
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .disabled(coordinator.isResolving)
                    .accessibilityIdentifier("auth.mfa.cancel")
                }
            }
        }
        .navigationTitle(AppStrings.Auth.multiFactorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .accessibilityIdentifier("auth.mfa.screen")
    }

    private var canSubmit: Bool {
        selectedFactorID != nil
            && AuthMultiFactorService.isValidCode(code)
            && !coordinator.isResolving
    }

    private func submit() {
        guard let selectedFactorID else { return }
        Task {
            do {
                _ = try await AuthService.shared.resolveMultiFactorSignIn(
                    oneTimeCode: code,
                    factorID: selectedFactorID
                )
            } catch AuthMultiFactorFlowError.challengeUnavailable {
                coordinator.fail(message: AppStrings.Auth.multiFactorChallengeExpired)
            } catch {
                // The coordinator publishes a precise recoverable error.
            }
        }
    }
}

@MainActor
final class AccountSecurityViewModel: ObservableObject {
    @Published private(set) var factors: [AuthMultiFactorFactor] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isStartingEnrollment = false
    @Published private(set) var isConfirmingEnrollment = false
    @Published private(set) var removingFactorID: String?
    @Published private(set) var enrollmentSession: AuthTOTPEnrollmentSession?
    @Published private(set) var isSessionTOTPAuthenticated = false
    @Published private(set) var isActivatingRequirement = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let multiFactorService: AuthMultiFactorService

    init(multiFactorService: AuthMultiFactorService) {
        self.multiFactorService = multiFactorService
    }

    convenience init() {
        self.init(multiFactorService: .shared)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            factors = try await multiFactorService.enrolledTOTPFactors()
        } catch {
            errorMessage = AppStrings.AccountSecurity.loadFailed
        }
    }

    func refreshSessionAuthentication() async {
        do {
            isSessionTOTPAuthenticated = try await multiFactorService
                .isCurrentSessionTOTPAuthenticated()
        } catch {
            isSessionTOTPAuthenticated = false
        }
    }

    func sendPasswordChangeLink(email: String) async {
        message = nil
        errorMessage = nil

        do {
            try await AuthService.shared.sendPasswordReset(email: email)
            message = AppStrings.AccountSecurity.passwordLinkSent
        } catch {
            errorMessage = AppStrings.AccountSecurity.passwordLinkFailed
        }
    }

    func beginEnrollment() async {
        isStartingEnrollment = true
        message = nil
        errorMessage = nil
        defer { isStartingEnrollment = false }

        do {
            enrollmentSession = try await multiFactorService.beginTOTPEnrollment()
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func completeEnrollment(code: String) async {
        guard let enrollmentSession else { return }
        isConfirmingEnrollment = true
        errorMessage = nil
        defer { isConfirmingEnrollment = false }

        do {
            try await multiFactorService.completeTOTPEnrollment(
                session: enrollmentSession,
                oneTimeCode: code
            )
            self.enrollmentSession = nil
            message = AppStrings.AccountSecurity.enrollmentSucceeded
            factors = try await multiFactorService.enrolledTOTPFactors()
            isSessionTOTPAuthenticated = false
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func cancelEnrollment() {
        enrollmentSession = nil
    }

    func removeFactor(_ factor: AuthMultiFactorFactor, for user: AppUser?) async {
        removingFactorID = factor.id
        message = nil
        errorMessage = nil
        defer { removingFactorID = nil }

        do {
            try await multiFactorService.removeTOTPFactor(
                id: factor.id,
                canRemoveLastFactor: AuthSecurityPolicy.canRemoveLastTOTPFactor(for: user)
            )
            factors.removeAll { $0.id == factor.id }
            message = AppStrings.AccountSecurity.removalSucceeded
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func activatePrivilegedRequirement() async -> Bool {
        isActivatingRequirement = true
        message = nil
        errorMessage = nil
        defer { isActivatingRequirement = false }

        do {
            let response = try await CloudFunctionsClient.shared
                .activatePrivilegedMFAProtection()
            guard response.required else {
                errorMessage = AppStrings.AccountSecurity.operationFailed
                return false
            }
            message = AppStrings.AccountSecurity.privilegedActivationSucceeded
            return true
        } catch {
            errorMessage = AppStrings.AccountSecurity.privilegedActivationFailed
            return false
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let flowError = error as? AuthMultiFactorFlowError {
            return switch flowError {
            case .invalidCode:
                AppStrings.Auth.multiFactorInvalidCode
            case .alreadyEnrolled:
                AppStrings.AccountSecurity.alreadyEnrolled
            case .noCurrentUser, .sessionChanged:
                AppStrings.AccountSecurity.requiresRecentLogin
            case .emailNotVerified:
                AppStrings.Auth.emailVerificationStillPending
            case .secondFactorRequired, .challengeUnavailable, .unsupportedFactor:
                AppStrings.AccountSecurity.operationFailed
            case .enrollmentNotReleased:
                AppStrings.AccountSecurity.multiFactorRolloutPending
            case .requiredFactorCannotBeRemoved:
                AppStrings.AccountSecurity.requiredFactorCannotBeRemoved
            }
        }

        let nsError = error as NSError
        if AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
            return AppStrings.AccountSecurity.requiresRecentLogin
        }
        if AuthErrorCode(rawValue: nsError.code) == .invalidVerificationCode {
            return AppStrings.Auth.multiFactorInvalidCode
        }
        return AppStrings.AccountSecurity.operationFailed
    }
}

struct AccountSecurityView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = AccountSecurityViewModel()
    @State private var isSendingPasswordLink = false
    @State private var factorPendingRemoval: AuthMultiFactorFactor?

    var body: some View {
        PushedScreenShell(
            title: AppStrings.AccountSecurity.title,
            subtitle: AppStrings.AccountSecurity.subtitle
        ) {
            if let message = viewModel.message {
                InlineMessageCard(style: .success, message: message)
            }
            if let errorMessage = viewModel.errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

            passwordSection
            multiFactorSection
        }
        .task(id: authState.user?.id) {
            await viewModel.load()
        }
        .sheet(item: Binding(
            get: { viewModel.enrollmentSession },
            set: { if $0 == nil { viewModel.cancelEnrollment() } }
        )) { session in
            TOTPEnrollmentView(viewModel: viewModel, session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $factorPendingRemoval) { factor in
            Alert(
                title: Text(AppStrings.AccountSecurity.removeTitle),
                message: Text(AppStrings.AccountSecurity.removeMessage),
                primaryButton: .destructive(Text(AppStrings.AccountSecurity.removeMultiFactor)) {
                    Task { await viewModel.removeFactor(factor, for: authState.user) }
                },
                secondaryButton: .cancel(Text(AppStrings.Common.cancel))
            )
        }
        .accessibilityIdentifier("screen.accountSecurity")
    }

    private var passwordSection: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.passwordSection,
            subtitle: AppStrings.AccountSecurity.passwordSubtitle
        ) {
            PrimaryActionButton(
                title: AppStrings.AccountSecurity.sendPasswordLink,
                loadingTitle: AppStrings.AccountSecurity.sendingPasswordLink,
                isEnabled: authState.user?.email.isEmpty == false,
                isLoading: isSendingPasswordLink,
                systemImage: "envelope.badge.shield.half.filled"
            ) {
                guard let email = authState.user?.email else { return }
                isSendingPasswordLink = true
                Task {
                    await viewModel.sendPasswordChangeLink(email: email)
                    isSendingPasswordLink = false
                }
            }
            .accessibilityIdentifier("accountSecurity.password.sendLink")
        }
    }

    private var multiFactorSection: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.multiFactorSection,
            subtitle: AppStrings.AccountSecurity.multiFactorSubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(AppStrings.Common.loading)
                } else if viewModel.factors.isEmpty {
                    InlineMessageCard(
                        style: .info,
                        message: AuthSecurityRollout.allowsTOTPEnrollment
                            ? AppStrings.AccountSecurity.multiFactorDisabled
                            : AppStrings.AccountSecurity.multiFactorRolloutPending
                    )

                    PrimaryActionButton(
                        title: AppStrings.AccountSecurity.enableMultiFactor,
                        loadingTitle: AppStrings.AccountSecurity.enablingMultiFactor,
                        isEnabled: AuthSecurityRollout.allowsTOTPEnrollment,
                        isLoading: viewModel.isStartingEnrollment,
                        systemImage: "qrcode"
                    ) {
                        Task { await viewModel.beginEnrollment() }
                    }
                    .accessibilityIdentifier("accountSecurity.mfa.enable")
                } else {
                    InlineMessageCard(
                        style: .success,
                        message: AppStrings.AccountSecurity.multiFactorEnabled
                    )

                    ForEach(viewModel.factors) { factor in
                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            Label(
                                factor.displayName ?? AppStrings.AccountSecurity.multiFactorSection,
                                systemImage: "checkmark.shield.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                            Text(factor.enrollmentDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)

                            if AuthSecurityPolicy.canRemoveLastTOTPFactor(for: authState.user)
                                || viewModel.factors.count > 1 {
                                Button(role: .destructive) {
                                    factorPendingRemoval = factor
                                } label: {
                                    Label(
                                        viewModel.removingFactorID == factor.id
                                            ? AppStrings.AccountSecurity.removingMultiFactor
                                            : AppStrings.AccountSecurity.removeMultiFactor,
                                        systemImage: "trash"
                                    )
                                }
                                .disabled(viewModel.removingFactorID != nil)
                            } else {
                                Label(
                                    AppStrings.AccountSecurity.requiredFactorCannotBeRemoved,
                                    systemImage: "lock.shield"
                                )
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .padding(AppTheme.cardPadding)
                        .background(
                            AppTheme.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        )
                    }
                }

                Text(AppStrings.AccountSecurity.recoveryNotice)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PrivilegedMultiFactorRequirementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = AccountSecurityViewModel()
    @State private var isRestartingSignIn = false

    private var currentUser: AppUser? { authState.user }

    var body: some View {
        AuthScreenScaffold {
            AuthHeaderView(
                title: AppStrings.AccountSecurity.privilegedRequiredTitle,
                subtitle: AppStrings.AccountSecurity.privilegedRequiredSubtitle
            )

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(AppStrings.Common.loading)
                    } else {
                        requirementContent
                    }

                    if let message = viewModel.message {
                        InlineMessageCard(style: .success, message: message)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
                    }

                    Text(AppStrings.AccountSecurity.recoveryNotice)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(AppStrings.AccountSecurity.privilegedRequiredTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
        .task(id: currentUser?.id) {
            await viewModel.load()
            await viewModel.refreshSessionAuthentication()
            await dismissIfRequirementIsSatisfied()
        }
        .sheet(item: Binding(
            get: { viewModel.enrollmentSession },
            set: { if $0 == nil { viewModel.cancelEnrollment() } }
        )) { session in
            TOTPEnrollmentView(viewModel: viewModel, session: session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("auth.mfa.privilegedRequirement")
    }

    @ViewBuilder
    private var requirementContent: some View {
        if viewModel.factors.isEmpty {
            InlineMessageCard(
                style: .info,
                message: AuthSecurityRollout.allowsTOTPEnrollment
                    ? AppStrings.AccountSecurity.privilegedEnrollmentRequired
                    : AppStrings.AccountSecurity.multiFactorRolloutPending
            )

            PrimaryActionButton(
                title: AppStrings.AccountSecurity.enableMultiFactor,
                loadingTitle: AppStrings.AccountSecurity.enablingMultiFactor,
                isEnabled: AuthSecurityRollout.allowsTOTPEnrollment,
                isLoading: viewModel.isStartingEnrollment,
                systemImage: "qrcode"
            ) {
                Task { await viewModel.beginEnrollment() }
            }
            .accessibilityIdentifier("auth.mfa.privilegedRequirement.enroll")
        } else if !viewModel.isSessionTOTPAuthenticated {
            InlineMessageCard(
                style: .info,
                message: AppStrings.AccountSecurity.privilegedSignInAgain
            )

            PrimaryActionButton(
                title: AppStrings.AccountSecurity.privilegedRestartSignIn,
                loadingTitle: AppStrings.AccountSecurity.privilegedRestartingSignIn,
                isEnabled: !isRestartingSignIn,
                isLoading: isRestartingSignIn,
                systemImage: "rectangle.portrait.and.arrow.right"
            ) {
                restartSignIn()
            }
            .accessibilityIdentifier("auth.mfa.privilegedRequirement.restart")
        } else if currentUser?.requiresMultiFactorAuth != true {
            InlineMessageCard(
                style: .info,
                message: AppStrings.AccountSecurity.privilegedActivateMessage
            )

            PrimaryActionButton(
                title: AppStrings.AccountSecurity.privilegedActivate,
                loadingTitle: AppStrings.AccountSecurity.privilegedActivating,
                isEnabled: !viewModel.isActivatingRequirement,
                isLoading: viewModel.isActivatingRequirement,
                systemImage: "checkmark.shield"
            ) {
                activateRequirement()
            }
            .accessibilityIdentifier("auth.mfa.privilegedRequirement.activate")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(AppStrings.Common.loading)
        }
    }

    private func restartSignIn() {
        isRestartingSignIn = true
        Task {
            let didSignOut = await AuthService.shared.signOut()
            isRestartingSignIn = false
            guard didSignOut else { return }
            await Task.yield()
            authState.presentAuthFlow(.login)
        }
    }

    private func activateRequirement() {
        Task {
            guard await viewModel.activatePrivilegedRequirement(),
                  let userID = currentUser?.id else { return }
            await authState.loadUser(uid: userID)
            await AuthService.shared.refreshPrivilegedMultiFactorRequirement()
        }
    }

    private func dismissIfRequirementIsSatisfied() async {
        guard AuthSecurityPolicy.protectedSessionIsReady(
            user: currentUser,
            isTOTPAuthenticated: viewModel.isSessionTOTPAuthenticated
        ) else { return }
        await AuthService.shared.refreshPrivilegedMultiFactorRequirement()
    }
}

private struct TOTPEnrollmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: AccountSecurityViewModel
    let session: AuthTOTPEnrollmentSession
    @State private var code = ""
    @State private var copiedSecret = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        SectionHeaderBlock(
                            title: AppStrings.AccountSecurity.enrollmentTitle,
                            subtitle: AppStrings.AccountSecurity.enrollmentSubtitle
                        )

                        AppEditorSectionCard {
                            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                                TOTPQRCodeView(payload: session.qrCodeURL)
                                    .frame(maxWidth: .infinity)
                                    .privacySensitive()

                                Button(AppStrings.AccountSecurity.openAuthenticator) {
                                    session.openInAuthenticator()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accentPrimary)
                                .frame(maxWidth: .infinity)

                                Text(AppStrings.AccountSecurity.manualSecret)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)

                                Text(session.sharedSecret)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .textSelection(.enabled)
                                    .privacySensitive()
                                    .accessibilityLabel(AppStrings.AccountSecurity.manualSecret)

                                Button(copiedSecret
                                    ? AppStrings.AccountSecurity.secretCopied
                                    : AppStrings.AccountSecurity.copySecret) {
                                    UIPasteboard.general.setItems(
                                        [[UTType.utf8PlainText.identifier: session.sharedSecret]],
                                        options: [
                                            .localOnly: true,
                                            .expirationDate: Date().addingTimeInterval(300)
                                        ]
                                    )
                                    copiedSecret = true
                                }
                                .font(.footnote.weight(.semibold))

                                EditorTextField(
                                    AppStrings.Auth.multiFactorCode,
                                    text: $code,
                                    systemImage: "number",
                                    keyboardType: .numberPad,
                                    textContentType: .oneTimeCode,
                                    autocapitalization: .never,
                                    autocorrectionDisabled: true
                                )
                                .onChange(of: code) { _, newValue in
                                    let normalized = String(
                                        AuthMultiFactorService.normalizedCode(newValue).prefix(6)
                                    )
                                    if normalized != newValue { code = normalized }
                                }

                                if let errorMessage = viewModel.errorMessage {
                                    InlineMessageCard(style: .error, message: errorMessage)
                                }

                                PrimaryActionButton(
                                    title: AppStrings.AccountSecurity.confirmEnrollment,
                                    loadingTitle: AppStrings.AccountSecurity.confirmingEnrollment,
                                    isEnabled: AuthMultiFactorService.isValidCode(code),
                                    isLoading: viewModel.isConfirmingEnrollment,
                                    systemImage: "checkmark.shield"
                                ) {
                                    Task {
                                        await viewModel.completeEnrollment(code: code)
                                        if viewModel.enrollmentSession == nil { dismiss() }
                                    }
                                }
                                .accessibilityIdentifier("accountSecurity.mfa.confirm")
                            }
                        }
                    }
                    .padding(AppTheme.pageHorizontal)
                    .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(AppStrings.AccountSecurity.enrollmentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppStrings.Common.cancel) {
                        viewModel.cancelEnrollment()
                        dismiss()
                    }
                    .disabled(viewModel.isConfirmingEnrollment)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isConfirmingEnrollment)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                copiedSecret = false
            }
        }
        .onDisappear {
            if viewModel.enrollmentSession?.id == session.id {
                viewModel.cancelEnrollment()
            }
        }
    }
}

private struct TOTPQRCodeView: View {
    let payload: String

    var body: some View {
        Group {
            if let image = Self.makeQRCode(payload: payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(AppStrings.AccountSecurity.enrollmentTitle)
            } else {
                InlineMessageCard(
                    style: .error,
                    message: AppStrings.AccountSecurity.operationFailed
                )
            }
        }
        .frame(maxWidth: 240, maxHeight: 240)
        .padding(AppTheme.cardPadding)
        .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private static func makeQRCode(payload: String) -> UIImage? {
        guard !payload.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        ) else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
