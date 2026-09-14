import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RemoteImageError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case tooLarge
    case invalidImage
    case cacheUnavailable
    case cacheFull
}

/// The downloader must enforce the byte limit while receiving, and validate every redirect before following it.
public protocol RemoteImageDownloading: Sendable {
    func download(_ url: URL, maximumBytes: Int) async throws -> RemoteImageDownload
}

public struct RemoteImageDownload: Sendable {
    public let data: Data
    public let responseURL: URL
    public let statusCode: Int
    public let redirects: [URL]

    public init(data: Data, responseURL: URL, statusCode: Int = 200, redirects: [URL] = []) {
        self.data = data
        self.responseURL = responseURL
        self.statusCode = statusCode
        self.redirects = redirects
    }
}

/// Prepares small raster images before a widget or activity needs to render them.
/// Each caller owns its download, so cancelling one caller never cancels another caller's image.
public actor RemoteImageLoader {
    public static let maximumDownloadBytes = 2 * 1_024 * 1_024
    private let cache: RemoteImageCache
    private let downloader: any RemoteImageDownloading

    public init(cache: RemoteImageCache, downloader: any RemoteImageDownloading = HTTPSImageDownloader()) {
        self.cache = cache
        self.downloader = downloader
    }

    public func load(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard let key = RemoteImageCache.key(for: url) else { throw RemoteImageError.invalidURL }
        if let cached = cache.data(forKey: key), let data = try? Self.thumbnail(cached) {
            // Preparing an existing image starts a fresh retention window for a new activity.
            try persistIfAvailable(data, forKey: key)
            return data
        }
        let result: RemoteImageDownload
        do {
            result = try await downloader.download(url, maximumBytes: Self.maximumDownloadBytes)
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        guard RemoteImageCache.isAllowed(result.responseURL), result.redirects.allSatisfy(RemoteImageCache.isAllowed) else {
            throw RemoteImageError.invalidURL
        }
        guard (200..<300).contains(result.statusCode) else { throw RemoteImageError.invalidResponse }
        guard result.data.count <= Self.maximumDownloadBytes else { throw RemoteImageError.tooLarge }
        let png = try Self.thumbnail(result.data)
        try Task.checkCancellation()
        try persistIfAvailable(png, forKey: key)
        return png
    }

    private func persistIfAvailable(_ data: Data, forKey key: String) throws {
        try Task.checkCancellation()
        do {
            try cache.store(data, forKey: key)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Persistence is optional: an unavailable/full cache must not hide a valid image in the app.
        }
        try Task.checkCancellation()
    }

    /// Validates and normalizes image bytes for a bounded raster presentation.
    public static func thumbnail(_ data: Data, maximumPixelSize: Int = 256) throws -> Data {
        guard (1...256).contains(maximumPixelSize) else { throw RemoteImageError.invalidImage }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png, .jpeg, .webP, .gif, .heic].contains(where: { $0.identifier == type }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4_096, height <= 4_096,
              width * height <= 4_000_000 else { throw RemoteImageError.invalidImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw RemoteImageError.invalidImage
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RemoteImageError.invalidImage
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let normalized = context.makeImage() else { throw RemoteImageError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw RemoteImageError.invalidImage
        }
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { throw RemoteImageError.invalidImage }
        guard output.length <= RemoteImageCache.maximumImageBytes else { throw RemoteImageError.tooLarge }
        return output as Data
    }
}

// This package is shared with extensions and cannot depend on the app HTTPClient.
// swiftlint:disable no_raw_urlsession no_raw_urlrequest
public struct HTTPSImageDownloader: RemoteImageDownloading {
    private let configuration: URLSessionConfiguration

    public init() {
        configuration = .ephemeral
    }

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    public func download(_ url: URL, maximumBytes: Int) async throws -> RemoteImageDownload {
        guard RemoteImageCache.isAllowed(url) else { throw RemoteImageError.invalidURL }
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url, delegate: HTTPSRedirectValidator())
        guard let response = response as? HTTPURLResponse, let finalURL = response.url,
              RemoteImageCache.isAllowed(finalURL), (200..<300).contains(response.statusCode) else {
            throw RemoteImageError.invalidResponse
        }
        guard response.expectedContentLength <= maximumBytes else { throw RemoteImageError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw RemoteImageError.tooLarge }
            data.append(byte)
        }
        return RemoteImageDownload(data: data, responseURL: finalURL, statusCode: response.statusCode)
    }
}

final class HTTPSRedirectValidator: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(RemoteImageCache.isAllowed) == true ? request : nil)
    }
}

// swiftlint:enable no_raw_urlsession no_raw_urlrequest
