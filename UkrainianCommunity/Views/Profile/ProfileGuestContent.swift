import SwiftUI

struct ProfileGuestContent: View {
    let signIn: () -> Void
    let createAccount: () -> Void

    var body: some View {
        CommunityCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "person.crop.circle")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityHidden(true)
                Text(LocalizationStore.localizedString("personal.guest.title", defaultValue: "Ihr persönlicher Bereich", table: "PersonalSections"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizationStore.localizedString("personal.guest.message", defaultValue: "Melden Sie sich an oder erstellen Sie ein Konto, um Inhalte zu speichern, Organisationen zu folgen und Ihre Anmeldungen und Ihren Verlauf zu sehen.", table: "PersonalSections"))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryActionButton(title: AppStrings.Auth.signIn, action: signIn)
                .accessibilityIdentifier("profile.guest.signIn")
                Button(action: createAccount) {
                    Text(AppStrings.Auth.createAccount)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentPrimaryForeground)
                .accessibilityIdentifier("profile.guest.register")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
