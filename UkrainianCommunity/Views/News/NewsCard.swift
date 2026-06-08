import SwiftUI

struct NewsCard: View {
    let post: NewsPost

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: post.imageURL, height: AppTheme.feedImageHeight, source: "NewsCard")

            VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                Text(post.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !post.subtitle.isEmpty {
                    Text(post.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.trailing, 88)
            }
        }
    }
}
