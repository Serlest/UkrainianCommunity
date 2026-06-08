import SwiftUI

struct GuideSectionDetailView: View {
    let node: GuideNode
    let feedbackRepository: FeedbackRepository
    @StateObject private var viewModel: GuideReaderViewModel

    init(node: GuideNode, viewModel: GuideReaderViewModel, feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository()) {
        self.node = node
        self.feedbackRepository = feedbackRepository
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        DetailScreenShell {
            compactHeader

            content
        }
        .task {
            await viewModel.openNode(node)
        }
    }

    private var compactHeader: some View {
        GuideHierarchyHeaderCard(
            title: node.title,
            subtitle: node.summary.nilIfBlank,
            badgeSystemImage: node.displaySystemImage,
            badgeTitle: GuideCategoryPresentation.sectionBadgeTitle,
            contextText: pathDescription.nilIfBlank
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
        } else if !viewModel.hasContent {
            EmptyStateCard(
                systemImage: "tray",
                title: node.title,
                message: GuideCategoryPresentation.nodeEmptyMessage
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing + 4) {
                if !viewModel.visibleChildNodes.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing + 4) {
                        SectionHeaderBlock(
                            title: GuideCategoryPresentation.nodeSectionsTitle,
                            subtitle: GuideCategoryPresentation.nodeSectionsSubtitle
                        )

                        ForEach(viewModel.visibleChildNodes) { childNode in
                            NavigationLink {
                                GuideSectionDetailView(
                                    node: childNode,
                                    viewModel: viewModel.makeChildViewModel(),
                                    feedbackRepository: feedbackRepository
                                )
                            } label: {
                                GuideSectionCard(node: childNode)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !viewModel.visibleMaterials.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing + 4) {
                        SectionHeaderBlock(
                            title: GuideCategoryPresentation.nodeMaterialsTitle,
                            subtitle: GuideCategoryPresentation.nodeMaterialsSubtitle
                        )

                        ForEach(viewModel.visibleMaterials) { material in
                            NavigationLink {
                                GuideMaterialDetailView(
                                    material: material,
                                    viewModel: viewModel,
                                    feedbackRepository: feedbackRepository
                                )
                            } label: {
                                GuideMaterialCard(material: material)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var pathDescription: String {
        let components = viewModel.breadcrumbs.components.map(\.title)
        return components.joined(separator: " → ")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
