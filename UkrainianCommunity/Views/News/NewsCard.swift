import SwiftUI

struct NewsCard: View {
    let post: NewsPost
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: post.imageURL, height: AppTheme.feedImageHeight, source: "NewsCard")

            VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                Text(post.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.subtitle.isEmpty {
                    Text(post.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 88)
            }
        }
    }
}
