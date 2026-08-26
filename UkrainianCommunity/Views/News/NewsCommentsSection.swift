import SwiftUI

extension NewsDetailView {
        func commentsSection(for post: NewsPost) -> some View {
            ContentCommentsSection(
                comments: post.comments,
                loadState: viewModel.commentLoadStates[post.id] ?? .loading,
                retry: { await viewModel.loadComments(for: post.id, forceRefresh: true) },
                composer: { commentComposer(parentID: post.id) },
                row: { comment in commentRow(comment, parentTitle: post.localizedTitle) }
            )
        }

        func commentRow(_ comment: Comment, parentTitle: String) -> some View {
            ContentCommentRow(comment: comment) {
                if canDeleteComment(comment) || canReportComment(comment) || canBlockComment(comment) {
                    commentActionMenu(for: comment, parentTitle: parentTitle)
                }
            }
        }

        func commentActionMenu(for comment: Comment, parentTitle: String) -> some View {
            Menu {
                if canDeleteComment(comment) {
                    Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                        pendingCommentDeleteID = comment.id
                    }
                }
                if canReportComment(comment),
                   let target = ContentReportTarget.comment(comment, parentTitle: parentTitle, parentType: .news, parentId: postID) {
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
                    .font(.title3.weight(.semibold))
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

        func commentComposer(parentID: String) -> some View {
            let author = authState.user
            return ContentCommentComposer(
                accountID: authState.isAuthenticated ? authState.user?.id : nil,
                canComment: PermissionService.isUsableAccount(user: authState.user),
                isPending: viewModel.pendingNewsCommentIDs.contains(parentID),
                focus: $isCommentFieldFocused,
                signIn: { guestAccessAction = .comments },
                send: { text in
                    guard let user = author, authState.user?.id == user.id else { return .failure(.permissionDenied) }
                    return await viewModel.addComment(to: parentID, text: text, author: user)
                }
            )
            .id(parentID)
        }

        var newsViewTaskID: String {
            "\(postID)-\(authState.user?.id ?? "guest")"
        }

        func canDeleteComment(_ comment: Comment) -> Bool {
            guard let user = authState.user else { return false }
            if PermissionService.canModerate(section: .comments, user: user) || PermissionService.canModerate(section: .news, user: user) {
                return true
            }
            guard let post = viewModel.post(for: postID), let organizationId = post.source.organizationId else {
                return false
            }
            if let organization = organizationForPermissions(organizationID: organizationId) {
                return PermissionService.canModerateOrganizationContent(organization, user: user)
            }
            return false
        }
}
