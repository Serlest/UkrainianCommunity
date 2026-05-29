import SwiftUI

extension OrganizationDetailView {
    @ViewBuilder
    func commentsSection(for organization: Organization) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Common.comments)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.accentPrimary)

                commentComposer(parentID: organization.id)

                let comments = viewModel.comments(for: organization.id)
                if comments.isEmpty {
                    Text(AppStrings.Common.noCommentsYet)
                        .font(AppTheme.secondaryBodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                            commentRow(comment, organization: organization)

                            if index < comments.count - 1 {
                                Divider()
                                    .padding(.vertical, AppTheme.eventsControlGroupSpacing)
                            }
                        }
                    }
                }
            }
        }
    }

    func commentComposer(parentID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if authState.isAuthenticated {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppStrings.Common.commentInputPlaceholder, text: $commentText, axis: .vertical)
                        .focused($isCommentFieldFocused)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                        )

                    Button {
                        submitComment(parentID: parentID)
                    } label: {
                        Image(systemName: editingCommentID == nil ? "paperplane.fill" : "checkmark")
                            .font(AppTheme.buttonLabelFont)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentPrimary, in: Circle())
                    }
                    .disabled(trimmedCommentText.isEmpty || viewModel.pendingOrganizationCommentIDs.contains(parentID))
                    .opacity(trimmedCommentText.isEmpty ? 0.55 : 1)
                }

                Text("\(commentText.count)/1000")
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Button {
                    guestAccessAction = .comments
                } label: {
                    Label(AppStrings.Common.signInToComment, systemImage: "person.crop.circle.badge.plus")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func commentRow(_ comment: Comment, organization: Organization) -> some View {
        HStack(alignment: .top, spacing: 10) {
            commentAvatar(comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Text(sanitizedAuthorName(comment.authorName))
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if canEditComment(comment) || canDeleteComment(comment, organization: organization) {
                        commentActionMenu(for: comment)
                    }
                }

                Text(comment.text)
                    .font(AppTheme.cardSubtitleFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func commentActionMenu(for comment: Comment) -> some View {
        Menu {
            if canEditComment(comment) {
                Button(AppStrings.Action.edit, systemImage: "pencil") {
                    editingCommentID = comment.id
                    commentText = comment.text
                    isCommentFieldFocused = true
                }
            }
            Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                pendingCommentDeleteID = comment.id
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(AppTheme.sectionTitleFont)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Action.delete)
    }

    var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func submitComment(parentID: String) {
        guard let user = authState.user else {
            guestAccessAction = .comments
            return
        }
        let text = String(trimmedCommentText.prefix(1000))
        guard !text.isEmpty else { return }
        let editingID = editingCommentID
        Task {
            if let editingID {
                await viewModel.updateComment(organizationID: parentID, commentID: editingID, text: text)
            } else {
                await viewModel.addComment(to: parentID, text: text, author: user)
            }
            await MainActor.run {
                commentText = ""
                editingCommentID = nil
                isCommentFieldFocused = false
            }
        }
    }

    @MainActor
    func deleteComment(commentID: String) async {
        await viewModel.deleteComment(organizationID: organizationID, commentID: commentID)
        pendingCommentDeleteID = nil
    }

    func commentAvatar(_ comment: Comment) -> some View {
        let avatarURL = comment.authorPhotoURL.flatMap { URL(string: $0) }
        return AvatarArtworkView(
            avatarURL: avatarURL,
            initials: commentInitials(comment),
            size: 32,
            showsBorder: false,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            initialsFont: .caption.weight(.bold),
            placeholderFill: AppTheme.accentPrimarySoft
        )
    }

    func commentInitials(_ comment: Comment) -> String {
        let name = sanitizedAuthorName(comment.authorName)
        return String(name.prefix(1)).uppercased()
    }

    func sanitizedAuthorName(_ authorName: String) -> String {
        let trimmed = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.Organizations.userFallback : trimmed
    }

    func canEditComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        return comment.authorId == user.id
    }

    func canDeleteComment(_ comment: Comment, organization: Organization) -> Bool {
        guard let user = authState.user else { return false }
        if comment.authorId == user.id {
            return true
        }
        return PermissionService.canModerateOrganizationContent(organization, user: user)
    }
}
