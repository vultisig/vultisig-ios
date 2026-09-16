import SwiftUI
import VultisigUIResources

/// App views and timeline preparation use the same container and image policy.
enum SharedImageLoading {
    #if WIDGET_EXTENSION
    static let cache = RemoteImageCache.shared()
    #else
    static let cache = RemoteImageCache.shared(allowLocalFallback: true)
    #endif
    static let loader = RemoteImageLoader(cache: cache)

    @MainActor private static let displayedImages: NSCache<NSString, DisplayedImage> = {
        let cache = NSCache<NSString, DisplayedImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    @MainActor
    static func cachedImage(forKey key: String, cache: RemoteImageCache) -> Image? {
        if let stored = displayedImages.object(forKey: key as NSString), stored.expiresAt > Date() {
            return stored.image
        }
        guard let data = cache.data(forKey: key), let image = image(from: data) else { return nil }
        remember(image, forKey: key)
        return image
    }

    @MainActor
    static func remember(_ image: Image, forKey key: String) {
        // Normalized images are at most 256px RGBA; bound decoded memory separately from disk.
        displayedImages.setObject(DisplayedImage(image: image), forKey: key as NSString, cost: 256 * 256 * 4)
    }

    private final class DisplayedImage {
        let image: Image
        let expiresAt = Date().addingTimeInterval(5 * 60)
        init(image: Image) { self.image = image }
    }

    static func image(from data: Data) -> Image? {
        #if os(iOS)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif os(macOS)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let cache: RemoteImageCache
    private let loader: RemoteImageLoader
    private let content: (AsyncImagePhase) -> Content
    @State private var loadedURL: URL?
    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        cache: RemoteImageCache = SharedImageLoading.cache,
        loader: RemoteImageLoader = SharedImageLoading.loader,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.cache = cache
        self.loader = loader
        self.content = content
    }

    init<ImageContent: View, Placeholder: View>(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> ImageContent,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) where Content == _ConditionalContent<ImageContent, Placeholder> {
        self.init(url: url) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }

    var body: some View {
        #if WIDGET_EXTENSION
        // Widget rendering cannot wait on a network task. The timeline prepares images.
        content(cachedPhase ?? .failure(RemoteImageError.cacheUnavailable))
        #else
        content(loadedURL == url ? phase : (cachedPhase ?? .empty))
            .task(id: url) {
                let requestedURL = url
                guard let requestedURL else { return }
                if let cachedPhase {
                    loadedURL = requestedURL
                    phase = cachedPhase
                    return
                }
                do {
                    let data = try await loader.load(requestedURL)
                    try Task.checkCancellation()
                    guard let image = SharedImageLoading.image(from: data) else {
                        throw RemoteImageError.invalidImage
                    }
                    if let key = RemoteImageCache.key(for: requestedURL) {
                        SharedImageLoading.remember(image, forKey: key)
                    }
                    loadedURL = requestedURL
                    phase = .success(image)
                } catch {
                    guard !Task.isCancelled else { return }
                    loadedURL = requestedURL
                    phase = .failure(error)
                }
            }
        #endif
    }

    private var cachedPhase: AsyncImagePhase? {
        guard let url, let key = RemoteImageCache.key(for: url),
              let image = SharedImageLoading.cachedImage(forKey: key, cache: cache) else { return nil }
        return .success(image)
    }
}
