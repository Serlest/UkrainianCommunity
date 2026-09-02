import SwiftUI

struct BlockedOrganizationsView: View {
    @EnvironmentObject private var coordinator: OrganizationBlockingCoordinator

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Safety.blockedOrganizationsTitle,
            introSubtitle: AppStrings.Safety.blockedOrganizationsExplanation
        ) {
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
                ForEach(coordinator.blockedOrganizations) { organization in
                    AppEditorSectionCard {
                        HStack {
                            Text(organization.name).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button(AppStrings.Safety.unblockAction) {
                                Task { await coordinator.setBlocked(organizationID: organization.id, isBlocked: false) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(coordinator.isMutating)
                            .accessibilityIdentifier("organization.unblock.\(organization.id)")
                        }
                    }
                }
            }
        }
        .task { await coordinator.reload() }
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
