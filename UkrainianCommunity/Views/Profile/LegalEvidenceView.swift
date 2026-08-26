import SwiftUI

struct LegalEvidenceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: LegalEvidenceViewModel
    @FocusState private var isSearchFocused: Bool
    private let repository: LegalEvidenceRepository

    init(repository: LegalEvidenceRepository = CloudLegalEvidenceRepository()) {
        self.repository = repository
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
        .refreshable {
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
                Label(AppStrings.LegalEvidence.accountsTitle, systemImage: "person.text.rectangle")
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.LegalEvidence.accountListInstruction)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppStrings.LegalEvidence.immutableNotice)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                        LegalEvidenceUserDetailView(account: account, repository: repository)
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

                    Text(account.userID)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}

private struct LegalEvidenceUserDetailView: View {
    @StateObject private var viewModel: LegalEvidenceUserViewModel

    init(account: LegalEvidenceAccount, repository: LegalEvidenceRepository) {
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
            filterCard
            content
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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

                Text(viewModel.account.userID)
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .textSelection(.enabled)

                if let createdAt = viewModel.account.createdAt {
                    AppInfoChip(
                        title: AppStrings.legalEvidenceAccountCreated(
                            LocalizationStore.dateString(from: createdAt, dateStyle: .medium, timeStyle: .short)
                        ),
                        systemImage: "calendar"
                    )
                }
            }
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
                title: viewModel.events.isEmpty ? AppStrings.LegalEvidence.emptyTitle : AppStrings.LegalEvidence.searchEmptyTitle,
                message: viewModel.events.isEmpty ? AppStrings.LegalEvidence.emptyMessage : AppStrings.LegalEvidence.searchEmptyMessage
            )
        } else {
            if let errorMessage = viewModel.errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

            DashboardSectionHeader(
                title: AppStrings.LegalEvidence.confirmationHistoryTitle,
                subtitle: AppStrings.legalEvidenceConfirmationCount(viewModel.filteredEvents.count)
            )

            ForEach(viewModel.filteredEvents) { event in
                LegalEvidenceEventCard(event: event)
            }
        }
    }
}

private struct LegalEvidenceEventCard: View {
    let event: LegalEvidenceEvent

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
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("legalEvidence.event.\(event.id)")
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
        case "legalDocument": AppStrings.LegalEvidence.sourceLegalDocument
        case "analyticsConsent": AppStrings.LegalEvidence.sourceAnalytics
        default: AppStrings.LegalEvidence.sourceServer
        }
    }
}
