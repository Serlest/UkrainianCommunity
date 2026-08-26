import SwiftUI

struct ContentCommentsSection<Composer: View, Row: View>: View {
    let comments: [Comment]
    let loadState: CommentLoadState
    let retry: () async -> Void
    @ViewBuilder let composer: () -> Composer
    @ViewBuilder let row: (Comment) -> Row

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppStrings.Common.comments)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("comments.section")
                composer()
                switch loadState {
                case .loading:
                    ProgressView(AppStrings.Comments.loading)
                        .font(.footnote)
                        .accessibilityIdentifier("comments.loading")
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Comments.loadFailed)
                            .font(.subheadline.weight(.semibold))
                        Text(CommentErrorMapper.message(error)).font(.footnote)
                            .accessibilityIdentifier("comments.loadError")
                        Button(AppStrings.Action.retry) { Task { await retry() } }
                            .frame(minHeight: AppTheme.minimumInteractiveTarget)
                            .accessibilityIdentifier("comments.retry")
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                case .loaded:
                    if comments.isEmpty {
                        Text(AppStrings.Common.noCommentsYet)
                            .font(AppTheme.secondaryBodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("comments.empty")
                    }
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { comment in
                        if comment.id != comments.first?.id { Divider() }
                        row(comment)
                    }
                }
            }
        }
    }
}

struct ContentCommentComposer: View {
    let accountID: String?
    let canComment: Bool
    let isPending: Bool
    let focus: FocusState<Bool>.Binding
    let signIn: () -> Void
    let send: (String) async -> CommentMutationResult
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var state = CommentComposerState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accountID == nil {
                Button(action: signIn) {
                    Label(AppStrings.Common.signInToComment, systemImage: "person.crop.circle.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("comments.signIn")
            } else if !canComment {
                Text(AppStrings.Comments.permissionError)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppStrings.Common.commentInputPlaceholder, text: $state.text, axis: .vertical)
                        .focused(focus)
                        .lineLimit(1...5)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.glassBorder(for: colorScheme)))
                        .accessibilityIdentifier("comments.input")
                    Button {
                        Task {
                            if await state.submit(send) { focus.wrappedValue = false }
                        }
                    } label: {
                        Group {
                            if state.isSending || isPending {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill").font(.subheadline.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                        .background(AppTheme.accentPrimary, in: Circle())
                    }
                    .disabled(!state.canSend || isPending)
                    .opacity(state.canSend && !isPending ? 1 : 0.55)
                    .accessibilityLabel(state.isSending ? AppStrings.Comments.sending : AppStrings.Action.send)
                    .accessibilityIdentifier("comments.send")
                }
                HStack(alignment: .firstTextBaseline) {
                    if focus.wrappedValue {
                        Button(AppStrings.Common.done) { focus.wrappedValue = false }
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: AppTheme.minimumInteractiveTarget)
                            .accessibilityIdentifier("comments.dismissKeyboard")
                    }
                    Spacer(minLength: 8)
                    Text("\(CommentTextPolicy.length(state.text))/\(CommentTextPolicy.maximumLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CommentTextPolicy.length(state.text) > CommentTextPolicy.maximumLength
                            ? AppTheme.accentWarningForeground : AppTheme.textSecondary)
                        .accessibilityIdentifier("comments.length")
                }
                if CommentTextPolicy.length(state.text) > CommentTextPolicy.maximumLength {
                    Text(AppStrings.Comments.lengthError).font(.footnote)
                        .foregroundStyle(AppTheme.accentWarningForeground)
                }
                if let error = state.error {
                    Text(CommentErrorMapper.message(error)).font(.footnote)
                        .foregroundStyle(AppTheme.accentWarningForeground)
                        .accessibilityIdentifier("comments.sendError")
                }
            }
        }
        .onChange(of: accountID) { _, _ in
            state.reset()
            focus.wrappedValue = false
        }
    }
}

struct ContentCommentRow<Actions: View>: View {
    let comment: Comment
    @ViewBuilder let actions: () -> Actions

    private var authorName: String {
        let name = comment.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? AppStrings.Organizations.userFallback : name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarArtworkView(
                avatarURL: comment.authorPhotoURL.flatMap(URL.init(string:)),
                initials: String(authorName.prefix(1)).uppercased(), size: 32,
                showsBorder: false, shadowOpacity: 0, shadowRadius: 0, shadowY: 0,
                initialsFont: .caption.weight(.bold), placeholderFill: AppTheme.accentPrimarySoft
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authorName).font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    actions()
                }
                Text(comment.text)
                    .accessibilityIdentifier("comments.row.\(comment.id)")
                    .font(AppTheme.secondaryBodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
