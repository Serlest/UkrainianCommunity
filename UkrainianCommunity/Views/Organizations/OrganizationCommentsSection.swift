import SwiftUI

extension OrganizationDetailView {
    @ViewBuilder
    func commentsSection(for organization: Organization) -> some View {
        ContentCommentsSection(
            comments: viewModel.comments(for: organization.id),
            loadState: viewModel.commentLoadStates[organization.id] ?? .loading,
            retry: { await viewModel.loadComments(for: organization.id, forceRefresh: true) },
            composer: { commentComposer(parentID: organization.id) },
            row: { comment in commentRow(comment, organization: organization) }
        )
    }

    func commentComposer(parentID: String) -> some View {
        let author = authState.user
        return ContentCommentComposer(
            accountID: authState.isAuthenticated ? authState.user?.id : nil,
            canComment: PermissionService.isUsableAccount(user: authState.user),
            isPending: viewModel.pendingOrganizationCommentIDs.contains(parentID),
            focus: $isCommentFieldFocused,
            signIn: { guestAccessAction = .comments },
            send: { text in
                guard let user = author, authState.user?.id == user.id else { return .failure(.permissionDenied) }
                return await viewModel.addComment(to: parentID, text: text, author: user)
            }
        )
        .id(parentID)
    }

    func commentRow(_ comment: Comment, organization: Organization) -> some View {
        ContentCommentRow(comment: comment) {
            if canDeleteComment(comment, organization: organization) || canReportComment(comment) || canBlockComment(comment) {
                commentActionMenu(for: comment, organization: organization)
            }
        }
    }

    func commentActionMenu(for comment: Comment, organization: Organization) -> some View {
        Menu {
            if canDeleteComment(comment, organization: organization) {
                Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                    pendingCommentDeleteID = comment.id
                }
            }
            if canReportComment(comment),
               let target = ContentReportTarget.comment(comment, parentTitle: organization.name, parentType: .organization, parentId: organization.id) {
                Button(AppStrings.Safety.reportAction, systemImage: "exclamationmark.bubble") {
                    presentContentReport(target)
                }
            }
            if canBlockComment(comment), let target = UserBlockTarget.comment(comment) {
                Button(AppStrings.Safety.blockAction, systemImage: "person.slash", role: .destructive) {
                    userBlockingPresentation.present(target)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(AppTheme.sectionTitleFont)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(
                    width: AppTheme.minimumInteractiveTarget,
                    height: AppTheme.minimumInteractiveTarget
                )
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Safety.moreActions)
    }

    func canReportComment(_ comment: Comment) -> Bool {
        !authState.isAuthenticated || comment.authorId != authState.user?.id
    }

    func canBlockComment(_ comment: Comment) -> Bool {
        authState.isAuthenticated && comment.authorId != nil && comment.authorId != authState.user?.id
    }

    @MainActor
    func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        if case .failure(let error) = await viewModel.deleteComment(organizationID: organizationID, commentID: commentID) {
            commentDeleteErrorMessage = readableOrganizationErrorText(error)
        }
    }

    func sanitizedAuthorName(_ authorName: String) -> String {
        let trimmed = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.Organizations.userFallback : trimmed
    }

    func canDeleteComment(_ comment: Comment, organization: Organization) -> Bool {
        guard let user = authState.user else { return false }
        return PermissionService.canModerateOrganizationComments(organization, user: user)
    }
}
