import Combine
import SwiftUI
import UIKit

private enum DonationField: Hashable { case url, title, message, button }
private enum DonationPresentation: Identifiable {
    case close(DonationEditorCommand), reload(DonationEditorScope)
    var id: String { switch self { case .close: "close"; case .reload: "reload" } }
}

struct DonationSettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: DonationConfigViewModel
    @State private var draft: DonationConfig = .defaults
    @State private var hasDraft = false
    @State private var isPreparing = true
    @State private var presentation: DonationPresentation?
    @State private var editLanguage: AppLanguage = .ukrainian
    @State private var previewLanguage: AppLanguage = .ukrainian
    @State private var previewExpanded = false
    @State private var linkFailed = false
    @State private var linkRequestID = UUID()
    @FocusState private var focusedField: DonationField?

    private var scope: DonationEditorScope { DonationEditorScope(authState) }
    private var language: AppLanguage { DonationLocalization.language(from: locale) }
    private var hasChanges: Bool { !draft.hasSameContent(as: viewModel.config) }
    private var hasRemoteConflict: Bool { draft.sourceRevision != viewModel.config.sourceRevision && hasChanges }
    private var canSave: Bool {
        scope.allowsOwner && hasChanges && draft.normalizedForSaving().validationIssue == nil
            && !viewModel.isSaving && !viewModel.isLoading && !hasRemoteConflict && !viewModel.needsReload
    }

    var body: some View {
        ScrollViewReader { proxy in
            PushedScreenShell(title: ProjectSupportText.title, tabBarHidden: true,
                              scrollsHeaderInCompactHeight: focusedField != nil, backAction: attemptDismiss) {
                AppGroupedContentPlane(spacing: AppTheme.feedRowSpacing) {
                    if !scope.allowsOwner {
                        ErrorStateCard(systemImage: "lock.fill", title: DonationLocalization.ownerOnlyTitle(for: language),
                                       message: DonationLocalization.ownerOnlyMessage(for: language))
                    } else if !hasDraft && (isPreparing || viewModel.isLoading) {
                        LoadingStateCard(title: nil).frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityIdentifier("donation.edit.loading")
                    } else if !hasDraft {
                        ErrorStateCard(systemImage: "heart.slash", title: ProjectSupportText.title,
                                       message: DonationLocalization.loadFailed(for: language), retryTitle: AppStrings.Action.retry) {
                            Task { await loadDraft() }
                        }
                    } else { content }
                }
            }
            .clipped()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasDraft && scope.allowsOwner {
                    PrimaryActionButton(title: ProjectSupportText.save, loadingTitle: ProjectSupportText.saving,
                                        isEnabled: canSave && presentation == nil, isLoading: viewModel.isSaving, systemImage: "checkmark") {
                        let command = DonationEditorCommand(config: draft.normalizedForSaving(), scope: scope)
                        focusedField = nil
                        Task { _ = await save(command) }
                    }
                    .accessibilityIdentifier("donation.edit.save")
                    .padding(.horizontal, AppTheme.pageHorizontal).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .onChange(of: focusedField) { _, _ in revealFocus(with: proxy) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in revealFocus(with: proxy) }
        }
        .task {
            let original = scope
            guard original.allowsOwner else { return }
            editLanguage = language; previewLanguage = language
            await loadDraft()
        }
        .appRefreshable { await loadDraft() }
        .onChange(of: viewModel.config) { old, new in
            if !viewModel.isSaving && draft.hasSameContent(as: old) { draft = new }
        }
        .onChange(of: scope) { _, _ in
            viewModel.invalidateEditor(); presentation = nil; focusedField = nil; dismiss()
        }
        .onChange(of: editLanguage) { _, _ in focusedField = nil }
        .onChange(of: draft.donationURL) { _, _ in linkFailed = false; linkRequestID = UUID() }
        .sheet(item: $presentation) { confirmation($0) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            if let status = viewModel.statusMessage { InlineMessageCard(style: viewModel.statusStyle, message: status) }
            if hasRemoteConflict || viewModel.needsReload {
                if viewModel.statusMessage == nil { InlineMessageCard(style: .error, message: DonationEditorText.conflict) }
                Button(DonationEditorText.reload) { focusedField = nil; presentation = .reload(scope) }
                    .accessibilityIdentifier("donation.edit.reload")
            }
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    Text(viewModel.config.isEnabled && viewModel.config.validDonationURL != nil ? ProjectSupportText.savedVisible : ProjectSupportText.savedHidden)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("donation.saved.visibility")
                    if hasChanges {
                        Text(ProjectSupportText.unsaved).font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("donation.unsaved")
                    }
                    Toggle(DonationLocalization.enableToggle(for: language), isOn: $draft.isEnabled)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("donation.edit.enabled")
                    AppEditorField(title: DonationLocalization.urlPlaceholder(for: language)) {
                        TextField(DonationLocalization.urlPlaceholder(for: language), text: $draft.donationURL)
                            .focused($focusedField, equals: .url).id(DonationField.url)
                            .accessibilityIdentifier("donation.edit.url")
                            .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                            .appEditorInputStyle(minHeight: 52)
                    }
                    if let urlError { InlineMessageCard(style: .error, message: urlError) }
                    if draft.validDonationURL != nil {
                        Button(ProjectSupportText.openLink) {
                            guard let url = draft.validDonationURL else { return }
                            let access = scope
                            let request = UUID(); linkRequestID = request
                            focusedField = nil
                            openURL(url) { accepted in if access == scope && request == linkRequestID { linkFailed = !accepted } }
                        }.accessibilityIdentifier("donation.edit.checkLink")
                    }
                    if linkFailed {
                        InlineMessageCard(style: .error, message: DonationEditorText.linkFailed)
                        Button(ProjectSupportText.copyLink) { UIPasteboard.general.string = draft.normalizedDonationURLString }
                    }
                }
            }
            languagePicker(DonationEditorText.editLanguage, selection: $editLanguage, id: "donation.edit.language")
            localizedTextSection
            if let error = validationError { InlineMessageCard(style: .error, message: error) }
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
            AppEditorSectionCard {
                Button { previewExpanded.toggle() } label: {
                    previewHeaderLayout {
                        Text(DonationLocalization.previewTitle(for: language)).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
                        Image(systemName: previewExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityIdentifier("donation.preview.toggle")
                    .accessibilityValue(ProjectSupportText.text(previewExpanded ? "previewExpanded" : "previewCollapsed"))
                if previewExpanded {
                    Text(draft.isEnabled && draft.normalizedForSaving().validationIssue == nil ? ProjectSupportText.willVisible : ProjectSupportText.willHidden)
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("donation.preview.visibility")
                    languagePicker(DonationEditorText.previewLanguage, selection: $previewLanguage, id: "donation.preview.language")
                    ProfileDonationSupportCard(config: draft.normalizedForSaving(), language: previewLanguage)
                        .allowsHitTesting(false).accessibilityElement(children: .ignore)
                        .accessibilityLabel(draft.title(for: previewLanguage) + ". " + draft.message(for: previewLanguage))
                }
            }
        }.disabled(viewModel.isSaving || presentation != nil || !scope.allowsOwner)
    }

    private var previewHeaderLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    private var localizedTextSection: some View {
        let isUK = editLanguage == .ukrainian
        let title = isUK ? $draft.titleUK : $draft.titleDE
        let message = isUK ? $draft.messageUK : $draft.messageDE
        let button = isUK ? $draft.buttonTitleUK : $draft.buttonTitleDE
        return AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: isUK ? DonationLocalization.ukrainianTextSection(for: language) : DonationLocalization.germanTextSection(for: language))
                AppEditorField(title: DonationLocalization.titlePlaceholder(for: language)) {
                    TextField(DonationLocalization.titlePlaceholder(for: language), text: title, axis: .vertical)
                        .lineLimit(1...3).focused($focusedField, equals: .title).id(DonationField.title)
                        .accessibilityIdentifier("donation.edit.title.\(editLanguage.rawValue)").appEditorInputStyle(minHeight: 52)
                    fieldFeedback(title.wrappedValue, limit: 120)
                }
                AppEditorField(title: DonationLocalization.messagePlaceholder(for: language)) {
                    TextEditor(text: message).focused($focusedField, equals: .message).id(DonationField.message)
                        .frame(height: messageEditorHeight).scrollContentBackground(.hidden)
                        .accessibilityIdentifier("donation.edit.message.\(editLanguage.rawValue)").appEditorInputStyle(minHeight: messageEditorHeight)
                    fieldFeedback(message.wrappedValue, limit: 2000)
                }
                AppEditorField(title: DonationLocalization.buttonTextPlaceholder(for: language)) {
                    TextField(DonationLocalization.buttonTextPlaceholder(for: language), text: button, axis: .vertical)
                        .lineLimit(1...3).focused($focusedField, equals: .button).id(DonationField.button)
                        .accessibilityIdentifier("donation.edit.button.\(editLanguage.rawValue)").appEditorInputStyle(minHeight: 52)
                    fieldFeedback(button.wrappedValue, limit: 80)
                }
            }
        }
    }

    private var messageEditorHeight: CGFloat {
        focusedField == .message && verticalSizeClass == .compact ? 100 : 180
    }

    private func revealFocus(with proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard let focusedField, scope.allowsOwner else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(focusedField, anchor: UnitPoint(x: 0.5, y: 0.2)) }
        }
    }
    private func languagePicker(_ label: String, selection: Binding<AppLanguage>, id: String) -> some View {
        Picker(label, selection: selection) {
            Text(AppStrings.Settings.ukrainian).tag(AppLanguage.ukrainian)
            Text(AppStrings.Settings.german).tag(AppLanguage.german)
        }.pickerStyle(.segmented).accessibilityIdentifier(id)
    }
    @ViewBuilder private func fieldFeedback(_ value: String, limit: Int) -> some View {
        Text("\(value.utf16.count)/\(limit)").font(.caption).foregroundStyle(AppTheme.textSecondary)
        if value.utf16.count > limit { Text(DonationEditorText.fieldTooLong).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground) }
        else if draft.isEnabled && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(DonationEditorText.fieldRequired).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground)
        }
    }
    private var urlError: String? {
        let config = draft.normalizedForSaving()
        if config.isEnabled && config.donationURL.isEmpty { return DonationLocalization.urlRequired(for: language) }
        if !config.donationURL.isEmpty && config.validDonationURL == nil { return DonationLocalization.invalidURL(for: language) }
        return nil
    }
    private var validationError: String? {
        switch draft.normalizedForSaving().validationIssue {
        case .urlRequired: DonationLocalization.urlRequired(for: language)
        case .invalidURL: DonationLocalization.invalidURL(for: language)
        case .tooLong: DonationEditorText.limits
        case .missingText: DonationEditorText.missingText
        case nil: nil
        }
    }
    private func loadDraft(discard: Bool = false) async {
        let access = scope, before = draft
        guard access.allowsOwner else { return }
        if !hasDraft { isPreparing = true }
        defer { isPreparing = false }
        await viewModel.load()
        guard scope == access, viewModel.hasLoadedData, !viewModel.needsReload,
              viewModel.statusMessage == nil else { return }
        if !hasDraft || discard || draft.hasSameContent(as: before) && !hasChanges { draft = viewModel.config; hasDraft = true }
        // First entry has no local draft yet; never replace actual edits during a refresh.
    }
    private func save(_ command: DonationEditorCommand) async -> Bool {
        guard command.scope == scope, scope.allowsOwner, command.config.validationIssue == nil,
              let userID = command.scope.identity.userID else { return false }
        let auth = authState
        let saved = await viewModel.save(command.config, updatedBy: userID,
                                         isCurrent: { command.scope == DonationEditorScope(auth) })
        guard saved, command.scope == scope else { return false }
        draft = viewModel.config
        return true
    }
    private func attemptDismiss() {
        guard !viewModel.isSaving else { return }
        focusedField = nil
        if hasChanges { presentation = .close(DonationEditorCommand(config: draft.normalizedForSaving(), scope: scope)) }
        else { dismiss() }
    }
    @ViewBuilder private func confirmation(_ route: DonationPresentation) -> some View {
        switch route {
        case .close(let command):
            NotificationConfirmationSheet(title: ProjectSupportText.closeTitle, message: ProjectSupportText.closeMessage,
                                          cancel: { presentation = nil }) {
                NotificationConfirmationAction(title: DonationEditorText.saveAndClose, id: "donation.confirm.save") {
                    presentation = nil
                    Task { if await save(command) { dismiss() } }
                }.disabled(command.scope != scope || command.config.validationIssue != nil || viewModel.needsReload || hasRemoteConflict)
                NotificationConfirmationAction(title: ProjectSupportText.leave, id: "donation.confirm.discard", role: .destructive) {
                    guard command.scope == scope else { presentation = nil; return }
                    presentation = nil; dismiss()
                }
            }
        case .reload(let access):
            NotificationConfirmationSheet(title: ProjectSupportText.reloadTitle, message: ProjectSupportText.reloadMessage,
                                          cancel: { presentation = nil }) {
                NotificationConfirmationAction(title: ProjectSupportText.reload, id: "donation.confirm.reload", role: .destructive) {
                    presentation = nil
                    Task { if access == scope { await loadDraft(discard: true) } }
                }
            }
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
            uk: "Ви перейдете на зовнішній сайт: \(host)",
            de: "Sie öffnen eine externe Website: \(host)",
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
