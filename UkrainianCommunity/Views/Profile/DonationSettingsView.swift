import SwiftUI

struct DonationSettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: DonationConfigViewModel
    @State private var draft: DonationConfig = .defaults
    @State private var showsDiscardConfirmation = false
    @State private var showsReloadConfirmation = false
    @State private var editLanguage: AppLanguage = .ukrainian
    @State private var previewLanguage: AppLanguage = .ukrainian
    @State private var linkFailed = false

    var body: some View {
        PushedScreenShell(
            title: DonationLocalization.settingsTitle(for: language),
            subtitle: DonationLocalization.settingsSubtitle(for: language),
            backAction: attemptDismiss
        ) {
            AppGroupedContentPlane(spacing: AppTheme.feedRowSpacing) {
                if !PermissionService.isAppOwner(user: authState.user) {
                    ErrorStateCard(
                        systemImage: "lock.fill",
                        title: DonationLocalization.ownerOnlyTitle(for: language),
                        message: DonationLocalization.ownerOnlyMessage(for: language)
                    )
                } else if viewModel.isLoading && !viewModel.hasLoadedData {
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
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasLoadedData && PermissionService.isAppOwner(user: authState.user) {
                VStack(spacing: 6) {
                    if let message = validationError(for: draft.normalizedForSaving()) {
                        Text(message).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PrimaryActionButton(title: DonationLocalization.saveButton(for: language),
                    loadingTitle: DonationLocalization.savingButton(for: language), isEnabled: canSave,
                    isLoading: viewModel.isSaving, systemImage: "checkmark") { Task { await save() } }
                    .accessibilityIdentifier("donation.edit.save")
                }
                    .padding(.horizontal, AppTheme.pageHorizontal).padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            let initialDraft = draft
            await viewModel.loadIfNeeded()
            if draft.hasSameContent(as: initialDraft) { draft = viewModel.config }
            editLanguage = language; previewLanguage = language
        }
        .appRefreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.config) { previousConfig, newConfig in
            if !viewModel.isSaving && draft.hasSameContent(as: previousConfig) { draft = newConfig }
        }
        .confirmationDialog(
            DonationLocalization.discardTitle(for: language),
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(DonationEditorText.saveAndClose) { Task { if await save() { dismiss() } } }.disabled(!canSave)
            Button(DonationLocalization.discardAction(for: language), role: .destructive) {
                dismiss()
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(DonationLocalization.discardMessage(for: language))
        }
        .confirmationDialog(DonationEditorText.reloadTitle, isPresented: $showsReloadConfirmation) {
            Button(DonationEditorText.reload, role: .destructive) { Task { await reloadDraft() } }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        }
        .onChange(of: authState.user?.id) { _, _ in dismiss() }

    }

    private var language: AppLanguage {
        DonationLocalization.language(from: locale)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            if let statusMessage = viewModel.statusMessage {
                InlineMessageCard(style: viewModel.statusStyle, message: statusMessage)
            }

            if hasRemoteConflict || viewModel.needsReload {
                InlineMessageCard(style: .error, message: DonationEditorText.conflict)
                Button(DonationEditorText.reload) { showsReloadConfirmation = true }
                    .accessibilityIdentifier("donation.edit.reload")
            }
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    SectionHeaderBlock(
                        title: DonationLocalization.previewTitle(for: language),
                        subtitle: DonationLocalization.previewSubtitle(for: language)
                    )

                    Label(draft.isEnabled && draft.normalizedForSaving().validationIssue == nil ? DonationEditorText.visible : DonationEditorText.hidden,
                        systemImage: draft.isEnabled && draft.normalizedForSaving().validationIssue == nil ? "eye" : "eye.slash")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                    languagePicker(DonationEditorText.previewLanguage, selection: $previewLanguage)
                    ProfileDonationSupportCard(config: previewConfig, language: previewLanguage)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(previewConfig.title(for: previewLanguage) + ". " + previewConfig.message(for: previewLanguage))
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
                        .accessibilityIdentifier("donation.edit.enabled")

                    AppEditorField(title: DonationLocalization.urlPlaceholder(for: language)) {
                        TextField(DonationLocalization.urlPlaceholder(for: language), text: $draft.donationURL)
                            .accessibilityIdentifier("donation.edit.url")
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .appEditorInputStyle(minHeight: 52)
                    }
                    if let urlError { InlineMessageCard(style: .error, message: urlError) }
                    if draft.validDonationURL != nil {
                        Button(DonationEditorText.checkLink) {
                            guard let url = draft.validDonationURL else { return }
                            openURL(url) { accepted in linkFailed = !accepted }
                        }.accessibilityIdentifier("donation.edit.checkLink")
                    }
                    if linkFailed { InlineMessageCard(style: .error, message: DonationEditorText.linkFailed) }
                }
            }

            languagePicker(DonationEditorText.editLanguage, selection: $editLanguage)
            localizedTextSection(
                title: editLanguage == .ukrainian ? DonationLocalization.ukrainianTextSection(for: language) : DonationLocalization.germanTextSection(for: language),
                titleText: editLanguage == .ukrainian ? $draft.titleUK : $draft.titleDE,
                messageText: editLanguage == .ukrainian ? $draft.messageUK : $draft.messageDE,
                buttonText: editLanguage == .ukrainian ? $draft.buttonTitleUK : $draft.buttonTitleDE,
                identifier: editLanguage.rawValue
            )
            AppEditorSectionCard {
                ContentTranslationButton(kind: "donation", fields: [
                    .init("title", DonationLocalization.titlePlaceholder(for: language), source: editLanguage == .ukrainian ? draft.titleUK : draft.titleDE,
                          target: editLanguage == .ukrainian ? $draft.titleDE : $draft.titleUK, limit: 120),
                    .init("message", DonationLocalization.messagePlaceholder(for: language), source: editLanguage == .ukrainian ? draft.messageUK : draft.messageDE,
                          target: editLanguage == .ukrainian ? $draft.messageDE : $draft.messageUK, limit: 2000),
                    .init("button", DonationLocalization.buttonTextPlaceholder(for: language), source: editLanguage == .ukrainian ? draft.buttonTitleUK : draft.buttonTitleDE,
                          target: editLanguage == .ukrainian ? $draft.buttonTitleDE : $draft.buttonTitleUK, limit: 80)
                ], sourceLanguage: editLanguage)
            }

        }.disabled(viewModel.isSaving).padding(.bottom, 16)
    }

    private var canSave: Bool {
        !draft.hasSameContent(as: viewModel.config)
            && validationError(for: draft.normalizedForSaving()) == nil
            && !viewModel.isSaving && !viewModel.isLoading && !hasRemoteConflict && !viewModel.needsReload
    }

    private func localizedTextSection(
        title: String,
        titleText: Binding<String>,
        messageText: Binding<String>,
        buttonText: Binding<String>,
        identifier: String
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: title,
                    subtitle: DonationLocalization.localizedTextSubtitle(for: language)
                )

                AppEditorField(title: DonationLocalization.titlePlaceholder(for: language)) {
                    TextField(DonationLocalization.titlePlaceholder(for: language), text: titleText)
                        .accessibilityIdentifier("donation.edit.title.\(identifier)")
                        .appEditorInputStyle(minHeight: 52)
                    fieldFeedback(titleText.wrappedValue, limit: 120)
                }

                AppEditorField(title: DonationLocalization.messagePlaceholder(for: language)) {
                    TextField(DonationLocalization.messagePlaceholder(for: language), text: messageText, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("donation.edit.message.\(identifier)")
                        .appEditorInputStyle(minHeight: 112)
                    fieldFeedback(messageText.wrappedValue, limit: 2000)
                }

                AppEditorField(title: DonationLocalization.buttonTextPlaceholder(for: language)) {
                    TextField(DonationLocalization.buttonTextPlaceholder(for: language), text: buttonText)
                        .accessibilityIdentifier("donation.edit.button.\(identifier)")
                        .appEditorInputStyle(minHeight: 52)
                    fieldFeedback(buttonText.wrappedValue, limit: 80)
                }
            }
        }
    }

    private func save() async -> Bool {
        let normalizedDraft = draft.normalizedForSaving()
        guard canSave, PermissionService.isAppOwner(user: authState.user), validationError(for: normalizedDraft) == nil else { return false }
        let userID = authState.user?.id
        draft = normalizedDraft
        if await viewModel.save(normalizedDraft, updatedBy: authState.user?.id) {
            guard authState.user?.id == userID else { return false }
            draft = viewModel.config
            return true
        }
        return false
    }

    private func attemptDismiss() {
        guard !viewModel.isSaving else { return }
        if draft.hasSameContent(as: viewModel.config) {
            dismiss()
        } else {
            showsDiscardConfirmation = true
        }
    }

    private var hasRemoteConflict: Bool { draft.sourceRevision != viewModel.config.sourceRevision && !draft.hasSameContent(as: viewModel.config) }
    private var previewConfig: DonationConfig {
        var config = draft
        config.isEnabled = config.validDonationURL != nil
        return config
    }
    private var urlError: String? {
        let config = draft.normalizedForSaving()
        if config.isEnabled && config.donationURL.isEmpty { return DonationLocalization.urlRequired(for: language) }
        if !config.donationURL.isEmpty && config.validDonationURL == nil { return DonationLocalization.invalidURL(for: language) }
        return nil
    }
    private func languagePicker(_ label: String, selection: Binding<AppLanguage>) -> some View {
        Picker(label, selection: selection) {
            Text(AppStrings.Settings.ukrainian).tag(AppLanguage.ukrainian)
            Text(AppStrings.Settings.german).tag(AppLanguage.german)
        }.pickerStyle(.segmented)
        .accessibilityIdentifier(label == DonationEditorText.editLanguage ? "donation.edit.language" : "donation.preview.language")
    }
    @ViewBuilder private func fieldFeedback(_ value: String, limit: Int) -> some View {
        Text("\(value.utf16.count)/\(limit)").font(.caption).foregroundStyle(AppTheme.textSecondary)
        if value.utf16.count > limit { Text(DonationEditorText.fieldTooLong).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground) }
        else if draft.isEnabled && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(DonationEditorText.fieldRequired).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground)
        }
    }
    private func reloadDraft() async {
        await viewModel.load()
        if !viewModel.needsReload && viewModel.statusMessage == nil { draft = viewModel.config }
    }
    private func validationError(for config: DonationConfig) -> String? {
        switch config.validationIssue {
        case .urlRequired: DonationLocalization.urlRequired(for: language)
        case .invalidURL: DonationLocalization.invalidURL(for: language)
        case .tooLong: DonationEditorText.limits
        case .missingText: DonationEditorText.missingText
        case nil: nil
        }
    }
}

