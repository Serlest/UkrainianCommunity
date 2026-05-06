import SwiftUI

struct MarketplaceListView: View {
    @ObservedObject var viewModel: MarketplaceViewModel

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Marketplace.loadNetworkError
        case .permissionDenied:
            AppStrings.Marketplace.loadPermissionError
        case .validationFailed:
            AppStrings.Marketplace.loadValidationError
        case .notFound:
            AppStrings.Marketplace.empty
        case .unknown:
            AppStrings.Marketplace.loadUnknownError
        case nil:
            ""
        }
    }

    var body: some View {
        ScrollView {
            if viewModel.items.isEmpty && viewModel.isLoading {
                VStack {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.items.isEmpty && viewModel.error != nil {
                MarketplaceStateView(
                    systemImage: "basket",
                    title: AppStrings.Marketplace.title,
                    subtitle: errorText
                ) {
                    Button(AppStrings.Marketplace.retry) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.items.isEmpty {
                MarketplaceStateView(
                    systemImage: "basket",
                    title: AppStrings.Marketplace.title,
                    subtitle: AppStrings.Marketplace.empty
                ) {
                    Button(AppStrings.Marketplace.retry) {
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

                            Button(AppStrings.Marketplace.retry) {
                                Task {
                                    await viewModel.refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 16)
                    }

                    AdaptiveCardGrid(items: viewModel.items) { item in
                        NavigationLink {
                            MarketplaceDetailView(viewModel: viewModel, itemID: item.id)
                        } label: {
                            MarketplaceCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("marketplace.link.\(item.id)")
                    }
                    .padding()
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Marketplace.title)
        .accessibilityIdentifier("marketplace.list")
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct MarketplaceStateView<ActionContent: View>: View {
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

private struct MarketplaceCard: View {
    let item: MarketplaceItem

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: item.imageURL, height: 220, source: "MarketplaceCard")

            Text(item.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MetadataRow(label: AppStrings.Common.price, value: marketplacePriceText, systemImage: "eurosign")
            MetadataRow(label: AppStrings.Common.city, value: item.city, systemImage: "mappin")
            MetadataRow(label: AppStrings.Marketplace.category, value: item.category, systemImage: "tag")
        }
    }

    private var marketplacePriceText: String {
        CurrencyFormatter.priceString(for: item.price, currencyCode: item.currency)
    }
}

struct MarketplaceDetailView: View {
    @ObservedObject var viewModel: MarketplaceViewModel
    let itemID: String

    var body: some View {
        Group {
            if let item = viewModel.item(for: itemID) {
                DetailPageContainer {
                    DetailHeaderCard(title: item.title, subtitle: item.category) {
                        MetadataRow(label: AppStrings.Common.city, value: item.city, systemImage: "mappin")
                    }

                    if item.imageURL != nil {
                        DetailImageCard(
                            imageURL: item.imageURL,
                            height: 260,
                            source: "MarketplaceDetailView"
                        )
                    }

                    DetailCard {
                        Text(item.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DetailCard {
                        MetadataRow(label: AppStrings.Common.price, value: CurrencyFormatter.priceString(for: item.price, currencyCode: item.currency), systemImage: "eurosign")
                        MetadataRow(label: AppStrings.Common.city, value: item.city, systemImage: "mappin")
                        MetadataRow(label: AppStrings.Marketplace.category, value: item.category, systemImage: "tag")

                        if let contactEmail = item.contactEmail, !contactEmail.isEmpty {
                            MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                        }

                        if let expiresAt = item.expiresAt {
                            MetadataRow(label: AppStrings.Common.expires, value: LocalizationStore.dateString(from: expiresAt), systemImage: "clock")
                        }
                    }

                    DetailCard {
                        DetailActionRow {
                            Text(AppStrings.Common.likes)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        } trailingContent: {
                            LikeButton(isLiked: item.likeState.isLiked, count: item.likeCount) {
                                viewModel.toggleLike(for: item.id)
                            }
                            .disabled(viewModel.pendingMarketplaceLikeIDs.contains(item.id))
                        }
                    }
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Marketplace.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("marketplace.detail.\(itemID)")
    }
}

#Preview("Marketplace List") {
    NavigationStack {
        MarketplaceListView(viewModel: MarketplaceViewModel(repository: MockMarketplaceRepository()))
    }
}

#Preview("Marketplace Detail") {
    NavigationStack {
        MarketplaceDetailView(viewModel: MarketplaceViewModel(repository: MockMarketplaceRepository()), itemID: MockContentBuilder.marketplaceItems().first!.id)
    }
}
