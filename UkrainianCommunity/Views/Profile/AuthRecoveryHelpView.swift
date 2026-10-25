import SwiftUI

struct AuthRecoveryHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PushedScreenShell(title: AccountSecurityCopy.recoveryTitle, showsBackButton: false, tabBarHidden: true) {
                AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AccountSecurityCopy.close) {
                    dismiss()
                }
                .accessibilityIdentifier("auth.mfa.recovery.close")
            } content: {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        Text(AccountSecurityCopy.recoveryBody)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = AccountRecoverySupport.composeURL {
                            Link(destination: url) {
                                Label(AccountSecurityCopy.contactSupport, systemImage: "envelope")
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.accentPrimaryForeground)
                            .accessibilityIdentifier("auth.mfa.recovery.email")
                        }
                        Text(verbatim: AccountRecoverySupport.email)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