enum DonationLocalization {
    static func language(from locale: Locale = LocalizationStore.locale) -> AppLanguage {
        AppLanguage.resolved(from: locale)
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
            uk: "Тексти та посилання для підтримки проєкту.",
            de: "Texte und Link zur Unterstützung des Projekts.",
            language: language
        )
    }

    static func settingsTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Налаштування підтримки проєкту", de: "Einstellungen zur Projektunterstützung", language: language)
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
            uk: "Налаштування підтримки проєкту може змінювати тільки власник застосунку.",
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
        localized(uk: "Посилання для підтримки", de: "Spenden-URL", language: language)
    }

    static func ukrainianTextSection(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Український текст", de: "Ukrainischer Text", language: language)
    }

    static func germanTextSection(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(uk: "Німецький текст", de: "Deutscher Text", language: language)
    }

    static func localizedTextSubtitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Текст відображається в профілі відповідно до мови застосунку.",
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

    static func saveSucceededRefreshFailed(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Зміни збережено, але оновити дані не вдалося. Спробуйте ще раз пізніше.",
            de: "Die Änderungen wurden gespeichert, aber die Daten konnten nicht aktualisiert werden. Versuchen Sie es später erneut.",
            language: language
        )
    }

    static func discardTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Відхилити незбережені зміни?",
            de: "Ungespeicherte Änderungen verwerfen?",
            language: language
        )
    }

    static func discardMessage(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Зміни налаштувань підтримки буде втрачено.",
            de: "Die Änderungen an den Unterstützungseinstellungen gehen verloren.",
            language: language
        )
    }

    static func discardAction(for language: AppLanguage = LocalizationStore.language) -> String {
        localized(
            uk: "Відхилити зміни",
            de: "Änderungen verwerfen",
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
