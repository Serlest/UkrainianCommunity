import SwiftUI

struct DonationSettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: DonationConfigViewModel
    @State private var draft: DonationConfig = .defaults
    @State private var validationMessage: String?

    var body: some View {
        ProfileDestinationLayout(
            title: DonationLocalization.settingsTitle(for: language),
            introSubtitle: DonationLocalization.settingsSubtitle(for: language)
        ) {
            if !PermissionService.isAppOwner(user: authState.user) {
                ErrorStateCard(
                    systemImage: "lock.fill",
                    title: DonationLocalization.ownerOnlyTitle(for: language),
                    message: DonationLocalization.ownerOnlyMessage(for: language)
                )
            } else if viewModel.isLoading {
                LoadingStateCard(title: nil)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if !viewModel.hasLoadedData {
                ErrorStateCard(
                    systemImage: "heart.slash",
                    title: DonationLocalization.settingsTitle(for: language),
                    message: DonationLocalization.loadFailed(for: language),
                    retryTitle: AppStrings.Action.retry
                ) {
                    Task {
                        await viewModel.load()
                        if viewModel.hasLoadedData {
                            draft = viewModel.config
                        }
                    }
                }
            } else {
                content
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            draft = viewModel.config
        }
        .refreshable {
            await viewModel.load()
            draft = viewModel.config
        }
        .onChange(of: viewModel.config) { _, newConfig in
            draft = newConfig
        }
    }

    private var language: AppLanguage {
        DonationLocalization.language(from: locale)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            if let validationMessage {
                InlineMessageCard(style: .error, message: validationMessage)
            }

            if let statusMessage = viewModel.statusMessage {
                InlineMessageCard(style: viewModel.statusStyle, message: statusMessage)
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    SectionHeaderBlock(
                        title: DonationLocalization.previewTitle(for: language),
                        subtitle: DonationLocalization.previewSubtitle(for: language)
                    )

                    ProfileDonationSupportCard(config: draft, language: language)
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    SectionHeaderBlock(
                        title: DonationLocalization.visibilityTitle(for: language),
                        subtitle: DonationLocalization.visibilitySubtitle(for: language)
                    )

                    Toggle(DonationLocalization.enableToggle(for: language), isOn: $draft.isEnabled)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    TextField(DonationLocalization.urlPlaceholder(for: language), text: $draft.donationURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .appEditorInputStyle(minHeight: 52)
                }
            }

            localizedTextSection(
                title: DonationLocalization.ukrainianTextSection(for: language),
                titleText: $draft.titleUK,
                messageText: $draft.messageUK,
                buttonText: $draft.buttonTitleUK
            )

            localizedTextSection(
                title: DonationLocalization.germanTextSection(for: language),
                titleText: $draft.titleDE,
                messageText: $draft.messageDE,
                buttonText: $draft.buttonTitleDE
            )

            PrimaryActionButton(
                title: DonationLocalization.saveButton(for: language),
                loadingTitle: DonationLocalization.savingButton(for: language),
                isEnabled: canSave,
                isLoading: viewModel.isSaving,
                systemImage: "checkmark"
            ) {
                Task { await save() }
            }
        }
    }

    private var canSave: Bool {
        draft.normalizedForSaving() != viewModel.config.normalizedForSaving()
            && validationError(for: draft.normalizedForSaving()) == nil
            && !viewModel.isSaving
    }

    private func localizedTextSection(
        title: String,
        titleText: Binding<String>,
        messageText: Binding<String>,
        buttonText: Binding<String>
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: title,
                    subtitle: DonationLocalization.localizedTextSubtitle(for: language)
                )

                TextField(DonationLocalization.titlePlaceholder(for: language), text: titleText)
                    .appEditorInputStyle(minHeight: 52)

                TextField(DonationLocalization.messagePlaceholder(for: language), text: messageText, axis: .vertical)
                    .lineLimit(3...6)
                    .appEditorInputStyle(minHeight: 112)

                TextField(DonationLocalization.buttonTextPlaceholder(for: language), text: buttonText)
                    .appEditorInputStyle(minHeight: 52)
            }
        }
    }

    private func save() async {
        let normalizedDraft = draft.normalizedForSaving()
        validationMessage = validationError(for: normalizedDraft)
        guard validationMessage == nil else { return }
        draft = normalizedDraft
        _ = await viewModel.save(normalizedDraft, updatedBy: authState.user?.id)
    }

    private func validationError(for config: DonationConfig) -> String? {
        let trimmedURL = config.donationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.isEnabled && trimmedURL.isEmpty {
            return DonationLocalization.urlRequired(for: language)
        }

        if !trimmedURL.isEmpty && config.validDonationURL == nil {
            return DonationLocalization.invalidURL(for: language)
        }

        return nil
    }
}

