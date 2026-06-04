import SwiftUI

struct GuideCategoryDetailView: View {
    let category: GuideCategory
    @StateObject private var viewModel: GuideReaderViewModel

    init(category: GuideCategory, viewModel: GuideReaderViewModel) {
        self.category = category
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        DetailPageContainer {
            compactHeader

            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationTitle(GuideCategoryPresentation.publicTitle(for: category))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.selectCategory(category)
        }
    }

    private var compactHeader: some View {
        GuideHierarchyHeaderCard(
            title: GuideCategoryPresentation.publicTitle(for: category),
            subtitle: GuideCategoryPresentation.subtitle(for: category),
            badgeSystemImage: category.systemImage,
            badgeTitle: GuideCategoryPresentation.guideBadgeTitle,
            contextText: nil
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            GuideLoadingView()
        } else if let error = viewModel.error {
            GuideErrorStateView(error: error) {
                Task {
                    await viewModel.reload()
                }
            }
        } else if viewModel.visibleChildNodes.isEmpty {
            EmptyStateCard(
                systemImage: category.systemImage,
                title: GuideCategoryPresentation.publicTitle(for: category),
                message: GuideCategoryPresentation.categoryEmptyMessage
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideCategoryPresentation.categorySectionsTitle,
                    subtitle: GuideCategoryPresentation.categorySectionsSubtitle
                )

                ForEach(viewModel.visibleChildNodes) { node in
                    NavigationLink {
                        GuideSectionDetailView(
                            node: node,
                            viewModel: viewModel.makeChildViewModel()
                        )
                    } label: {
                        GuideSectionCard(node: node)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
