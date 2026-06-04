import SwiftUI

struct GuideTreeSectionManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    let node: GuideNode
    let onNodeDeleted: @MainActor () async -> Void
    @StateObject private var viewModel: GuideReaderViewModel
    @State private var managedNode: GuideNode
    @State private var selectedTab: GuideManagementTab = .sections
    @State private var isPresentingChildEditor = false
    @State private var isPresentingEditEditor = false
    @State private var isPresentingMaterialEditor = false
    @State private var editingMaterial: GuideMaterial?
    @State private var materialPendingDelete: GuideMaterial?
    @State private var isPresentingDeleteConfirmation = false
    @State private var deleteAlertMessage: String?
    @State private var isDeleting = false
    private let writeRepository: GuideWriteRepositoryProtocol

    init(
        node: GuideNode,
        viewModel: GuideReaderViewModel,
        writeRepository: GuideWriteRepositoryProtocol,
        onNodeDeleted: @escaping @MainActor () async -> Void = {}
    ) {
        self.node = node
        self.onNodeDeleted = onNodeDeleted
        _viewModel = StateObject(wrappedValue: viewModel)
        _managedNode = State(initialValue: node)
        self.writeRepository = writeRepository
    }

    var body: some View {
        DetailPageContainer {
            navigationHeader
                .padding(.top, AppTheme.dashboardSpacing)

            headerCard
            tabPickerCard
            tabActionCard
            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.openNode(managedNode)
        }
        .sheet(isPresented: $isPresentingChildEditor) {
            NavigationStack {
                GuideSectionEditorView(
                    viewModel: GuideSectionEditorViewModel(
                        mode: .createChild(parent: managedNode),
                        repository: writeRepository,
                        currentUserID: authState.user?.id
                    )
                ) { _ in
                    await viewModel.reload()
                }
            }
        }
        .sheet(isPresented: $isPresentingEditEditor) {
            NavigationStack {
                GuideSectionEditorView(
                    viewModel: GuideSectionEditorViewModel(
                        mode: .edit(node: managedNode),
                        repository: writeRepository,
                        currentUserID: authState.user?.id
                    )
                ) { savedNode in
                    managedNode = savedNode
                    await viewModel.openNode(savedNode)
                }
            }
        }
        .sheet(isPresented: $isPresentingMaterialEditor) {
            NavigationStack {
                GuideMaterialEditorView(
                    viewModel: GuideMaterialEditorViewModel(
                        mode: .create(
                            node: managedNode,
                            nodePath: viewModel.breadcrumbs
                        ),
                        repository: writeRepository,
                        currentUserID: authState.user?.id
                    )
                ) { _ in
                    await viewModel.reload()
                }
            }
        }
        .sheet(item: $editingMaterial) { material in
            NavigationStack {
                GuideMaterialEditorView(
                    viewModel: GuideMaterialEditorViewModel(
                        mode: .edit(material: material),
                        repository: writeRepository,
                        currentUserID: authState.user?.id
                    )
                ) { _ in
                    await viewModel.reload()
                }
            }
        }
        .confirmationDialog(
            GuideAuthoringPresentation.deleteSectionTitle,
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(GuideAuthoringPresentation.deleteSection, role: .destructive) {
                Task {
                    await deleteSection()
                }
            }
            Button(GuideAuthoringPresentation.cancelLabel, role: .cancel) {}
        } message: {
            Text(GuideAuthoringPresentation.deleteIrreversibleMessage)
        }
        .confirmationDialog(
            GuideAuthoringPresentation.deleteMaterialTitle,
            isPresented: Binding(
                get: { materialPendingDelete != nil },
                set: { if !$0 { materialPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(GuideAuthoringPresentation.deleteMaterial, role: .destructive) {
                Task {
                    await deleteMaterialFromList()
                }
            }
            Button(GuideAuthoringPresentation.cancelLabel, role: .cancel) {
                materialPendingDelete = nil
            }
        } message: {
            Text(GuideAuthoringPresentation.deleteIrreversibleMessage)
        }
        .alert(
            GuideAuthoringPresentation.deleteFailedTitle,
            isPresented: Binding(
                get: { deleteAlertMessage != nil },
                set: { if !$0 { deleteAlertMessage = nil } }
            ),
            actions: {
                Button(GuideAuthoringPresentation.okLabel, role: .cancel) {
                    deleteAlertMessage = nil
                }
            },
            message: {
                Text(deleteAlertMessage ?? "")
            }
        )
    }

    private var navigationHeader: some View {
        GuideManagementNavigationHeader {
            Menu {
                Button(GuideAuthoringPresentation.editSection) {
                    isPresentingEditEditor = true
                }
                Button(GuideAuthoringPresentation.deleteSection, role: .destructive) {
                    Task {
                        await handleDeleteSectionTapped()
                    }
                }
                .disabled(isDeleting)
            } label: {
                GuideManagementHeaderGlassControl(systemImage: "ellipsis")
            }
            .accessibilityLabel(GuideAuthoringPresentation.actionsTitle)
        }
    }

    private var headerCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                if !pathDescription.isEmpty {
                    Text(pathDescription)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(managedNode.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !managedNode.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(managedNode.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tabPickerCard: some View {
        AppEditorSectionCard {
            Picker(GuideAuthoringPresentation.contentSwitchTitle, selection: $selectedTab) {
                ForEach(GuideManagementTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var tabActionCard: some View {
        AppEditorSectionCard {
            HStack {
                Button(selectedTab.primaryActionTitle) {
                    switch selectedTab {
                    case .sections:
                        isPresentingChildEditor = true
                    case .materials:
                        isPresentingMaterialEditor = true
                    }
                }
                .appActionButtonStyle(.primary)

                Spacer(minLength: 0)
            }
        }
    }

    private var pathDescription: String {
        let titles = viewModel.breadcrumbs.components.map(\.title)
        return titles.joined(separator: " → ")
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
        } else {
            switch selectedTab {
            case .sections:
                sectionsContent
            case .materials:
                materialsContent
            }
        }
    }

    @ViewBuilder
    private var sectionsContent: some View {
        if viewModel.visibleChildNodes.isEmpty {
            EmptyStateCard(
                systemImage: "folder",
                title: GuideAuthoringPresentation.sectionsListTitle,
                message: GuideAuthoringPresentation.noSubsectionsInSection
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing + 4) {
                ForEach(viewModel.visibleChildNodes) { childNode in
                    NavigationLink {
                        GuideTreeSectionManagementView(
                            node: childNode,
                            viewModel: viewModel.makeChildViewModel(),
                            writeRepository: writeRepository,
                            onNodeDeleted: {
                                await viewModel.reload()
                            }
                        )
                    } label: {
                        GuideManagementSectionCardView(node: childNode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var materialsContent: some View {
        if viewModel.visibleMaterials.isEmpty {
            EmptyStateCard(
                systemImage: "doc.text",
                title: GuideAuthoringPresentation.materialsListTitle,
                message: GuideAuthoringPresentation.noMaterialsInSection
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing + 4) {
                ForEach(viewModel.visibleMaterials) { material in
                    NavigationLink {
                        GuideTreeMaterialManagementView(
                            material: material,
                            writeRepository: writeRepository,
                            currentUserID: authState.user?.id
                        ) { _ in
                            await viewModel.reload()
                        } onMaterialDeleted: {
                            await viewModel.reload()
                        }
                    } label: {
                        GuideManagementMaterialCard(material: material)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(GuideAuthoringPresentation.editMaterial) {
                            editingMaterial = material
                        }
                        Button(GuideAuthoringPresentation.deleteMaterial, role: .destructive) {
                            materialPendingDelete = material
                        }
                    }
                }
            }
        }
    }

    private func handleDeleteSectionTapped() async {
        guard !isDeleting else { return }

        do {
            if try await hasNestedContentForDeleteCheck() {
                deleteAlertMessage = GuideAuthoringPresentation.deleteSectionBlockedMessage
            } else {
                isPresentingDeleteConfirmation = true
            }
        } catch let error as AppError {
            deleteAlertMessage = readableDeleteMessage(for: error)
        } catch {
            deleteAlertMessage = GuideAuthoringPresentation.deleteUnknownError
        }
    }

    private func deleteSection() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            if try await hasNestedContentForDeleteCheck() {
                deleteAlertMessage = GuideAuthoringPresentation.deleteSectionBlockedMessage
                return
            }

            try await writeRepository.deleteNode(id: managedNode.id)
            await onNodeDeleted()
            dismiss()
        } catch let error as AppError {
            deleteAlertMessage = readableDeleteMessage(for: error)
        } catch {
            deleteAlertMessage = GuideAuthoringPresentation.deleteUnknownError
        }
    }

    private func hasNestedContentForDeleteCheck() async throws -> Bool {
        let hasChildren = try await writeRepository.hasAnyChildNodes(parentId: managedNode.id)
        if hasChildren {
            return true
        }

        return try await writeRepository.hasAnyMaterials(nodeId: managedNode.id)
    }

    private func deleteMaterialFromList() async {
        guard !isDeleting, let material = materialPendingDelete else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await writeRepository.deleteMaterial(id: material.id)
            materialPendingDelete = nil
            await viewModel.reload()
        } catch let error as AppError {
            deleteAlertMessage = readableDeleteMessage(for: error)
        } catch {
            deleteAlertMessage = GuideAuthoringPresentation.deleteUnknownError
        }
    }
}

struct GuideTreeMaterialManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let material: GuideMaterial
    let writeRepository: GuideWriteRepositoryProtocol
    let currentUserID: String?
    let onMaterialSaved: @MainActor (GuideMaterial) async -> Void
    let onMaterialDeleted: @MainActor () async -> Void
    @State private var managedMaterial: GuideMaterial
    @State private var isPresentingMaterialEditor = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var deleteAlertMessage: String?
    @State private var isDeleting = false
    @State private var isMarkingReviewed = false
    @State private var reviewAlertMessage: String?
    @State private var isShowingReviewSuccess = false

    init(
        material: GuideMaterial,
        writeRepository: GuideWriteRepositoryProtocol,
        currentUserID: String?,
        onMaterialSaved: @escaping @MainActor (GuideMaterial) async -> Void = { _ in },
        onMaterialDeleted: @escaping @MainActor () async -> Void = {}
    ) {
        self.material = material
        self.writeRepository = writeRepository
        self.currentUserID = currentUserID
        self.onMaterialSaved = onMaterialSaved
        self.onMaterialDeleted = onMaterialDeleted
        _managedMaterial = State(initialValue: material)
    }

    var body: some View {
        DetailPageContainer {
            GuideManagementNavigationHeader()
                .padding(.top, AppTheme.dashboardSpacing)

            DetailHeaderCard(title: managedMaterial.title, subtitle: managedMaterial.summary) {
                GuideManagementMetadataRow(items: materialMetadataItems)
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    AppEditorSectionTitle(title: GuideAuthoringPresentation.actionsTitle)

                    VStack(spacing: 0) {
                        Button {
                            isPresentingMaterialEditor = true
                        } label: {
                            AppNavigationRow(
                                title: GuideAuthoringPresentation.editMaterial,
                                systemImage: "pencil",
                                accessory: .none
                            )
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 42)

                        Button {
                            Task {
                                await markAsReviewed()
                            }
                        } label: {
                            AppNavigationRow(
                                title: GuideAuthoringPresentation.markAsReviewed,
                                systemImage: "checkmark.circle",
                                accessory: .none
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isMarkingReviewed)

                        Divider()
                            .padding(.leading, 42)

                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            AppNavigationRow(
                                title: GuideAuthoringPresentation.deleteMaterial,
                                systemImage: "trash",
                                tint: AppTheme.accentDestructive,
                                accessory: .none
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting || isMarkingReviewed)
                    }
                }
            }

            if managedMaterial.contentBlocks.isEmpty {
                DetailCard {
                    Text(managedMaterial.body)
                        .font(AppTheme.detailBodyFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(managedMaterial.contentBlocks) { block in
                    GuideContentBlockView(block: block)
                }
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isPresentingMaterialEditor) {
            NavigationStack {
                GuideMaterialEditorView(
                    viewModel: GuideMaterialEditorViewModel(
                        mode: .edit(material: managedMaterial),
                        repository: writeRepository,
                        currentUserID: currentUserID
                    )
                ) { savedMaterial in
                    managedMaterial = savedMaterial
                    await onMaterialSaved(savedMaterial)
                }
            }
        }
        .confirmationDialog(
            GuideAuthoringPresentation.deleteMaterialTitle,
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(GuideAuthoringPresentation.deleteMaterial, role: .destructive) {
                Task {
                    await deleteMaterial()
                }
            }
            Button(GuideAuthoringPresentation.cancelLabel, role: .cancel) {}
        } message: {
            Text(GuideAuthoringPresentation.deleteIrreversibleMessage)
        }
        .alert(
            GuideAuthoringPresentation.deleteFailedTitle,
            isPresented: Binding(
                get: { deleteAlertMessage != nil },
                set: { if !$0 { deleteAlertMessage = nil } }
            ),
            actions: {
                Button(GuideAuthoringPresentation.okLabel, role: .cancel) {
                    deleteAlertMessage = nil
                }
            },
            message: {
                Text(deleteAlertMessage ?? "")
            }
        )
        .alert(
            GuideAuthoringPresentation.reviewUpdateFailedTitle,
            isPresented: Binding(
                get: { reviewAlertMessage != nil },
                set: { if !$0 { reviewAlertMessage = nil } }
            ),
            actions: {
                Button(GuideAuthoringPresentation.okLabel, role: .cancel) {
                    reviewAlertMessage = nil
                }
            },
            message: {
                Text(reviewAlertMessage ?? "")
            }
        )
        .alert(
            GuideAuthoringPresentation.reviewUpdatedTitle,
            isPresented: $isShowingReviewSuccess
        ) {
            Button(GuideAuthoringPresentation.okLabel, role: .cancel) {}
        } message: {
            Text(GuideAuthoringPresentation.reviewUpdatedMessage)
        }
    }

    private var materialMetadataItems: [GuideMetadataItem] {
        var items: [GuideMetadataItem] = [
            GuideMetadataItem(
                title: managedMaterial.healthStatus.displayTitle,
                systemImage: managedMaterial.healthStatus.displaySystemImage,
                tint: managedMaterial.healthStatus.displayTint,
                fill: managedMaterial.healthStatus.displayFill
            )
        ]

        if let federalState = managedMaterial.federalState {
            items.append(
                GuideMetadataItem(
                    title: AppStrings.FederalStates.title(for: federalState),
                    systemImage: "mappin.and.ellipse",
                    tint: AppTheme.textSecondary,
                    fill: AppTheme.surfaceGlass
                )
            )
        }

        return items
    }

    private func deleteMaterial() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await writeRepository.deleteMaterial(id: managedMaterial.id)
            await onMaterialDeleted()
            dismiss()
        } catch let error as AppError {
            deleteAlertMessage = readableDeleteMessage(for: error)
        } catch {
            deleteAlertMessage = GuideAuthoringPresentation.deleteUnknownError
        }
    }

    private func markAsReviewed() async {
        guard !isMarkingReviewed else { return }
        isMarkingReviewed = true
        defer { isMarkingReviewed = false }

        let reviewedAt = Date()
        let nextReviewAt = Calendar.current.date(
            byAdding: .month,
            value: managedMaterial.reviewInterval.months,
            to: reviewedAt
        ) ?? reviewedAt

        do {
            try await writeRepository.markMaterialReviewed(
                id: managedMaterial.id,
                reviewedAt: reviewedAt,
                nextReviewAt: nextReviewAt,
                reviewedBy: currentUserID
            )

            let updatedMaterial = GuideMaterial(
                id: managedMaterial.id,
                title: managedMaterial.title,
                summary: managedMaterial.summary,
                body: managedMaterial.body,
                sortOrder: managedMaterial.sortOrder,
                contentBlocks: managedMaterial.contentBlocks,
                sourceLinks: managedMaterial.sourceLinks,
                officialSourceURL: managedMaterial.officialSourceURL,
                sourceName: managedMaterial.sourceName,
                officialSourcesRequired: managedMaterial.officialSourcesRequired,
                kind: managedMaterial.kind,
                category: managedMaterial.category,
                nodeID: managedMaterial.nodeID,
                nodePath: managedMaterial.nodePath,
                regionScope: managedMaterial.regionScope,
                federalState: managedMaterial.federalState,
                reviewInterval: managedMaterial.reviewInterval,
                lastReviewedAt: reviewedAt,
                nextReviewAt: nextReviewAt,
                reviewedBy: currentUserID,
                moderationStatus: managedMaterial.moderationStatus,
                publishedAt: managedMaterial.publishedAt,
                createdAt: managedMaterial.createdAt,
                updatedAt: reviewedAt,
                createdBy: managedMaterial.createdBy,
                updatedBy: currentUserID,
                archivedAt: managedMaterial.archivedAt
            )

            managedMaterial = updatedMaterial
            await onMaterialSaved(updatedMaterial)
            isShowingReviewSuccess = true
        } catch let error as AppError {
            reviewAlertMessage = GuideAuthoringPresentation.reviewUpdateErrorMessage(for: error)
        } catch {
            reviewAlertMessage = GuideAuthoringPresentation.reviewUpdateErrorMessage(for: .unknown)
        }
    }
}

enum GuideManagementTab: String, CaseIterable, Identifiable {
    case sections
    case materials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sections:
            return GuideAuthoringPresentation.sectionsListTitle
        case .materials:
            return GuideAuthoringPresentation.materialsListTitle
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .sections:
            return GuideAuthoringPresentation.createSubsection
        case .materials:
            return GuideAuthoringPresentation.createMaterial
        }
    }
}

struct GuideMetadataItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let fill: Color
}

struct GuideManagementMetadataRow: View {
    let items: [GuideMetadataItem]

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        AppInfoChip(
                            title: item.title,
                            systemImage: item.systemImage,
                            tint: item.tint,
                            fill: item.fill,
                            size: .small
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
