import SwiftUI

extension NewsDetailView {
        func navigateBack() {
            if let onNavigateBack {
                onNavigateBack()
            } else {
                dismiss()
            }
        }

        func newsHeaderActions(for post: NewsPost) -> some View {
            Group {
                DetailHeaderActionButton(
                    systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark",
                    accessibilityLabel: post.isBookmarked ? AppStrings.Action.unsave : AppStrings.Action.save,
                    isDisabled: viewModel.pendingNewsBookmarkIDs.contains(post.id),
                    isSelected: post.isBookmarked
                ) {
                    handleBookmark(for: post.id)
                }

                DetailHeaderShareButton(
                    title: post.localizedTitle,
                    message: newsShareMessage(for: post),
                    url: safeShareURL(post.sourceURL)
                )

                DetailHeaderActionsMenu(
                    onEdit: canEditNews
                        ? { isShowingEditSheet = true }
                        : nil,
                    onReport: post.authorId != authState.user?.id || !authState.isAuthenticated
                        ? { presentContentReport(.news(post)) }
                        : nil,
                    onBlock: newsBlockAction(for: post),
                    destructiveTitle: canDeleteNews ? AppStrings.Action.delete : nil,
                    onDestructive: canDeleteNews
                        ? { showDeleteConfirmation = true }
                        : nil,
                    isDestructiveDisabled: isDeleting
                )
            }
        }

        func newsBlockAction(for post: NewsPost) -> (() -> Void)? {
            guard authState.isAuthenticated,
                  let target = UserBlockTarget.news(post),
                  target.userId != authState.user?.id else {
                return nil
            }
            return { userBlockingPresentation.present(target) }
        }

        func presentContentReport(_ target: ContentReportTarget) {
            guard authState.isAuthenticated else {
                guestAccessAction = .feedback
                return
            }
            contentReportPresentation.present(target)
        }

        func newsShareMessage(for post: NewsPost) -> String {
            let subtitle = post.localizedSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = subtitle.isEmpty ? post.localizedBody.trimmingCharacters(in: .whitespacesAndNewlines) : subtitle
            guard source.count > 400 else { return source }
            return String(source.prefix(397)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        func safeShareURL(_ value: String?) -> URL? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return url
        }

        func articleHeader(for post: NewsPost) -> some View {
            DetailHeaderCard(title: post.localizedTitle, subtitle: nil) {
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
                .accessibilityLabel(post.mediaMetadata?.alternativeText ?? post.localizedTitle)

                if post.mediaMetadata?.caption != nil || post.mediaMetadata?.credit != nil {
                    Text([post.mediaMetadata?.caption, post.mediaMetadata?.credit]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }

        func leadBlock(for post: NewsPost) -> some View {
            DetailCard {
                HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "info.circle")
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppStrings.News.summarySectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(post.localizedSubtitle)
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
                        .foregroundStyle(AppTheme.accentPrimaryForeground)

                    Text(post.localizedBody)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
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
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        if let url = source.url {
                            Link(destination: url) {
                                Label(source.title, systemImage: "link")
                                    .font(AppTheme.metadataStrongFont)
                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
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

        @ViewBuilder
        func articleExternalActionSection(for post: NewsPost) -> some View {
            if let action = post.externalAction, let url = action.webURL {
                Link(destination: url) {
                    Label(action.title ?? ContentPublishingStrings.externalLink, systemImage: "arrow.up.right.square")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
            }
        }

        func trimmedNonEmpty(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        @ViewBuilder
        func tagsSection(for post: NewsPost) -> some View {
            if !post.additionalCategories.isEmpty || !post.tags.isEmpty {
                DetailCard {
                    if !post.additionalCategories.isEmpty {
                        Text(AppStrings.NewsEditor.additionalCategoriesTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        AppHorizontalChipRow {
                            ForEach(post.additionalCategories) { category in
                                AppInfoChip(title: category.title, systemImage: category.systemImage, size: .small)
                            }
                        }
                    }

                    if !post.tags.isEmpty {
                        Text(AppStrings.News.tagsSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        AppHorizontalChipRow {
                            ForEach(post.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(AppTheme.metadataStrongFont)
                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.accentPrimarySoft, in: Capsule())
                            }
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
                            systemImage: post.likeState.isLiked ? "heart.fill" : "heart",
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
                        .foregroundStyle(isSelected ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)

                    Text("\(count)")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                }
                .frame(minWidth: 74, minHeight: AppTheme.minimumInteractiveTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPressFeedbackButtonStyle())
            .disabled(isPlaceholder)
            .opacity(isPlaceholder ? 0.72 : 1)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(count)")
            .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        func publisherLine(for post: NewsPost) -> some View {
            Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
                .font(AppTheme.metadataFont)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 190, alignment: .trailing)
                .accessibilityLabel(newsPublisherText(for: post))
        }

        @ViewBuilder
        func relatedSection(for _: NewsPost) -> some View {
            if !relatedNewsRecommendations.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        Text(AppStrings.News.relatedSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(relatedNewsRecommendations) { recommendation in
                                NavigationLink {
                                    NewsDetailView(
                                        viewModel: viewModel,
                                        postID: recommendation.post.id,
                                        onNewsDeleted: onNewsDeleted,
                                        analyticsSourceScreen: "news_recommendation"
                                    )
                                    .environment(\.newsPresentationMode, presentationMode)
                                } label: {
                                    relatedNewsCard(recommendation)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("news.related.\(recommendation.post.id)")
                            }
                        }
                    }
                }
            }
        }

        func relatedNewsCard(_ recommendation: NewsContentRecommendation) -> some View {
            let post = recommendation.post
            return SoftContentCard(padding: 10) {
                HStack(alignment: .center, spacing: AppTheme.eventsControlGroupSpacing) {
                    relatedNewsThumbnail(for: post)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.localizedTitle)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !post.localizedSubtitle.isEmpty {
                            Text(post.localizedSubtitle)
                                .font(AppTheme.metadataFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }

                        Label(
                            recommendation.primaryReason.title,
                            systemImage: recommendation.primaryReason.systemImage
                        )
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .lineLimit(1)

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
                        .foregroundStyle(AppTheme.textSecondary)
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
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 82, height: 62)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            }
        }

}
