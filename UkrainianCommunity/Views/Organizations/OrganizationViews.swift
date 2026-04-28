import SwiftUI

struct OrganizationsListView: View {
    @ObservedObject var viewModel: OrganizationsViewModel

    var body: some View {
        ScrollView {
            AdaptiveCardGrid(items: viewModel.organizations) { organization in
                VStack(spacing: 10) {
                    NavigationLink {
                        OrganizationDetailView(viewModel: viewModel, organizationID: organization.id)
                    } label: {
                        OrganizationCard(organization: organization)
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Spacer()
                        LikeButton(isLiked: organization.likeState.isLiked, count: organization.likeCount) {
                            viewModel.toggleLike(for: organization.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding()
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Organizations.title)
    }
}

private struct OrganizationCard: View {
    let organization: Organization

    var body: some View {
        CommunityCard {
            Text(organization.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(organization.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: organization.name, subtitle: organization.summary) {
                            Text(organization.city)
                                .font(.subheadline.weight(.semibold))
                        }

                        CommunityCard {
                            Text(organization.mission)
                            MetadataRow(label: AppStrings.Common.contact, value: organization.contactEmail, systemImage: "envelope")
                            MetadataRow(label: AppStrings.Common.website, value: organization.website, systemImage: "link")
                            LikeButton(isLiked: organization.likeState.isLiked, count: organization.likeCount) {
                                viewModel.toggleLike(for: organization.id)
                            }
                        }

                        CommunityCard {
                            ForEach(organization.focusAreas, id: \.self) { area in
                                Label(area, systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(AppTheme.primaryBlue)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Organizations.title)
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