enum DonationLocalization {
    static func language(from locale: Locale = LocalizationStore.locale) -> AppLanguage {
        locale.identifier.lowercased().hasPrefix(AppLanguage.ukrainian.rawValue) ? .ukrainian : .german
    }

    static func publicSectionTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Підтримати проєкт", de: "Projekt unterstützen", language: language)
    }

    static func publicSectionSubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Добровільний внесок у розвиток і підтримку застосунку.",
            de: "Freiwilliger Beitrag zur Weiterentwicklung und zum Betrieb der App.",
            language: language
        )
    }

    static func platformEntrySubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Керування текстом і зовнішнім donation URL.",
            de: "Text und externe Spenden-URL verwalten.",
            language: language
        )
    }

    static func settingsTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Підтримка проєкту", de: "Projekt unterstützen", language: language)
    }

    static func settingsSubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Керуйте текстом картки підтримки та зовнішнім HTTPS-посиланням.",
            de: "Verwalten Sie den Text der Unterstützungskarte und den externen HTTPS-Link.",
            language: language
        )
    }

    static func ownerOnlyTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Доступ лише для власника", de: "Nur für den Owner", language: language)
    }

    static func ownerOnlyMessage(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Налаштування підтримки проєкту може змінювати тільки owner платформи.",
            de: "Die Einstellungen zur Projektunterstützung kann nur der Plattform-Owner ändern.",
            language: language
        )
    }

    static func visibilityTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Видимість і посилання", de: "Sichtbarkeit und Link", language: language)
    }

    static func visibilitySubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Кнопка показується тільки коли підтримка увімкнена і URL є валідним HTTPS-посиланням.",
            de: "Die Schaltfläche wird nur angezeigt, wenn Unterstützung aktiviert ist und die URL ein gültiger HTTPS-Link ist.",
            language: language
        )
    }

    static func enableToggle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Увімкнути кнопку підтримки", de: "Unterstützungsbutton aktivieren", language: language)
    }

    static func urlPlaceholder(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Donation URL", de: "Spenden-URL", language: language)
    }

    static func ukrainianTextSection(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Український текст", de: "Ukrainischer Text", language: language)
    }

    static func germanTextSection(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Німецький текст", de: "Deutscher Text", language: language)
    }

    static func localizedTextSubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Текст відображається в Profile відповідно до мови застосунку.",
            de: "Der Text wird im Profil entsprechend der App-Sprache angezeigt.",
            language: language
        )
    }

    static func previewTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Попередній перегляд", de: "Vorschau", language: language)
    }

    static func previewSubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Так картка виглядатиме в профілі користувача.",
            de: "So wird die Karte im Benutzerprofil angezeigt.",
            language: language
        )
    }

    static func externalSiteNotice(host: String, language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Внесок відкриється на захищеному зовнішньому сайті: \(host)",
            de: "Die Unterstützung wird auf einer sicheren externen Website geöffnet: \(host)",
            language: language
        )
    }

    static func titlePlaceholder(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Заголовок", de: "Titel", language: language)
    }

    static func messagePlaceholder(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Повідомлення", de: "Nachricht", language: language)
    }

    static func buttonTextPlaceholder(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Текст кнопки", de: "Buttontext", language: language)
    }

    static func saveButton(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Зберегти налаштування", de: "Einstellungen speichern", language: language)
    }

    static func savingButton(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Збереження", de: "Speichern", language: language)
    }

    static func urlRequired(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "URL обовʼязковий, коли підтримку увімкнено.",
            de: "Eine URL ist erforderlich, wenn Unterstützung aktiviert ist.",
            language: language
        )
    }

    static func invalidURL(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Введіть коректний домен або HTTPS-посилання.",
            de: "Geben Sie eine gültige Domain oder einen HTTPS-Link ein.",
            language: language
        )
    }

    static func loadFailed(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Не вдалося завантажити налаштування підтримки.",
            de: "Die Unterstützungseinstellungen konnten nicht geladen werden.",
            language: language
        )
    }

    static func saveSucceeded(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Налаштування підтримки збережено.",
            de: "Die Unterstützungseinstellungen wurden gespeichert.",
            language: language
        )
    }

    static func saveFailed(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Не вдалося зберегти налаштування підтримки.",
            de: "Die Unterstützungseinstellungen konnten nicht gespeichert werden.",
            language: language
        )
    }

    private static func localized(uk: String, de: String, language: AppLanguage) -> String {
        switch language {
        case .ukrainian:
            uk
        case .german:
            de
        }
    }
}
