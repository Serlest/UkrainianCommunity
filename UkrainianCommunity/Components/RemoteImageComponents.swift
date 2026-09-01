import SwiftUI
import UIKit
import Foundation
import ImageIO

private enum RemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 75 * 1024 * 1024
        return cache
    }()
}

enum RemoteImageDecodePolicy {
    static let minimumPixelSize: CGFloat = 128
    static let maximumPixelSize: CGFloat = 2_048
    static let pixelBucketSize: CGFloat = 64

    static func pixelSize(
        forMaximumDisplayDimension maximumDisplayDimension: CGFloat,
        displayScale: CGFloat
    ) -> CGFloat {
        guard maximumDisplayDimension.isFinite, displayScale.isFinite else {
            return maximumPixelSize
        }

        let requestedPixelSize = max(0, maximumDisplayDimension) * max(1, displayScale)
        let bucketedPixelSize = ceil(requestedPixelSize / pixelBucketSize) * pixelBucketSize
        return min(max(bucketedPixelSize, minimumPixelSize), maximumPixelSize)
    }
}

private struct RemoteImageLoadKey: Hashable {
    let imageURL: String?
    let maximumPixelSize: Int
}

private actor RemoteImageDataLoader {
    static let shared = RemoteImageDataLoader()

    private let session: URLSession
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )
        // Respect HTTP cache headers and revalidation so a reused Storage URL
        // can refresh instead of being served stale indefinitely.
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }

    func data(from url: URL) async throws -> Data {
        if let task = inFlight[url] { return try await task.value }

        let session = session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            if let response = response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}

private enum RemoteImageDecoder {
    static func decode(_ data: Data, maximumPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumPixelSize.rounded(.up)))
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: image)
        }.value
    }

    static func memoryCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

enum RemoteImagePlaceholderStyle {
    case icon
    case glassSkeleton
}

enum RemoteImagePresentationStyle {
    case fill
    case fit
    case adaptiveBanner
}

struct AdaptiveBannerImage: View {
    let image: UIImage

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .saturation(0.82)
                .blur(radius: 22, opaque: true)
                .scaleEffect(1.08)

            Color.black.opacity(0.10)

            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
        .clipped()
    }
}

struct RemoteImageView: View {
    private static let fallbackHeight: CGFloat = 220

    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    let placeholderStyle: RemoteImagePlaceholderStyle
    let presentationStyle: RemoteImagePresentationStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        placeholderStyle: RemoteImagePlaceholderStyle = .icon,
        presentationStyle: RemoteImagePresentationStyle = .fill
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.placeholderStyle = placeholderStyle
        self.presentationStyle = presentationStyle
    }

    var body: some View {
        GeometryReader { proxy in
            let loadKey = loadKey(for: proxy.size)

            Group {
                if let loadedImage {
                    loadedImageContent(loadedImage)
                } else if loadFailed {
                    unavailablePlaceholder
                } else {
                    loadingPlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: loadKey) {
                await loadImage(maximumPixelSize: CGFloat(loadKey.maximumPixelSize))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: resolvedHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var resolvedHeight: CGFloat {
        Self.normalizedHeight(for: height)
    }

    static func normalizedHeight(for height: CGFloat) -> CGFloat {
        height > 0 ? height : fallbackHeight
    }

    private func loadKey(for size: CGSize) -> RemoteImageLoadKey {
        let maximumDisplayDimension = max(max(size.width, size.height), resolvedHeight)
        let maximumPixelSize = RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: maximumDisplayDimension,
            displayScale: displayScale
        )
        return RemoteImageLoadKey(
            imageURL: imageURL,
            maximumPixelSize: Int(maximumPixelSize.rounded(.up))
        )
    }

    @ViewBuilder
    private func loadedImageContent(_ image: UIImage) -> some View {
        switch presentationStyle {
        case .fill:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: resolvedHeight)
                .clipped()
        case .fit:
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: resolvedHeight)
                .clipped()
        case .adaptiveBanner:
            AdaptiveBannerImage(image: image)
                .frame(maxWidth: .infinity)
                .frame(height: resolvedHeight)
        }
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
    private func loadImage(maximumPixelSize: CGFloat) async {
        loadedImage = nil
        loadFailed = false

        guard let imageURL, let url = URL(string: imageURL) else {
            return
        }

        let cacheKey = "\(imageURL)#content-\(Int(maximumPixelSize))" as NSString
        if let cachedImage = RemoteImageCache.shared.object(forKey: cacheKey) {
            loadedImage = cachedImage
            return
        }

        do {
            let data = try await RemoteImageDataLoader.shared.data(from: url)
            guard !Task.isCancelled else { return }
            guard let image = await RemoteImageDecoder.decode(
                data,
                maximumPixelSize: maximumPixelSize
            ) else {
                loadFailed = true
                return
            }
            guard !Task.isCancelled else { return }

            RemoteImageCache.shared.setObject(
                image,
                forKey: cacheKey,
                cost: RemoteImageDecoder.memoryCost(of: image)
            )
            loadedImage = image
        } catch {
            guard !Task.isCancelled else { return }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return
            }
            loadFailed = true
            #if DEBUG
            print("RemoteImageView failed source=\(source) requestedHeight=\(height) resolvedHeight=\(resolvedHeight) code=\(nsError.code) message=\(nsError.localizedDescription)")
            #endif
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
    private static let minimumDecodedPixelSize: CGFloat = 512
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
                            .tint(AppTheme.accentPrimaryForeground)
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

        let decodedPixelSize = max(Self.minimumDecodedPixelSize, size * 3)
        let cacheKey = "\(avatarURLString)#avatar-\(Int(decodedPixelSize.rounded(.up)))" as NSString
        if let image = RemoteImageCache.shared.object(forKey: cacheKey) {
            cachedAvatarImage = image
            cachedAvatarURL = avatarURLString
            avatarLoadFailed = false
            return
        }

        avatarLoadFailed = false

        do {
            let data = try await RemoteImageDataLoader.shared.data(from: url)
            guard let image = await RemoteImageDecoder.decode(
                data,
                maximumPixelSize: decodedPixelSize
            ) else {
                avatarLoadFailed = true
                return
            }

            RemoteImageCache.shared.setObject(
                image,
                forKey: cacheKey,
                cost: RemoteImageDecoder.memoryCost(of: image)
            )
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
                    .tint(AppTheme.accentPrimaryForeground)
            } else {
                Text(initials)
                    .font(initialsFont ?? .system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
            }
        }
    }
}
