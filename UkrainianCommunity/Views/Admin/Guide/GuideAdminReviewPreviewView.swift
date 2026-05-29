import SwiftUI

struct GuideAdminReviewPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let article: GuideArticle
    let repository: GuideRepository

    @State private var approveConfirmationIsPresented = false
    @State private var isApproving = false
    @State private var approveErrorMessage: String?
    @State private var publishConfirmationIsPresented = false
    @State private var isPublishing = false
    @State private var publishErrorMessage: String?

    private var contentBlocks: [GuideContentBlock] {
        article.contentBlocks ?? []
    }

    var body: some View {
        DetailPageContainer {
            DetailHeaderCard(title: article.title, subtitle: article.summary) {
                metadataPills
            }

            reviewMetadataCard
            approveActionCard
            publishActionCard

            if contentBlocks.isEmpty {
                DetailCard {
                    Text(article.body)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(contentBlocks) { block in
                    GuideContentBlockView(block: block)
                }
            }

            GuideSourceLinksView(
                links: article.sourceLinks ?? [],
                legacyURL: article.officialSourceURL
            )
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            AppStrings.GuideManagement.approveConfirmationTitle,
            isPresented: $approveConfirmationIsPresented
        ) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.GuideManagement.approveAction) {
                approve()
            }
        } message: {
            Text(AppStrings.GuideManagement.approveConfirmationMessage)
        }
        .alert(
            AppStrings.GuideManagement.publishConfirmationTitle,
            isPresented: $publishConfirmationIsPresented
        ) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.GuideManagement.publishAction) {
                publish()
            }
        } message: {
            Text(AppStrings.GuideManagement.publishConfirmationMessage)
        }
    }

    private var metadataPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metadataPillContent
            }

            VStack(alignment: .leading, spacing: 8) {
                metadataPillContent
            }
        }
    }

    private var metadataPillContent: some View {
        Group {
            ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)
            ContentMetadataPill(systemImage: "clock.badge.exclamationmark", text: article.moderationStatus.title)
            ContentMetadataPill(systemImage: "tag", text: statusText)

            if let sourceName = article.sourceName, !sourceName.isEmpty {
                ContentMetadataPill(systemImage: "link", text: sourceName)
            }
        }
    }

    private var reviewMetadataCard: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Text(AppStrings.GuideManagement.reviewMetadataTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                metadataRow(title: AppStrings.GuideManagement.submittedAtLabel, value: formattedDate(article.updatedAt))

                if let updatedBy = article.updatedBy, !updatedBy.isEmpty {
                    metadataRow(title: AppStrings.GuideManagement.submittedByLabel, value: updatedBy)
                }

                if let reviewedBy = article.reviewedBy, !reviewedBy.isEmpty {
                    metadataRow(title: AppStrings.GuideManagement.reviewedByLabel, value: reviewedBy)
                }

                if let lastReviewedAt = article.lastReviewedAt {
                    metadataRow(title: AppStrings.GuideManagement.lastReviewedAtLabel, value: formattedDate(lastReviewedAt))
                }

                if let nextReviewAt = article.nextReviewAt {
                    metadataRow(title: AppStrings.GuideManagement.nextReviewAtLabel, value: formattedDate(nextReviewAt))
                }

                if let reviewInterval = article.reviewInterval {
                    metadataRow(title: AppStrings.GuideManagement.reviewIntervalLabel, value: reviewIntervalText(reviewInterval))
                }
            }
        }
    }

    @ViewBuilder
    private var approveActionCard: some View {
        if article.moderationStatus == .pendingReview,
           article.status == .review,
           PermissionService.canApproveGuideArticle(user: authState.user) {
            DetailCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Button {
                        approveErrorMessage = nil
                        approveConfirmationIsPresented = true
                    } label: {
                        Label(
                            isApproving ? AppStrings.GuideManagement.approving : AppStrings.GuideManagement.approveAction,
                            systemImage: isApproving ? "clock" : "checkmark.seal"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApproving)

                    if let approveErrorMessage {
                        Text(approveErrorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.accentDestructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var publishActionCard: some View {
        if article.moderationStatus == .approved,
           article.status == .approved,
           PermissionService.canApproveGuideArticle(user: authState.user) {
            DetailCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Button {
                        publishErrorMessage = nil
                        publishConfirmationIsPresented = true
                    } label: {
                        Label(
                            isPublishing ? AppStrings.GuideManagement.publishing : AppStrings.GuideManagement.publishAction,
                            systemImage: isPublishing ? "clock" : "paperplane"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPublishing)

                    if let publishErrorMessage {
                        Text(publishErrorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.accentDestructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        if article.moderationStatus == .approved, article.status == .approved {
            return AppStrings.GuideManagement.approved
        }

        return AppStrings.GuideManagement.inReview
    }

    private var statusText: String {
        switch article.status {
        case .draft:
            return AppStrings.Common.draft
        case .review:
            return AppStrings.Common.pendingReview
        case .approved:
            return AppStrings.Common.approved
        case .published:
            return AppStrings.GuideManagement.published
        case .needsReview:
            return AppStrings.Common.needsRevision
        case .archived:
            return AppStrings.Common.archived
        case nil:
            return AppStrings.Common.draft
        }
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func approve() {
        guard !isApproving else { return }
        guard let currentUserId = authState.user?.id,
              PermissionService.canApproveGuideArticle(user: authState.user) else {
            approveErrorMessage = AppStrings.GuideManagement.approvePermissionError
            return
        }

        isApproving = true
        approveErrorMessage = nil

        Task {
            do {
                try await repository.approveGuideArticle(id: article.id, reviewerId: currentUserId)
                AppContentChangeBus.postGuideChanged()
                dismiss()
            } catch let appError as AppError {
                approveErrorMessage = approveErrorMessage(for: appError)
                isApproving = false
            } catch {
                approveErrorMessage = AppStrings.GuideManagement.approveFailed
                isApproving = false
            }
        }
    }

    private func approveErrorMessage(for error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.GuideEditor.saveNetworkError
        case .permissionDenied:
            return AppStrings.GuideManagement.approvePermissionError
        case .validationFailed:
            return AppStrings.GuideManagement.approveValidationError
        case .notFound:
            return AppStrings.GuideManagement.approveNotFoundError
        case .unknown:
            return AppStrings.GuideManagement.approveFailed
        }
    }

    private func publish() {
        guard !isPublishing else { return }
        guard let currentUserId = authState.user?.id,
              PermissionService.canApproveGuideArticle(user: authState.user) else {
            publishErrorMessage = AppStrings.GuideManagement.publishPermissionError
            return
        }

        isPublishing = true
        publishErrorMessage = nil

        Task {
            do {
                try await repository.publishGuideArticle(id: article.id, publisherId: currentUserId)
                AppContentChangeBus.postGuideChanged()
                dismiss()
            } catch let appError as AppError {
                publishErrorMessage = publishErrorMessage(for: appError)
                isPublishing = false
            } catch {
                publishErrorMessage = AppStrings.GuideManagement.publishFailed
                isPublishing = false
            }
        }
    }

    private func publishErrorMessage(for error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.GuideEditor.saveNetworkError
        case .permissionDenied:
            return AppStrings.GuideManagement.publishPermissionError
        case .validationFailed:
            return AppStrings.GuideManagement.publishValidationError
        case .notFound:
            return AppStrings.GuideManagement.publishNotFoundError
        case .unknown:
            return AppStrings.GuideManagement.publishFailed
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func reviewIntervalText(_ interval: ReviewInterval) -> String {
        switch interval {
        case .critical:
            return AppStrings.GuideManagement.reviewIntervalCritical
        case .normal:
            return AppStrings.GuideManagement.reviewIntervalNormal
        case .stable:
            return AppStrings.GuideManagement.reviewIntervalStable
        }
    }
}
