import SwiftUI

struct LegacyGuideDetailView: View {
    let article: GuideArticle

    private var contentBlocks: [GuideContentBlock] {
        article.contentBlocks ?? []
    }

    private var officialSourceLink: GuideSourceLink? {
        article.sourceLinks?.first(where: \.isOfficial)
    }

    private var hasSourceLinks: Bool {
        !(article.sourceLinks ?? []).isEmpty || article.officialSourceURL != nil
    }

    private var showsPrimarySourceHighlight: Bool {
        officialSourceLink != nil || article.officialSourceURL != nil
    }

    private var shouldShowSourcesSection: Bool {
        if !hasSourceLinks {
            return false
        }

        let hasSupportingSources = !(article.sourceLinks ?? []).filter { !$0.isOfficial }.isEmpty
        return hasSupportingSources || !showsPrimarySourceHighlight
    }

    var body: some View {
        DetailPageContainer {
            DetailHeaderCard(title: article.title, subtitle: nil) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        GuideReviewBadge(state: article.reviewState, size: .small)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        GuideReviewBadge(state: article.reviewState, size: .small)
                    }
                }
            }

            if let officialSourceLink, let url = URL(string: officialSourceLink.url) {
                DetailCard {
                    sourceHighlightHeader

                    Link(destination: url) {
                        GuideSourceLinkRow(link: officialSourceLink)
                    }
                    .buttonStyle(.plain)
                }
            } else if let legacyURL = article.officialSourceURL, let url = URL(string: legacyURL) {
                DetailCard {
                    sourceHighlightHeader

                    Link(destination: url) {
                        DetailActionRow {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppStrings.Guide.officialSource)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(AppStrings.Guide.openOfficialSourceAction)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.accentPrimary)

                                Text(legacyURL)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(AppStrings.Guide.opensExternalWebsiteHint)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
                            }
                        } trailingContent: {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accentPrimary)

                                Text(AppStrings.Guide.openSourceAction)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.accentPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            DetailCard {
                if hasSourceLinks {
                    Text(AppStrings.Guide.articleOverviewLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                }

                Text(article.summary)
                    .font(AppTheme.cardTitleFont)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if contentBlocks.isEmpty {
                    Text(article.body)
                        .font(AppTheme.detailBodyFont)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !contentBlocks.isEmpty {
                DetailCard {
                    Text(AppStrings.Guide.articleContainsTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Guide.articleContainsSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(contentBlocks.enumerated()), id: \.element.id) { index, block in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.accentPrimary)
                                    .frame(width: 20, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.readerSummaryTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)

                                    Text(block.readerSummaryBody)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            if !contentBlocks.isEmpty {
                ForEach(contentBlocks) { block in
                    GuideContentBlockView(block: block)
                }
            }

            if shouldShowSourcesSection {
                GuideSourceLinksView(
                    links: article.sourceLinks ?? [],
                    legacyURL: article.officialSourceURL,
                    highlightsPrimarySource: showsPrimarySourceHighlight
                )
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationTitle(AppStrings.Guide.articleDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceHighlightHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.Guide.sourceSectionPrimaryTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Guide.sourceSectionPrimarySubtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension GuideContentBlock {
    var readerSummaryTitle: String {
        switch self {
        case .text(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeText, customTitle: block.title)
        case .steps(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeSteps, customTitle: block.title)
        case .checklist(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeChecklist, customTitle: block.title)
        case .warning(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeWarning, customTitle: block.title)
        case .infoBox(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeInfoBox, customTitle: block.title)
        case .links(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeLinks, customTitle: block.title)
        case .contacts(let block):
            summaryTitle(for: AppStrings.Guide.blockTypeContacts, customTitle: block.title)
        }
    }

    var readerSummaryBody: String {
        switch self {
        case .text(let block):
            block.text.guidePreviewText
        case .steps(let block):
            block.steps.guidePreviewText
        case .checklist(let block):
            block.items.guidePreviewText
        case .warning(let block), .infoBox(let block):
            block.message.guidePreviewText
        case .links(let block):
            block.links.compactMap { $0.title.guideNilIfEmpty }.first ?? AppStrings.Guide.noResults
        case .contacts(let block):
            block.contacts.compactMap { $0.name.guideNilIfEmpty }.first ?? AppStrings.Guide.noResults
        }
    }

    private func summaryTitle(for blockType: String, customTitle: String?) -> String {
        if let customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !customTitle.isEmpty {
            return "\(blockType) • \(customTitle)"
        }

        return blockType
    }
}

private extension String {
    var guidePreviewText: String {
        guideNilIfEmpty ?? AppStrings.Guide.noResults
    }

    var guideNilIfEmpty: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private extension Array where Element == String {
    var guidePreviewText: String {
        compactMap(\.guideNilIfEmpty).first ?? AppStrings.Guide.noResults
    }
}
