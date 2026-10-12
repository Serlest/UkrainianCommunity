import SwiftUI

struct LinkedAccountProvidersView: View {
    let account: AppUser?

    @State private var linkedProviderIDs: Set<String> = []
    @State private var isLoading = true
    @State private var hasLoadedProviders = false
    @State private var appleLinkConsent = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var showsLinkingOptions = false

    private var availableProviderIDs: Set<String> {
        Set(["apple.com", "google.com"]).subtracting(linkedProviderIDs)
    }

    private var isAppleConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "UACAppleSignInEnabled") as? Bool == true
    }

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.linkedMethodsTitle,
            subtitle: AppStrings.AccountSecurity.linkedMethodsSubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(AppStrings.Common.loading)
                } else if !hasLoadedProviders {
                    Button(AppStrings.Action.retry) {
                        Task { await loadProviders() }
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    if linkedProviderIDs.contains("password") {
                        connectedMethod(AppStrings.AccountSecurity.emailPasswordMethod)
                    }
                    if linkedProviderIDs.contains("apple.com") {
                        connectedMethod("Apple")
                    }
                    if linkedProviderIDs.contains("google.com") {
                        connectedMethod("Google")
                    }

                    if !availableProviderIDs.isEmpty {
                        DisclosureGroup(
                            AppStrings.AccountSecurity.addSignInMethod,
                            isExpanded: $showsLinkingOptions
                        ) {
                            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                                if AuthSecurityPolicy.isPrivilegedAccount(account) {
                                    Text(AppStrings.AccountSecurity.privilegedLinkHint)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                if availableProviderIDs.contains("apple.com") && isAppleConfigured {
                                    Text(AppStrings.AccountSecurity.appleLinkDisclosure)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.textSecondary)

                                    Toggle(AppStrings.AccountSecurity.appleLinkConsent, isOn: $appleLinkConsent)
                                        .font(.footnote)
                                        .accessibilityIdentifier("accountSecurity.provider.appleConsent")
                                }

                                FederatedCredentialButtons(
                                    showsHeading: false,
                                    allowedProviderIDs: availableProviderIDs,
                                    appleButtonEnabled: appleLinkConsent,
                                    isLinking: true
                                ) { credential in
                                    linkedProviderIDs = try await AccountProviderLinkService.shared.link(credential)
                                    message = AppStrings.AccountSecurity.linkSucceeded
                                    errorMessage = nil
                                    appleLinkConsent = false
                                    await AuthService.shared.refreshPrivilegedMultiFactorRequirement()
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(AppTheme.primaryBlue)
                    }
                }

                if let message {
                    InlineMessageCard(style: .success, message: message)
                }
                if let errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                }
            }
        }
        .task(id: account?.id) {
            await loadProviders()
        }
        .accessibilityIdentifier("accountSecurity.linkedMethods")
    }

    private func connectedMethod(_ name: String) -> some View {
        Label(
            "\(name) · \(AppStrings.AccountSecurity.methodConnected)",
            systemImage: "checkmark.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.textPrimary)
    }

    private func loadProviders() async {
        isLoading = true
        hasLoadedProviders = false
        errorMessage = nil
        do {
            linkedProviderIDs = try await AccountProviderLinkService.shared.linkedProviderIDs()
            hasLoadedProviders = true
        } catch {
            errorMessage = AppStrings.AccountSecurity.linkLoadFailed
        }
        isLoading = false
    }
}
