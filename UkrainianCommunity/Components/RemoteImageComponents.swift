import SwiftUI
import UIKit
import Foundation

private enum RemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 75 * 1024 * 1024
        return cache
    }()
}

enum RemoteImagePlaceholderStyle {
    case icon
    case glassSkeleton
}

struct RemoteImageView: View {
    private static let fallbackHeight: CGFloat = 220

    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    let placeholderStyle: RemoteImagePlaceholderStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        placeholderStyle: RemoteImagePlaceholderStyle = .icon
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.placeholderStyle = placeholderStyle
    }

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            } else if loadFailed {
                unavailablePlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            } else {
                loadingPlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: imageURL) {
            await loadImage()
        }
    }

    private var resolvedHeight: CGFloat {
        Self.normalizedHeight(for: height)
    }

    static func normalizedHeight(for height: CGFloat) -> CGFloat {
        height > 0 ? height : fallbackHeight
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
            LinearGradient(
                colors: [
                    AppTheme.surfaceSecondary,
                    AppTheme.surfacePrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        switch placeholderStyle {
        case .icon:
            placeholder(systemImage: "photo")
        case .glassSkeleton:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme))
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.20),
                            Color.white.opacity(0.02),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
        }
    }

    private var unavailablePlaceholder: some View {
        placeholder(systemImage: "photo.badge.exclamationmark")
    }

    @MainActor
    private func loadImage() async {
        loadedImage = nil
        loadFailed = false

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
                loadFailed = true
                return
            }

            RemoteImageCache.shared.setObject(image, forKey: cacheKey, cost: data.count)
            loadedImage = image
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return
            }
            loadFailed = true
            print("RemoteImageView failed source=\(source) requestedHeight=\(height) resolvedHeight=\(resolvedHeight) code=\(nsError.code) message=\(nsError.localizedDescription)")
        }
    }
}

struct RemoteCardImage: View {
    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    let isDecorative: Bool
    let placeholderStyle: RemoteImagePlaceholderStyle

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        isDecorative: Bool = false,
        placeholderStyle: RemoteImagePlaceholderStyle = .icon
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.isDecorative = isDecorative
        self.placeholderStyle = placeholderStyle
    }

    var body: some View {
        RemoteImageView(
            imageURL: imageURL,
            height: height,
            cornerRadius: cornerRadius,
            source: source,
            placeholderStyle: placeholderStyle
        )
            .accessibilityHidden(isDecorative)
    }
}

struct AvatarArtworkView: View {
    let avatarURL: URL?
    let previewImage: UIImage?
    let initials: String
    let size: CGFloat
    let accessibilityLabel: String?
    let isLoading: Bool
    let isDecorative: Bool
    let showsBorder: Bool
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let initialsFont: Font?
    let placeholderFill: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var cachedAvatarImage: UIImage?
    @State private var cachedAvatarURL: String?
    @State private var avatarLoadFailed = false

    init(
        avatarURL: URL?,
        previewImage: UIImage? = nil,
        initials: String,
        size: CGFloat,
        accessibilityLabel: String? = nil,
        isLoading: Bool = false,
        isDecorative: Bool = false,
        showsBorder: Bool = true,
        shadowOpacity: Double = 0.06,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 4,
        initialsFont: Font? = nil,
        placeholderFill: Color? = nil
    ) {
        self.avatarURL = avatarURL
        self.previewImage = previewImage
        self.initials = initials
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.isLoading = isLoading
        self.isDecorative = isDecorative
        self.showsBorder = showsBorder
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.initialsFont = initialsFont
        self.placeholderFill = placeholderFill
    }

    var body: some View {
        ZStack {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())

            if isLoading {
                Circle()
                    .fill(reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme))
                    .background {
                        if !reduceTransparency {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .overlay {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(AppTheme.accentPrimary)
                    }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showsBorder {
                Circle().stroke(AppTheme.borderSubtle)
            }
        }
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        .accessibilityHidden(isDecorative)
        .accessibilityLabel(accessibilityLabel ?? initials)
        .task(id: avatarURL?.absoluteString) {
            await loadAvatarImage()
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else if let avatarURLString = avatarURL?.absoluteString {
            if let cachedAvatarImage, cachedAvatarURL == avatarURLString {
                Image(uiImage: cachedAvatarImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                avatarPlaceholder(showProgress: !avatarLoadFailed)
            }
        } else {
            avatarPlaceholder(showProgress: false)
        }
    }

    @MainActor
    private func loadAvatarImage() async {
        guard let avatarURLString = avatarURL?.absoluteString,
              let url = URL(string: avatarURLString) else {
            cachedAvatarImage = nil
            cachedAvatarURL = nil
            avatarLoadFailed = false
            return
        }

        let cacheKey = avatarURLString as NSString
        if let image = RemoteImageCache.shared.object(forKey: cacheKey) {
            cachedAvatarImage = image
            cachedAvatarURL = avatarURLString
            avatarLoadFailed = false
            return
        }

        avatarLoadFailed = false

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                avatarLoadFailed = true
                return
            }

            RemoteImageCache.shared.setObject(image, forKey: cacheKey, cost: data.count)
            cachedAvatarImage = image
            cachedAvatarURL = avatarURLString
            avatarLoadFailed = false
        } catch {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                avatarLoadFailed = true
            }
        }
    }

    private var placeholderBackground: AnyShapeStyle {
        if let placeholderFill {
            return AnyShapeStyle(placeholderFill)
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [AppTheme.accentPrimarySoft, AppTheme.surfaceSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func avatarPlaceholder(showProgress: Bool) -> some View {
        ZStack {
            Circle()
                .fill(placeholderBackground)

            if showProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accentPrimary)
            } else {
                Text(initials)
                    .font(initialsFont ?? .system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }
    }
}
