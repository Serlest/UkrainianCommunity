import SwiftUI

extension NewsDetailView {
        func newsDetailHeader() -> some View {
            AppCenteredBrandHeader {
                detailIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                    navigateBack()
                }
            } trailingContent: {
                headerActions()
            }
            .zIndex(10)
        }

        func navigateBack() {
            if let onNavigateBack {
                onNavigateBack()
            } else {
                dismiss()
            }
        }

        func headerActions() -> some View {
            HStack(spacing: 10) {
                if let post = viewModel.post(for: postID) {
                    detailIconButton(
                        systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark",
                        accessibilityLabel: AppStrings.Action.save
                    ) {
                        handleBookmark(for: post.id)
                    }
                }

                detailIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: AppStrings.Action.share) {
                    guard let post = viewModel.post(for: postID) else { return }
                    sharePayload = NewsSharePayload(post: post)
                }
            }
        }

        func detailIconButton(
            systemImage: String,
            accessibilityLabel: String,
            role: ButtonRole? = nil,
            isPlaceholder: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            AppGlassIconButton(
                systemImage: systemImage,
                accessibilityLabel: accessibilityLabel,
                role: role,
                isPlaceholder: isPlaceholder
            ) {
                action()
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .zIndex(2)
        }

        func articleHeader(for post: NewsPost) -> some View {
            DetailHeaderCard(title: post.title, subtitle: nil) {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    newsBadge
                    metadataRow(for: post)
                }
            }
            .accessibilityElement(children: .contain)
        }

        var newsBadge: some View {
            ContentMetadataPill(systemImage: "newspaper", text: AppStrings.News.detailBadge.uppercased())
        }

        func metadataRow(for post: NewsPost) -> some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    metadataItems(for: post)
                }

                VStack(alignment: .leading, spacing: 7) {
                    metadataItems(for: post)
                }
            }
        }

        func metadataItems(for post: NewsPost) -> some View {
            Group {
                AppMetadataLine(title: newsDateText(for: post), systemImage: "calendar")
                AppMetadataLine(title: newsTimeText(for: post), systemImage: "clock")
                AppMetadataLine(title: viewCountText(for: post), systemImage: "eye")
            }
        }

        @ViewBuilder
        func heroImage(for post: NewsPost) -> some View {
            if let imageURL = sanitizedImageURL(post.imageURL) {
                RemoteImageView(
                    imageURL: imageURL,
                    height: detailImageHeight,
                    cornerRadius: AppTheme.imageRadius,
                    source: "NewsDetailView",
                    placeholderStyle: .glassSkeleton
                )
                .frame(maxWidth: .infinity, minHeight: detailImageHeight, maxHeight: detailImageHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.78))
                )
                .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.55), radius: 8, y: 4)
            }
        }

        func leadBlock(for post: NewsPost) -> some View {
            DetailCard {
                HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "info.circle")
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.News.summarySectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(post.subtitle)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        func articleBody(for post: NewsPost) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.News.bodySectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)

                    Text(post.body)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        func articleSourceSection(for post: NewsPost) -> some View {
            if let source = articleSourceDisplay(for: post) {
                DetailCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.News.sourceSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimary)

                        if let url = source.url {
                            Link(destination: url) {
                                Label(source.title, systemImage: "link")
                                    .font(AppTheme.metadataStrongFont)
                                    .foregroundStyle(AppTheme.accentPrimary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Label(source.title, systemImage: "doc.text")
                                .font(AppTheme.cardSubtitleFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        func articleSourceDisplay(for post: NewsPost) -> (title: String, url: URL?)? {
            let name = trimmedNonEmpty(post.sourceName)
            let urlString = trimmedNonEmpty(post.sourceURL)
            let url = urlString.flatMap(URL.init(string:))

            if let url {
                return (name ?? url.absoluteString, url)
            }

            if let name {
                return (name, nil)
            }

            return nil
        }

        func trimmedNonEmpty(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        @ViewBuilder
        func tagsSection(for post: NewsPost) -> some View {
            if !post.tags.isEmpty {
                DetailCard {
                    Text(AppStrings.News.tagsSectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)

                    AppHorizontalChipRow {
                        ForEach(post.tags, id: \.self) { tag in
                            Text(tag)
                                .font(AppTheme.metadataStrongFont)
                                .foregroundStyle(AppTheme.accentPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.accentPrimarySoft, in: Capsule())
                        }
                    }
                }
            }
        }

        func actionsCard(for post: NewsPost) -> some View {
            detailGlassCard(padding: 9) {
                DetailActionRow {
                    HStack(spacing: 12) {
                        detailMetricButton(
                            systemImage: post.likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                            count: post.likeCount,
                            accessibilityLabel: post.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like,
                            isSelected: post.likeState.isLiked
                        ) {
                            handleLike(for: post.id)
                        }
                        .disabled(viewModel.pendingNewsLikeIDs.contains(post.id))
                        .accessibilityIdentifier("news.like.\(post.id)")
                        .accessibilityHint(AppStrings.Common.likes)

                        detailMetricButton(
                            systemImage: "bubble.left",
                            count: post.commentCount,
                            accessibilityLabel: AppStrings.Common.comments
                        ) {
                            isCommentFieldFocused = true
                        }
                    }
                } trailingContent: {
                    publisherLine(for: post)
                }
            }
        }

        @ViewBuilder
        func managementCard(for post: NewsPost) -> some View {
            if canEditNews || canDeleteNews {
                detailGlassCard(padding: 9) {
                    HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                        if canEditNews {
                            managementActionButton(systemImage: "pencil", title: AppStrings.Action.edit) {
                                isShowingEditSheet = true
                            }
                            .accessibilityHint(AppStrings.News.detailTitle)
                        }

                        if canDeleteNews {
                            managementActionButton(systemImage: "trash", title: AppStrings.Action.delete, role: .destructive) {
                                showDeleteConfirmation = true
                            }
                            .disabled(isDeleting)
                            .accessibilityHint(AppStrings.News.detailTitle)
                        }
                    }
                }
            }
        }

        func managementActionButton(
            systemImage: String,
            title: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.metadataStrongFont)
                    .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }

        func detailMetricButton(
            systemImage: String,
            count: Int,
            accessibilityLabel: String,
            isSelected: Bool = false,
            isPlaceholder: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(AppTheme.buttonLabelFont)
                        .foregroundStyle(isSelected ? AppTheme.accentDestructive : AppTheme.accentPrimary)

                    Text("\(count)")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                }
                .frame(minWidth: 74, minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPlaceholder)
            .opacity(isPlaceholder ? 0.72 : 1)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(count)")
            .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
        }

        func publisherLine(for post: NewsPost) -> some View {
            Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
                .font(AppTheme.metadataFont)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 190, alignment: .trailing)
                .accessibilityLabel(newsPublisherText(for: post))
        }

        @ViewBuilder
        func relatedSection(for post: NewsPost) -> some View {
            let relatedPosts = relatedNewsPosts(for: post)
            if !relatedPosts.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        Text(AppStrings.News.relatedSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimary)

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(relatedPosts) { relatedPost in
                                NavigationLink {
                                    NewsDetailView(
                                        viewModel: viewModel,
                                        postID: relatedPost.id,
                                        onNewsDeleted: onNewsDeleted
                                    )
                                    .environment(\.newsPresentationMode, presentationMode)
                                } label: {
                                    relatedNewsCard(relatedPost)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("news.related.\(relatedPost.id)")
                            }
                        }
                    }
                }
            }
        }

        func relatedNewsCard(_ post: NewsPost) -> some View {
            SoftContentCard(padding: 10) {
                HStack(alignment: .center, spacing: AppTheme.eventsControlGroupSpacing) {
                    relatedNewsThumbnail(for: post)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !post.subtitle.isEmpty {
                            Text(post.subtitle)
                                .font(AppTheme.metadataFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                                AppMetadataLine(title: newsDateText(for: post), systemImage: "calendar")
                                AppMetadataLine(title: viewCountText(for: post), systemImage: "eye")
                            }

                            AppMetadataLine(title: newsDateText(for: post), systemImage: "calendar")
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                }
                .contentShape(Rectangle())
            }
        }

        @ViewBuilder
        func relatedNewsThumbnail(for post: NewsPost) -> some View {
            if let imageURL = sanitizedImageURL(post.imageURL) {
                RemoteImageView(
                    imageURL: imageURL,
                    height: 62,
                    cornerRadius: AppTheme.imageRadius,
                    source: "NewsDetailRelated",
                    placeholderStyle: .glassSkeleton
                )
                .frame(width: 82, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            } else {
                Image(systemName: "newspaper")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 82, height: 62)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            }
        }

        func relatedNewsPosts(for post: NewsPost) -> [NewsPost] {
            viewModel.posts
                .filter { $0.id != post.id }
                .sorted { lhs, rhs in
                    let lhsScore = relatedScore(lhs, to: post)
                    let rhsScore = relatedScore(rhs, to: post)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }
                    return lhs.publishedAt > rhs.publishedAt
                }
                .prefix(4)
                .map { $0 }
        }

        func relatedScore(_ candidate: NewsPost, to post: NewsPost) -> Int {
            var score = 0

            if candidate.category == post.category {
                score += 4
            }

            if candidate.federalState != nil && candidate.federalState == post.federalState {
                score += 3
            }

            let currentTags = Set(post.tags.map { $0.lowercased() })
            let candidateTags = Set(candidate.tags.map { $0.lowercased() })
            score += min(currentTags.intersection(candidateTags).count, 3) * 2

            if candidate.source.organizationId != nil && candidate.source.organizationId == post.source.organizationId {
                score += 1
            }

            return score
        }
}
