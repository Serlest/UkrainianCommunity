import SwiftUI

struct GuideTreeCategoryManagementView: View {
    @EnvironmentObject private var authState: AuthState
    let category: GuideCategory
    @StateObject private var viewModel: GuideReaderViewModel
    @State private var isPresentingRootEditor = false
    @State private var reorderingNodeID: String?
    private let writeRepository: GuideWriteRepositoryProtocol

    init(
        category: GuideCategory,
        viewModel: GuideReaderViewModel,
        writeRepository: GuideWriteRepositoryProtocol
    ) {
        self.category = category
        _viewModel = StateObject(wrappedValue: viewModel)
        self.writeRepository = writeRepository
    }

    var body: some View {
        DetailPageContainer {
            GuideManagementNavigationHeader()
                .padding(.top, AppTheme.dashboardSpacing)

            DetailHeaderCard(
                title: GuideCategoryPresentation.publicTitle(for: category),
                subtitle: GuideCategoryPresentation.subtitle(for: category)
            ) {
                AppInfoChip(
                    title: GuideAuthoringPresentation.rootSectionsChip,
                    systemImage: "square.grid.2x2",
                    tint: AppTheme.textSecondary,
                    fill: AppTheme.surfaceGlass,
                    size: .small
                )
            }

            GuideCategoryManagementActionPanel(
                onAddRootNode: { isPresentingRootEditor = true }
            )

            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.selectCategory(category)
        }
        .sheet(isPresented: $isPresentingRootEditor) {
            NavigationStack {
                GuideSectionEditorView(
                    viewModel: GuideSectionEditorViewModel(
                        mode: .createRoot(category: category),
                        repository: writeRepository,
                        currentUserID: authState.user?.id
                    )
                ) { _ in
                    await viewModel.reload()
                }
            }
        }
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
                message: GuideAuthoringPresentation.noSectionsYet
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: GuideAuthoringPresentation.sectionsListTitle,
                    subtitle: GuideAuthoringPresentation.sectionsListSubtitle
                )

                ForEach(Array(viewModel.visibleChildNodes.enumerated()), id: \.element.id) { index, node in
                    HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
                        NavigationLink {
                            GuideTreeSectionManagementView(
                                node: node,
                                viewModel: viewModel.makeChildViewModel(),
                                writeRepository: writeRepository,
                                onNodeDeleted: {
                                    await viewModel.reload()
                                }
                            )
                        } label: {
                            GuideManagementSectionCardView(node: node)
                        }
                        .buttonStyle(.plain)

                        GuideReorderControls(
                            canMoveUp: index > 0,
                            canMoveDown: index < viewModel.visibleChildNodes.count - 1,
                            isDisabled: reorderingNodeID != nil,
                            onMoveUp: {
                                Task { await moveNode(node, direction: .up) }
                            },
                            onMoveDown: {
                                Task { await moveNode(node, direction: .down) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func moveNode(_ node: GuideNode, direction: GuideReorderDirection) async {
        guard reorderingNodeID == nil else { return }
        let updates = viewModel.nodeSortOrderUpdates(moving: node.id, direction: direction)
        guard !updates.isEmpty else { return }

        reorderingNodeID = node.id
        defer { reorderingNodeID = nil }

        do {
            try await writeRepository.updateNodeSortOrders(
                updates,
                updatedAt: Date(),
                updatedBy: authState.user?.id
            )
            viewModel.applyNodeSortOrderUpdates(updates)
        } catch {
            await viewModel.reload()
        }
    }
}
