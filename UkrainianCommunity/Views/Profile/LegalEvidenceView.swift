import SwiftUI

struct LegalEvidenceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: LegalEvidenceViewModel
    @FocusState private var isSearchFocused: Bool
    private let repository: LegalEvidenceRepository
    private let legalRepository: LegalDocumentRepository

    init(repository: LegalEvidenceRepository = LegalEvidenceRepositories.makeDefault(), legalRepository: LegalDocumentRepository = FirestoreLegalDocumentRepository()) {
        self.repository = repository
        self.legalRepository = legalRepository
        _viewModel = StateObject(wrappedValue: LegalEvidenceViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.LegalEvidence.title,
            introSubtitle: AppStrings.LegalEvidence.accountsSubtitle,
            contentSpacing: AppTheme.feedRowSpacing
        ) {
            if !PermissionService.isAppOwner(user: authState.user) {
                ErrorStateCard(
                    systemImage: "lock.fill",
                    title: AppStrings.LegalEvidence.permissionTitle,
                    message: AppStrings.LegalEvidence.permissionMessage
                )
            } else {
                noticeCard
                accountSearchField
                content
            }
        }
        .task(id: viewModel.searchText) {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            if !viewModel.normalizedSearch.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            await viewModel.load()
        }
        .appRefreshable {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            await viewModel.load()
        }
        .accessibilityIdentifier("screen.legalEvidence")
    }

    private var accountSearchField: some View {
        AppGlassCard(padding: 12, spacing: 8, shadowRadius: 8, shadowY: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)

                TextField(AppStrings.LegalEvidence.accountSearchPlaceholder, text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityIdentifier("legalEvidence.accountSearch")

                if !viewModel.searchText.isEmpty {
                    AppSearchClearButton {
                        viewModel.searchText = ""
                    }
                }
            }
            .frame(minHeight: AppTheme.searchControlHeight)
        }
    }

    private var noticeCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                DisclosureGroup(LegalEvidenceText.about) {
                    Text(AppStrings.LegalEvidence.accountSearchScopeNotice)
                    Text(AppStrings.LegalEvidence.immutableNotice)
                }
                .font(.footnote).foregroundStyle(AppTheme.textSecondary)

            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasSearchMinimumLength {
            ProfileDestinationEmptyStateCard(
                systemImage: "text.magnifyingglass",
                title: AppStrings.LegalEvidence.searchTooShortTitle,
                message: AppStrings.LegalEvidence.searchTooShortMessage
            )
        } else if viewModel.isLoading && !viewModel.hasLoaded {
            LoadingStateCard(title: AppStrings.LegalEvidence.loadingAccounts)
        } else if let errorMessage = viewModel.errorMessage, viewModel.accounts.isEmpty {
            ErrorStateCard(
                systemImage: "person.text.rectangle",
                title: AppStrings.LegalEvidence.loadFailedTitle,
                message: errorMessage,
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await viewModel.load() }
            }
        } else if viewModel.accounts.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: viewModel.normalizedSearch.isEmpty ? "person.crop.circle.badge.questionmark" : "magnifyingglass",
                title: viewModel.normalizedSearch.isEmpty
                    ? AppStrings.LegalEvidence.emptyAccountsTitle
                    : AppStrings.LegalEvidence.accountSearchEmptyTitle,
                message: viewModel.normalizedSearch.isEmpty
                    ? AppStrings.LegalEvidence.emptyAccountsMessage
                    : AppStrings.LegalEvidence.accountSearchEmptyMessage
            )
        } else {
            if let errorMessage = viewModel.errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

            DashboardSectionHeader(
                title: AppStrings.LegalEvidence.accountsTitle,
                subtitle: accountCountSubtitle
            )

            LazyVStack(spacing: AppTheme.eventsListRowSpacing) {
                ForEach(viewModel.accounts) { account in
                    NavigationLink {
                        LegalEvidenceUserDetailView(account: account, repository: repository, legalRepository: legalRepository)
                    } label: {
                        LegalEvidenceAccountRow(account: account)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("legalEvidence.account.\(account.id)")
                }
            }

            if viewModel.canLoadMore {
                PrimaryActionButton(
                    title: AppStrings.LegalEvidence.loadMoreAccounts,
                    loadingTitle: AppStrings.LegalEvidence.loadingAccounts,
                    isLoading: viewModel.isLoadingMore,
                    systemImage: "arrow.down.circle"
                ) {
                    Task { await viewModel.load(reset: false) }
                }
            }
        }
    }

    private var accountCountSubtitle: String {
        if let totalMatches = viewModel.totalMatches {
            return AppStrings.legalEvidenceSearchResultCount(totalMatches)
        }
        return AppStrings.legalEvidenceLoadedAccountCount(viewModel.accounts.count)
    }
}

private struct LegalEvidenceAccountRow: View {
    let account: LegalEvidenceAccount

