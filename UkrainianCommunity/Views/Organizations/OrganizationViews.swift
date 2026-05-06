import SwiftUI

struct OrganizationsListView: View {
    @ObservedObject var viewModel: OrganizationsViewModel

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.loadPermissionError
        case .validationFailed:
            AppStrings.Organizations.loadValidationError
        case .notFound:
            AppStrings.Organizations.empty
        case .unknown:
            AppStrings.Organizations.loadUnknownError
        case nil:
            ""
        }
    }

    var body: some View {
        ScrollView {
            if viewModel.organizations.isEmpty && viewModel.isLoading {
                VStack {
                    LoadingStateCard(title: nil)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.organizations.isEmpty && viewModel.error != nil {
                ErrorStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.title,
                    message: errorText,
                    retryTitle: AppStrings.Organizations.retry
                ) {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.organizations.isEmpty {
                EmptyStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.title,
                    message: AppStrings.Organizations.empty
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        ErrorStateCard(
                            title: AppStrings.Organizations.title,
                            message: errorText,
                            retryTitle: AppStrings.Organizations.retry
                        ) {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    AdaptiveCardGrid(items: viewModel.organizations) { organization in
                        NavigationLink {
                            OrganizationDetailView(viewModel: viewModel, organizationID: organization.id)
                        } label: {
                            OrganizationCard(organization: organization)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Organizations.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct OrganizationCard: View {
    let organization: Organization

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: organization.imageURL, height: 220, source: "OrganizationCard")

            Text(organization.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(organization.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            MetadataRow(label: AppStrings.Common.city, value: organization.city, systemImage: "mappin")
        }
    }
}

struct OrganizationDetailView: View {
    @ObservedObject var viewModel: OrganizationsViewModel
    let organizationID: String

    var body: some View {
        Group {
            if let organization = viewModel.organization(for: organizationID) {
                DetailPageContainer {
                    DetailHeaderCard(title: organization.name, subtitle: organization.city) {
                        if let contactEmail = organization.contactEmail, !contactEmail.isEmpty {
                            MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                        }
                    }

                    if organization.imageURL != nil {
                        DetailImageCard(
                            imageURL: organization.imageURL,
                            height: 260,
                            source: "OrganizationDetailView"
                        )
                    }

                    DetailCard {
                        Text(organization.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DetailCard {
                        MetadataRow(label: AppStrings.Common.city, value: organization.city, systemImage: "mappin")

                        if let contactEmail = organization.contactEmail, !contactEmail.isEmpty {
                            MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                        }

                        if let website = organization.website, !website.isEmpty {
                            MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                        }
                    }
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Organizations.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Organizations List") {
    NavigationStack {
        OrganizationsListView(viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()))
    }
}

#Preview("Organization Detail") {
    NavigationStack {
        OrganizationDetailView(viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()), organizationID: MockContentBuilder.organizations().first!.id)
    }
}
