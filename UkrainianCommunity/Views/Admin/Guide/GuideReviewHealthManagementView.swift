import Combine
import SwiftUI

struct GuideReviewHealthManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: GuideReviewHealthManagementViewModel
    private let writeRepository: GuideWriteRepositoryProtocol

    init(
        repository: GuideRepositoryProtocol = FirestoreGuideRepository(),
        writeRepository: GuideWriteRepositoryProtocol = FirestoreGuideWriteRepository()
    ) {
        _viewModel = StateObject(
            wrappedValue: GuideReviewHealthManagementViewModel(repository: repository)
        )
        self.writeRepository = writeRepository
    }

    var body: some View {
        DetailPageContainer {
            GuideManagementNavigationHeader(
                title: GuideAuthoringPresentation.reviewQueueTitle,
                subtitle: GuideAuthoringPresentation.reviewQueueSubtitle
            )
                .padding(.top, AppTheme.dashboardSpacing)

            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.materials.isEmpty {
            GuideLoadingView()
        } else if let error = viewModel.error, viewModel.materials.isEmpty {
            GuideErrorStateView(error: error) {
                Task {
                    await viewModel.refresh()
                }
            }
        } else if viewModel.materialsNeedingReview.isEmpty {
            EmptyStateCard(
                systemImage: "checkmark.circle",
                title: GuideAuthoringPresentation.reviewQueueEmptyTitle,
                message: GuideAuthoringPresentation.reviewQueueEmptyMessage
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                if !viewModel.overdueMaterials.isEmpty {
                    reviewSection(
                        title: GuideAuthoringPresentation.overdueTitle,
                        materials: viewModel.overdueMaterials
                    )
                }

                if !viewModel.dueSoonMaterials.isEmpty {
                    reviewSection(
                        title: GuideAuthoringPresentation.dueSoonTitle,
                        materials: viewModel.dueSoonMaterials
                    )
                }
            }
        }
    }

    private func reviewSection(title: String, materials: [GuideMaterial]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            SectionHeaderBlock(title: title)

            ForEach(materials) { material in
                NavigationLink {
                    GuideTreeMaterialManagementView(
                        material: material,
                        writeRepository: writeRepository,
                        currentUserID: authState.user?.id,
                        onMaterialSaved: { updatedMaterial in
                            await viewModel.replaceMaterial(updatedMaterial)
                        }
                    )
                } label: {
                    GuideReviewMaterialCard(material: material)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

@MainActor
private final class GuideReviewHealthManagementViewModel: ObservableObject {
    @Published private(set) var materials: [GuideMaterial] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: GuideRepositoryProtocol
    private var hasLoaded = false

    init(repository: GuideRepositoryProtocol) {
        self.repository = repository
    }

    var materialsNeedingReview: [GuideMaterial] {
        materials.filter {
            let status = $0.healthStatus
            return status == .dueSoon || status == .overdue
        }
    }

    var overdueMaterials: [GuideMaterial] {
        materialsNeedingReview.filter { $0.healthStatus == .overdue }
    }

    var dueSoonMaterials: [GuideMaterial] {
        materialsNeedingReview.filter { $0.healthStatus == .dueSoon }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            materials = try await repository.fetchMaterialsNeedingReview()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func replaceMaterial(_ material: GuideMaterial) async {
        if material.healthStatus == .dueSoon || material.healthStatus == .overdue {
            if let index = materials.firstIndex(where: { $0.id == material.id }) {
                materials[index] = material
            } else {
                materials.append(material)
            }
        } else {
            materials.removeAll { $0.id == material.id }
        }
    }
}

private struct GuideReviewMaterialCard: View {
    let material: GuideMaterial

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                            .fill(material.healthStatus.displayFill)

                        Image(systemName: material.healthStatus.displaySystemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(material.healthStatus.displayTint)
                    }
                    .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !material.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(material.summary)
                                .font(AppTheme.secondaryBodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                }

                HStack(spacing: 8) {
                    AppInfoChip(
                        title: statusTitle,
                        systemImage: material.healthStatus.displaySystemImage,
                        tint: material.healthStatus.displayTint,
                        fill: material.healthStatus.displayFill,
                        size: .small
                    )

                    if let nextReviewAt = material.nextReviewAt {
                        AppInfoChip(
                            title: "\(GuideAuthoringPresentation.nextReviewLabel): \(LocalizationStore.dateString(from: nextReviewAt, dateStyle: .medium, timeStyle: .none))",
                            systemImage: "calendar",
                            tint: AppTheme.textSecondary,
                            fill: AppTheme.surfaceGlass,
                            size: .small
                        )
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        switch material.healthStatus {
        case .current:
            return GuideAuthoringPresentation.localized(uk: "Актуально", de: "Aktuell", en: "Current")
        case .dueSoon:
            return GuideAuthoringPresentation.dueSoonTitle
        case .overdue:
            return GuideAuthoringPresentation.overdueTitle
        case .archived:
            return GuideAuthoringPresentation.localized(uk: "Архів", de: "Archiv", en: "Archived")
        }
    }
}