    var body: some View {
        AppEditorSectionCard {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentPrimarySoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if let email = account.email, email != account.title {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    if let createdAt = account.createdAt {
                        Label(
                            AppStrings.legalEvidenceAccountCreated(
                                LocalizationStore.dateString(from: createdAt, dateStyle: .medium, timeStyle: .none)
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Spacer(minLength: 8)

            }
            .contentShape(Rectangle())
        }
    }
}

private struct LegalEvidenceUserDetailView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    let legalRepository: LegalDocumentRepository
    @StateObject private var viewModel: LegalEvidenceUserViewModel
    @FocusState private var isHistorySearchFocused: Bool

    init(account: LegalEvidenceAccount, repository: LegalEvidenceRepository, legalRepository: LegalDocumentRepository) {
        self.legalRepository = legalRepository
        _viewModel = StateObject(
            wrappedValue: LegalEvidenceUserViewModel(account: account, repository: repository)
        )
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.LegalEvidence.accountDetailTitle,
            introSubtitle: viewModel.account.title,
            contentSpacing: AppTheme.feedRowSpacing
        ) {
            accountCard
            if !viewModel.summary.isEmpty { summaryCard }
            historySearchField
            filterCard
            Button {
                Task { await viewModel.prepareExport() }
            } label: {
                Label(viewModel.isExporting ? LegalEvidenceText.exporting : LegalEvidenceText.prepareExport, systemImage: "square.and.arrow.down")
            }.disabled(viewModel.isExporting || viewModel.isLoading)
            .accessibilityIdentifier("legalEvidence.prepareExport")
            if let export = viewModel.exportText {
                ShareLink(item: export) {
                    Label(AppStrings.LegalEvidence.exportHistory, systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("legalEvidence.export")
            }
            if let message = viewModel.errorMessage { InlineMessageCard(style: .error, message: message) }
            content
            if viewModel.canLoadMore {
                Text(LegalEvidenceText.partial).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                PrimaryActionButton(title: LegalEvidenceText.more, loadingTitle: AppStrings.LegalEvidence.loading,
                    isLoading: viewModel.isLoadingMore, systemImage: "arrow.down.circle") {
                    Task { await viewModel.load(reset: false) }
                }.disabled(viewModel.isLoading).accessibilityIdentifier("legalEvidence.loadMore")
            }
        }
        .task(id: viewModel.requestKey) {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            if !viewModel.searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            await viewModel.load()
        }
        .onChange(of: authState.user?.id) { _, _ in viewModel.clear(); dismiss() }
        .appRefreshable { await viewModel.load() }
        .accessibilityIdentifier("screen.legalEvidence.user")
    }

    private var accountCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Label(viewModel.account.title, systemImage: "person.crop.circle.fill")
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                if let email = viewModel.account.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .textSelection(.enabled)
                }

                DisclosureGroup(LegalEvidenceText.details) {
                    Text(viewModel.account.userID).font(.caption.monospaced()).textSelection(.enabled)
                    if let createdAt = viewModel.account.createdAt {
                        Text(AppStrings.legalEvidenceAccountCreated(LocalizationStore.dateString(from: createdAt)))
                    }
                    Text(AppStrings.LegalEvidence.currentIdentityNotice)
                }.font(.footnote).foregroundStyle(AppTheme.textSecondary)

            }
        }
    }

    private var summaryCard: some View {
        AppEditorSectionCard {
            Text(LegalEvidenceText.summary).font(.headline)
            ForEach(viewModel.summary) { status in
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title).font(.subheadline.weight(.semibold))
                    Text(statusTitle(status.state)).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    if let version = status.version { Text(AppStrings.legalVersionLabel(version)).font(.caption) }
                    if let date = status.date { Text(LocalizationStore.dateString(from: date)).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if viewModel.summary.isEmpty { Text(LegalEvidenceText.unknown).font(.subheadline).foregroundStyle(AppTheme.textSecondary) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("legalEvidence.summary")
    }

    private func statusTitle(_ state: String) -> String {
        switch state {
        case "current": LegalEvidenceText.current
        case "outdated": LegalEvidenceText.outdated
        case "confirmed": LegalEvidenceText.confirmed
        case "granted": LegalEvidenceText.granted
        case "withdrawn": LegalEvidenceText.withdrawn
        default: LegalEvidenceText.unknown
        }
    }

    private var historySearchField: some View {
        AppGlassCard(padding: 12, spacing: 8, shadowRadius: 8, shadowY: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)

                TextField(AppStrings.LegalEvidence.searchPlaceholder, text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($isHistorySearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isHistorySearchFocused = false }
                    .accessibilityIdentifier("legalEvidence.historySearch")

                if !viewModel.searchText.isEmpty {
                    AppSearchClearButton { viewModel.searchText = "" }
                }
            }
            .frame(minHeight: AppTheme.searchControlHeight)
        }
    }

    private var filterCard: some View {
        AppEditorSectionCard {
            HStack {
                Label(AppStrings.LegalEvidence.filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                    .font(AppTheme.buttonLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: 8)

                Picker(AppStrings.LegalEvidence.filterTitle, selection: $viewModel.filter) {
                    ForEach(LegalEvidenceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("legalEvidence.filter")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            LoadingStateCard(title: AppStrings.LegalEvidence.loading)
        } else if let errorMessage = viewModel.errorMessage, viewModel.events.isEmpty {
            ErrorStateCard(
                systemImage: "signature",
                title: AppStrings.LegalEvidence.loadFailedTitle,
                message: errorMessage,
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await viewModel.load() }
            }
        } else if viewModel.filteredEvents.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "signature",
                title: viewModel.filter == .all && viewModel.searchText.isEmpty ? AppStrings.LegalEvidence.emptyTitle : AppStrings.LegalEvidence.searchEmptyTitle,
                message: viewModel.canLoadMore ? LegalEvidenceText.continueHistory : viewModel.filter == .all && viewModel.searchText.isEmpty ? AppStrings.LegalEvidence.emptyMessage : AppStrings.LegalEvidence.searchEmptyMessage
            )
        } else {
            DashboardSectionHeader(
                title: LegalEvidenceText.loaded,
                subtitle: AppStrings.legalEvidenceConfirmationCount(viewModel.filteredEvents.count)
            )


            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(viewModel.filteredEvents) { event in
                    LegalEvidenceEventCard(event: event, legalRepository: legalRepository)
                }
            }
        }
    }
}

private struct LegalEvidenceEventCard: View {
    let event: LegalEvidenceEvent
    let legalRepository: LegalDocumentRepository

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.eventType.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.eventType.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if let organizationName = event.organizationName {
                        Label(organizationName, systemImage: "building.2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    if let organizationID = event.organizationID {
                        Text("\(AppStrings.LegalEvidence.organizationLabel): \(organizationID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { evidenceChips }
                        VStack(alignment: .leading, spacing: 8) { evidenceChips }
                    }

                    if event.documentType != nil, event.version != nil {
                        NavigationLink {
                            LegalEvidenceVersionView(event: event, repository: legalRepository)
                        } label: { Label(LegalEvidenceText.readVersion, systemImage: "doc.text") }
                        .accessibilityIdentifier("legalEvidence.readVersion.\(event.id)")
                    }
                    if event.source == "profileSnapshot" {
                        Text(LegalEvidenceText.profileNotice).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                    DisclosureGroup(LegalEvidenceText.details) {
                        if let contentHash = event.contentHash {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(AppStrings.LegalEvidence.contentHashLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(contentHash)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }

                        provenanceDetails
                    }.font(.footnote).foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("legalEvidence.event.\(event.id)")
    }

    @ViewBuilder
    private var provenanceDetails: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { technicalChips }
            VStack(alignment: .leading, spacing: 8) { technicalChips }
        }

        if let sourceRecordID = event.sourceRecordID {
            evidenceDetail(AppStrings.LegalEvidence.sourceRecordIDLabel, value: sourceRecordID, monospaced: true)
        }
        if let platform = event.acceptedFromPlatform {
            evidenceDetail(AppStrings.LegalEvidence.platformLabel, value: platform)
        }
        if let consentID = event.consentID {
            evidenceDetail(AppStrings.LegalEvidence.consentIDLabel, value: consentID, monospaced: true)
        }
        if let purposeVersion = event.purposeVersion {
            evidenceDetail(AppStrings.LegalEvidence.purposeVersionLabel, value: purposeVersion)
        }
        if let disclosureVersion = event.disclosureVersion {
            evidenceDetail(AppStrings.LegalEvidence.disclosureVersionLabel, value: disclosureVersion)
        }
        if let disclosureText = event.disclosureText {
            evidenceDetail(AppStrings.LegalEvidence.disclosureTextLabel, value: disclosureText)
        }
    }

    private func evidenceDetail(_ label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(monospaced ? .caption2.monospaced() : .caption2)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var evidenceChips: some View {
        AppInfoChip(
            title: LocalizationStore.dateString(from: event.occurredAt, dateStyle: .medium, timeStyle: .short),
            systemImage: "calendar.badge.clock"
        )

        if let version = event.version {
            AppInfoChip(title: AppStrings.legalVersionLabel(version), systemImage: "number")
        }
    }

    @ViewBuilder
    private var technicalChips: some View {
        if let locale = event.locale {
            AppInfoChip(title: locale.uppercased(), systemImage: "globe")
        }

        if let appVersion = event.appVersion {
            AppInfoChip(title: appVersion, systemImage: "apps.iphone")
        }

        AppInfoChip(title: sourceTitle, systemImage: "server.rack")
    }

    private var sourceTitle: String {
        switch event.source {
        case "registration": AppStrings.LegalEvidence.sourceRegistration
        case "profileSnapshot": LegalEvidenceText.profileSnapshot
        case "legalDocument": AppStrings.LegalEvidence.sourceLegalDocument
        case "analyticsConsent": AppStrings.LegalEvidence.sourceAnalytics
        default: AppStrings.LegalEvidence.sourceServer
        }
    }
}
