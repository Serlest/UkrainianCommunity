import SwiftUI

struct MarketplaceListView: View {
    @ObservedObject var viewModel: MarketplaceViewModel

    var body: some View {
        ScrollView {
            AdaptiveCardGrid(items: viewModel.items) { item in
                VStack(spacing: 10) {
                    NavigationLink {
                        MarketplaceDetailView(viewModel: viewModel, itemID: item.id)
                    } label: {
                        MarketplaceCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("marketplace.link.\(item.id)")

                    HStack {
                        Spacer()
                        LikeButton(isLiked: item.likeState.isLiked, count: item.likeCount) {
                            viewModel.toggleLike(for: item.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding()
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Marketplace.title)
        .accessibilityIdentifier("marketplace.list")
    }
}

private struct MarketplaceCard: View {
    let item: MarketplaceItem

    var body: some View {
        CommunityCard {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            MetadataRow(label: AppStrings.Common.city, value: item.city, systemImage: "mappin")
            MetadataRow(label: AppStrings.Common.price, value: marketplacePrice(item), systemImage: "eurosign")
        }
    }

    private func marketplacePrice(_ item: MarketplaceItem) -> String {
        if item.isFreeGift {
            return AppStrings.Marketplace.freeGift
        }
        return CurrencyFormatter.priceString(for: item.price)
    }
}

struct MarketplaceDetailView: View {
    @ObservedObject var viewModel: MarketplaceViewModel
    let itemID: String

    var body: some View {
        Group {
            if let item = viewModel.item(for: itemID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: item.title, subtitle: item.description) {
                            Text(item.moderationStatus.title)
                                .font(.subheadline.weight(.semibold))
                        }

                        CommunityCard {
                            MetadataRow(label: AppStrings.Common.city, value: item.city, systemImage: "mappin")
                            MetadataRow(label: AppStrings.Common.price, value: item.isFreeGift ? AppStrings.Marketplace.freeGift : CurrencyFormatter.priceString(for: item.price), systemImage: "eurosign")
                            MetadataRow(label: AppStrings.Common.contact, value: AppStrings.contactLine(method: item.contactMethod.title, value: item.contactValue), systemImage: "message")
                            MetadataRow(label: AppStrings.Common.expires, value: LocalizationStore.dateString(from: item.expirationDate), systemImage: "clock")
                            MetadataRow(label: AppStrings.Common.status, value: item.moderationStatus.title, systemImage: "checkmark.shield")
                            LikeButton(isLiked: item.likeState.isLiked, count: item.likeCount) {
                                viewModel.toggleLike(for: item.id)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Marketplace.title)
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
