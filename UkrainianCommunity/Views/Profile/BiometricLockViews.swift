import SwiftUI

struct RegistrationBiometricLockView: View {
    @ObservedObject var choice: RegistrationAppLockChoice
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                toggle.labelsHidden()
            } else {
                toggle
            }
            Text(AppStrings.AppLock.registrationHelp)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if choice.biometry == .unavailable {
                Text(AppStrings.AppLock.unavailable)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
            if let error = choice.errorMessage {
                Text(error).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
            if choice.isAuthenticating { ProgressView() }
        }
        .onAppear { choice.refreshAvailability() }
    }

    private var title: some View {
        Text(AppStrings.AppLock.registrationTitle)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toggle: some View {
        Toggle(isOn: Binding(
            get: { choice.isEnabled },
            set: { enabled in Task { await choice.setEnabled(enabled) } }
        )) { title }
        .disabled(choice.isAuthenticating || (choice.biometry == .unavailable && !choice.isEnabled))
        .accessibilityLabel(AppStrings.AppLock.registrationTitle)
        .accessibilityIdentifier("auth.register.appLock")
    }
}

struct BiometricLockSettingsSection: View {
    @ObservedObject var lock: AppLockService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ProfileSectionCard(title: AppStrings.AppLock.settingsTitle) {
            VStack(alignment: .leading, spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(AppStrings.AppLock.toggleTitle).font(.headline)
                    toggle.labelsHidden()
                } else {
                    toggle
                }
                Text(AppStrings.AppLock.settingsHelp)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if lock.biometry == .unavailable && !lock.isEnabled {
                    Text(AppStrings.AppLock.unavailable)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if lock.isEnabled {
                    Picker(AppStrings.AppLock.delayTitle, selection: Binding(
                        get: { lock.gracePeriod }, set: { lock.setGracePeriod($0) }
                    )) {
                        Text(AppStrings.AppLock.delayImmediately).tag(0.0)
                        Text(AppStrings.AppLock.delayMinute).tag(60.0)
                    }
                    .accessibilityIdentifier("profile.settings.appLock.delay")
                }
                if let message = lock.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(AppTheme.accentDestructiveForeground)
                }
                if lock.isAuthenticating { ProgressView() }
            }
        }
        .onAppear { lock.refreshAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { lock.refreshAvailability() }
        }
    }

    private var toggle: some View {
        Toggle(AppStrings.AppLock.toggleTitle, isOn: Binding(
            get: { lock.isEnabled },
            set: { enabled in Task { await lock.setEnabled(enabled) } }
        ))
        .disabled(lock.isAuthenticating || (lock.biometry == .unavailable && !lock.isEnabled))
        .accessibilityLabel(AppStrings.AppLock.toggleTitle)
        .accessibilityIdentifier("profile.settings.appLock")
    }
}

struct AppLockScreen: View {
    @ObservedObject var lock: AppLockService
    let showsControls: Bool
    let signOut: () async -> Bool
    @State private var isSigningOut = false
    @State private var signOutFailed = false
    @AppStorage("selectedAppLanguage") private var language = AppLanguage.stored.rawValue
    @AppStorage("selectedAppAppearance") private var appearance = AppAppearance.stored.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityHidden(true)
                Text(AppStrings.Home.brandTitle).font(.title2.bold())
                if showsControls {
                    Text(AppStrings.AppLock.lockedTitle).font(.title.bold())
                    Text(AppStrings.AppLock.lockedHelp)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let message = lock.errorMessage {
                        Text(message).foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                    if signOutFailed {
                        Text(AppStrings.AppLock.signOutFailed)
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Label(AppStrings.AppLock.unlock, systemImage: lock.biometry.symbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lock.isAuthenticating || isSigningOut)
                    .accessibilityIdentifier("appLock.unlock")

                    Button(AppStrings.AppLock.passwordSignIn) {
                        isSigningOut = true
                        signOutFailed = false
                        lock.cancelAuthentication()
                        Task {
                            signOutFailed = !(await signOut())
                            isSigningOut = false
                        }
                    }
                    .frame(minHeight: 44)
                    .disabled(isSigningOut || lock.isAuthenticating)
                    .accessibilityIdentifier("appLock.passwordSignIn")
                    Text(AppStrings.AppLock.passwordHelp)
                        .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    if lock.isAuthenticating || isSigningOut { ProgressView() }
                }
            }
            .multilineTextAlignment(.center)
            .padding(28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
        .background(AppBackgroundView())
        .tint(AppTheme.primaryBlue)
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
        .environment(\.locale, Locale(identifier: language))
        .accessibilityIdentifier("appLock.screen")
    }
}
