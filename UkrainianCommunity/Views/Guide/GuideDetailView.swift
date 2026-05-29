import SwiftUI

struct GuideDetailView: View {
    let article: GuideArticle

    private var contentBlocks: [GuideContentBlock] {
        article.contentBlocks ?? []
    }

    var body: some View {
        DetailPageContainer {
            DetailHeaderCard(title: article.title, subtitle: nil) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        if let sourceName = article.sourceName, !sourceName.isEmpty {
                            ContentMetadataPill(systemImage: "link", text: sourceName)
                        }

                        GuideReviewBadge(state: article.reviewState, size: .small)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        if let sourceName = article.sourceName, !sourceName.isEmpty {
                            ContentMetadataPill(systemImage: "link", text: sourceName)
                        }

                        GuideReviewBadge(state: article.reviewState, size: .small)
                    }
                }
            }

            DetailCard {
                Text(article.summary)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if contentBlocks.isEmpty {
                    Text(article.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !contentBlocks.isEmpty {
                ForEach(contentBlocks) { block in
                    GuideContentBlockView(block: block)
                }
            }

            GuideSourceLinksView(
                links: article.sourceLinks ?? [],
                legacyURL: article.officialSourceURL
            )
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Guide.articleDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
