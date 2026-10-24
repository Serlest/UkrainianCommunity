import SwiftUI

struct OrganizationContentVisibilityGate: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        Group {
            if isLoading {
                LoadingStateCard(title: AppStrings.Safety.verifyingOrganizationContent)
            } else {
                ErrorStateCard(
                    title: AppStrings.Safety.organizationVisibilityUnavailableTitle,
                    message: AppStrings.Safety.organizationVisibilityUnavailableMessage,
                    retryTitle: AppStrings.Action.retry,
                    retryAction: retry
                )
            }
        }
        .accessibilityIdentifier("organization.block.visibilityGate")
    }
}

struct BlockedOrganizationsView: View {
    @EnvironmentObject private var coordinator: OrganizationBlockingCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var pendingUnblock: BlockedOrganization?
    private var visibleOrganizations: [BlockedOrganization] {
        coordinator.blockedOrganizations.filter { LocalSearchMatcher.matches(query: searchText, values: [$0.name]) }
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Safety.blockedOrganizationsTitle,
            introSubtitle: SettingsPrivacyText.hiddenOrganizationsIntro
        ) {
            if !coordinator.blockedOrganizations.isEmpty {
                AppSearchField(placeholder: SettingsPrivacyText.hiddenSearch, text: $searchText)
            }
            if coordinator.isLoading && coordinator.blockedOrganizations.isEmpty {
                LoadingStateCard(title: AppStrings.Safety.blockedOrganizationsTitle)
            } else {
                if let error = coordinator.errorMessage {
                    ErrorStateCard(
                        title: AppStrings.Safety.blockedOrganizationsTitle,
                        message: error, retryTitle: AppStrings.Action.retry
                    ) { Task { await coordinator.reload() } }
                }
                if coordinator.blockedOrganizations.isEmpty && coordinator.errorMessage == nil {
                    ProfileDestinationEmptyStateCard(
                        systemImage: "building.2", title: AppStrings.Safety.blockedOrganizationsEmpty,
                        message: AppStrings.Safety.blockedOrganizationsExplanation
                    )
                }
                if !coordinator.blockedOrganizations.isEmpty && visibleOrganizations.isEmpty {
                    ProfileDestinationEmptyStateCard(systemImage: "magnifyingglass", title: AppStrings.Search.noResultsTitle, message: AppStrings.Search.noResultsMessage)
                }
                ForEach(visibleOrganizations) { organization in
                    AppEditorSectionCard {
                        (dynamicTypeSize.isAccessibilitySize
                         ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                         : AnyLayout(HStackLayout(spacing: 12))) {
                            Text(organization.name).fixedSize(horizontal: false, vertical: true)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Button(AppStrings.Safety.unblockAction) { pendingUnblock = organization }
                            .buttonStyle(.bordered)
                            .disabled(coordinator.isMutating)
                            .accessibilityIdentifier("organization.unblock.\(organization.id)")
                        }
                    }
                }
            }
        }
        .confirmationDialog(SettingsPrivacyText.showOrganizationTitle, isPresented: Binding(
            get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } }
        ), presenting: pendingUnblock) { organization in
            Button(AppStrings.Safety.unblockAction, role: .destructive) {
                Task { await coordinator.setBlocked(organizationID: organization.id, isBlocked: false) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: { organization in
            Text(SettingsPrivacyText.showOrganizationMessage(organization.name))
        }
        .task { await coordinator.reload() }
        .appRefreshable { await coordinator.reload() }
        .accessibilityIdentifier("screen.profile.blockedOrganizations")
    }
}

struct OrganizationBlockConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: OrganizationBlockingCoordinator
    let target: OrganizationBlockTarget

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Text(target.name).font(.title2.bold())
                    Text(AppStrings.Safety.blockedOrganizationsExplanation)
                    if let error = coordinator.errorMessage {
                        InlineMessageCard(style: .error, message: error)
                    }
                    Button(AppStrings.Safety.blockOrganizationAction, role: .destructive) {
                        Task {
                            if await coordinator.setBlocked(organizationID: target.organizationID, isBlocked: true) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentPrimary)
                    .disabled(coordinator.isMutating)
                    .accessibilityIdentifier("organization.block.confirm")
                }
                .padding(AppTheme.pageHorizontal)
            }
            .navigationTitle(AppStrings.Safety.blockOrganizationAction)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
