import SwiftUI

struct LegalEvidenceView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: LegalEvidenceViewModel

    init(repository: LegalEvidenceRepository = CloudLegalEvidenceRepository()) {
        _viewModel = StateObject(wrappedValue: LegalEvidenceViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.LegalEvidence.title,
            introSubtitle: AppStrings.LegalEvidence.subtitle,
            contentSpacing: AppTheme.feedRowSpacing
        ) {
            if !PermissionService.isAppOwner(user: authState.user) {
                ErrorStateCard(
                    systemImage: "lock.fill",
                    title: AppStrings.LegalEvidence.permissionTitle,
                    message: AppStrings.LegalEvidence.permissionMessage
                )
            } else {
                filterCard
                content
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(AppStrings.LegalEvidence.searchPlaceholder)
        )
        .task {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            await viewModel.load()
        }
        .refreshable {
            guard PermissionService.isAppOwner(user: authState.user) else { return }
            await viewModel.load()
        }
        .accessibilityIdentifier("screen.legalEvidence")
    }

    private var filterCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
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

                Text(AppStrings.LegalEvidence.immutableNotice)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasLoadedContent {
            LoadingStateCard(title: AppStrings.LegalEvidence.loading)
        } else if let errorMessage = viewModel.errorMessage, !viewModel.hasLoadedContent {
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
                systemImage: viewModel.searchText.isEmpty ? "signature" : "magnifyingglass",
                title: viewModel.searchText.isEmpty
                    ? AppStrings.LegalEvidence.emptyTitle
                    : AppStrings.LegalEvidence.searchEmptyTitle,
                message: viewModel.searchText.isEmpty
                    ? AppStrings.LegalEvidence.emptyMessage
                    : AppStrings.LegalEvidence.searchEmptyMessage
            )
        } else {
            if let errorMessage = viewModel.errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

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
                    .background(
                        AppTheme.accentPrimarySoft,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.eventType.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(event.userTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if let email = event.email, email != event.userTitle {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                    }

                    Text(event.userID)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.textSecondary)
                        .textSelection(.enabled)

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
            title: LocalizationStore.dateString(
                from: event.occurredAt,
                dateStyle: .medium,
                timeStyle: .short
            ),
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
    }
}
