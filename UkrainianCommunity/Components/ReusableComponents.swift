import SwiftUI
import UIKit

private enum RemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
}

struct GradientHeroCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct AdaptiveCardGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: horizontalSizeClass == .regular ? 2 : 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

struct CommunityCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
        )
    }
}

struct RemoteImageView: View {
    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    @State private var loadedImage: UIImage?

    init(imageURL: String?, height: CGFloat, cornerRadius: CGFloat = 18) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: imageURL) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.groupedBackground)
            LinearGradient(
                colors: [
                    AppTheme.groupedBackground,
                    AppTheme.cardBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadImage() async {
        loadedImage = nil

        guard let imageURL, let url = URL(string: imageURL) else {
            return
        }

        let cacheKey = imageURL as NSString
        if let cachedImage = RemoteImageCache.shared.object(forKey: cacheKey) {
            loadedImage = cachedImage
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return
            }

            RemoteImageCache.shared.setObject(image, forKey: cacheKey)
            loadedImage = image
        } catch {}
    }
}

struct RemoteCardImage: View {
    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat

    init(imageURL: String?, height: CGFloat, cornerRadius: CGFloat = 18) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RemoteImageView(imageURL: imageURL, height: height, cornerRadius: cornerRadius)
    }
}

struct LikeButton: View {
    let isLiked: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(count)", systemImage: isLiked ? "heart.fill" : "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isLiked ? AppTheme.accentRed : AppTheme.primaryBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill((isLiked ? AppTheme.accentRed : AppTheme.primaryBlue).opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.primaryBlue)
        }
        .font(.subheadline)
    }
}

struct EmptyStateView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "tray")
    }
}
