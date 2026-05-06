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
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.organizations.isEmpty && viewModel.error != nil {
                OrganizationsStateView(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.title,
                    subtitle: errorText
                ) {
                    Button(AppStrings.Organizations.retry) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.organizations.isEmpty {
                OrganizationsStateView(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.title,
                    subtitle: AppStrings.Organizations.empty
                ) {
                    Button(AppStrings.Organizations.retry) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        VStack(spacing: 8) {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(AppStrings.Organizations.retry) {
                                Task {
                                    await viewModel.refresh()
                                }
                            }
                            .buttonStyle(.bordered)
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

private struct OrganizationsStateView<ActionContent: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let actionContent: ActionContent

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                actionContent
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
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
