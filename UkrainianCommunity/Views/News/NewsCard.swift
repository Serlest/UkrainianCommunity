import SwiftUI
import UIKit

struct NewsCard: View {
    let post: NewsPost
    var previewImage: UIImage? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CommunityCard {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.feedImageHeight)
                    .clipped()
            } else {
                RemoteCardImage(imageURL: post.imageURL, height: AppTheme.feedImageHeight, source: "NewsCard")
            }

            VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                Text(post.localizedTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.localizedSubtitle.isEmpty {
                    Text(post.localizedSubtitle)
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
