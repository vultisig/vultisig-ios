import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import VultisigUIResources

// Tests exercise the standalone package networking seam and redirect delegate.
// swiftlint:disable no_raw_urlsession no_raw_urlrequest
final class RemoteImageTests: XCTestCase {
    private var directory: URL!
    private let url = URL(string: "https://images.example.com/token.png")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("remote-image-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStableKeyAndInvalidURLs() {
        XCTAssertEqual(RemoteImageCache.key(for: url), "c764df1a4ae947d4aab8dacc3782efe26025234efb9e07199c6da44be8475231")
        for value in ["http://example.com/x", "file:///tmp/x", "https://user@example.com/x", "https://user:pass@example.com/x", "https:/x"] {
            XCTAssertNil(RemoteImageCache.key(for: URL(string: value)!))
        }
    }

    func testInvalidKeysNeverBecomePaths() throws {
        let cache = RemoteImageCache(directory: directory)
        for key in ["../secret", url.absoluteString, String(repeating: "A", count: 64), String(repeating: "0", count: 63)] {
            XCTAssertNil(cache.data(forKey: key))
            XCTAssertThrowsError(try cache.store(Data([1]), forKey: key))
        }
    }

    func testOfflineReadAcrossCacheInstancesAndNilDirectory() throws {
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        let png = try image(width: 100, height: 50)
        try RemoteImageCache(directory: directory).store(png, forKey: key)
        XCTAssertEqual(RemoteImageCache(directory: directory).data(forKey: key), png)
        try RemoteImageCache(directory: nil).store(png, forKey: key)
        XCTAssertNil(RemoteImageCache(directory: nil).data(forKey: key))
    }

    func testBoundedAndExpiredReads() throws {
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        let file = directory.appendingPathComponent(key)
        let oversized = Data(repeating: 0, count: RemoteImageCache.maximumImageBytes + 1)
        try oversized.write(to: file)
        let cache = RemoteImageCache(directory: directory)
        XCTAssertNil(cache.data(forKey: key))
        XCTAssertThrowsError(try cache.store(oversized, forKey: key))
        try cache.store(Data([1]), forKey: key)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 24 * 3_600)], ofItemAtPath: file.path)
        XCTAssertNil(cache.data(forKey: key))
    }

    func testCacheQuotaPreservesActiveImagesAndEvictsOlderImages() throws {
        let cache = RemoteImageCache(directory: directory)
        let data = Data(repeating: 1, count: RemoteImageCache.maximumImageBytes)
        let keys = (0..<129).map { String(format: "%064x", $0) }
        // Populate the bounded directory directly; store performs its best-effort quota check before atomic replacement.
        for key in keys.prefix(128) { try data.write(to: directory.appendingPathComponent(key)) }
        XCTAssertThrowsError(try cache.store(data, forKey: keys[128])) { XCTAssertEqual($0 as? RemoteImageError, .cacheFull) }
        let oldFile = directory.appendingPathComponent(keys[0])
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 3_600)], ofItemAtPath: oldFile.path)
        try cache.store(data, forKey: keys[128])
        XCTAssertNil(cache.data(forKey: keys[0]))
        XCTAssertEqual(cache.data(forKey: keys[1]), data)
        XCTAssertEqual(cache.data(forKey: keys[128]), data)
    }

    func testConcurrentCacheInstancesNeverReadPartialWrites() async throws {
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        let directory = try XCTUnwrap(directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for value in UInt8(1)...24 {
                group.addTask {
                    let cache = RemoteImageCache(directory: directory)
                    try cache.store(Data(repeating: value, count: 32_768), forKey: key)
                    let read = try XCTUnwrap(cache.data(forKey: key))
                    XCTAssertEqual(read.count, 32_768)
                    XCTAssertEqual(Set(read).count, 1)
                }
            }
            try await group.waitForAll()
        }
    }

    func testLoaderNormalizesAndReusesOfflineImage() async throws {
        let downloader = StubDownloader(result: .init(data: try image(width: 1_024, height: 512), responseURL: url))
        let cache = RemoteImageCache(directory: directory)
        let loader = RemoteImageLoader(cache: cache, downloader: downloader)
        let png = try await loader.load(url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 256)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 128)
        XCTAssertEqual(properties[kCGImagePropertyDepth] as? Int, 8)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let offline = RemoteImageLoader(cache: RemoteImageCache(directory: directory), downloader: RejectingDownloader())
        let reread = try await offline.load(url)
        XCTAssertEqual(png, reread)
    }

    func testPreparingCachedImageRenewsActivityRetention() async throws {
        let cache = RemoteImageCache(directory: directory)
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        try cache.store(try image(width: 10, height: 10), forKey: key)
        let file = directory.appendingPathComponent(key)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-6 * 24 * 3_600)], ofItemAtPath: file.path)
        let before = Date()
        _ = try await RemoteImageLoader(cache: cache, downloader: RejectingDownloader()).load(url)
        let modified = try XCTUnwrap(file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertGreaterThanOrEqual(modified.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
    }

    func testRejectsInvalidResponsesAndImageData() async throws {
        let png = try image(width: 10, height: 10)
        let cases: [(RemoteImageDownload, RemoteImageError)] = [
            (.init(data: png, responseURL: URL(string: "http://example.com/x")!), .invalidURL),
            (.init(data: png, responseURL: url, redirects: [URL(string: "https://user@example.com/x")!]), .invalidURL),
            (.init(data: png, responseURL: url, redirects: [URL(string: "http://example.com/x")!]), .invalidURL),
            (.init(data: png, responseURL: url, statusCode: 404), .invalidResponse),
            (.init(data: Data(repeating: 0, count: RemoteImageLoader.maximumDownloadBytes + 1), responseURL: url), .tooLarge),
            (.init(data: Data("<svg width='10' height='10'></svg>".utf8), responseURL: url), .invalidImage),
            (.init(data: Data([0, 1, 2]), responseURL: url), .invalidImage)
        ]
        for (result, expected) in cases {
            do {
                _ = try await RemoteImageLoader(cache: .init(directory: nil), downloader: StubDownloader(result: result)).load(url)
                XCTFail("Expected \(expected)")
            } catch { XCTAssertEqual(error as? RemoteImageError, expected) }
        }
    }

    func testCancellationPreventsLateDownloadFromWriting() async throws {
        let downloader = SuspendedDownloader(result: .init(data: try image(width: 10, height: 10), responseURL: url))
        let cache = RemoteImageCache(directory: directory)
        let loader = RemoteImageLoader(cache: cache, downloader: downloader)
        let task = Task { try await loader.load(url) }
        await downloader.waitUntilStarted()
        task.cancel()
        await downloader.finish()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(cache.data(forKey: try XCTUnwrap(RemoteImageCache.key(for: url))))
    }

    func testCancelledConcurrentLoadDoesNotOverwriteSuccessfulLoad() async throws {
        let downloader = SuspendedDownloader(result: .init(data: try image(width: 10, height: 10), responseURL: url))
        let cache = RemoteImageCache(directory: directory)
        let slowLoader = RemoteImageLoader(cache: cache, downloader: downloader)
        let task = Task { try await slowLoader.load(url) }
        await downloader.waitUntilStarted()
        let successfulLoader = RemoteImageLoader(cache: cache, downloader: StubDownloader(
            result: .init(data: try image(width: 20, height: 10), responseURL: url)
        ))
        let successful = try await successfulLoader.load(url)
        task.cancel()
        await downloader.finish()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(cache.data(forKey: try XCTUnwrap(RemoteImageCache.key(for: url))), successful)
    }

    func testRejectsSymlinkCacheEntries() throws {
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        let target = directory.appendingPathComponent("other")
        try Data([1]).write(to: target)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(key), withDestinationURL: target)
        XCTAssertNil(RemoteImageCache(directory: directory).data(forKey: key))
    }

    func testRedirectDelegateRejectsDowngradesBeforeFollowing() throws {
        let validator = HTTPSRedirectValidator()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        var callbackCount = 0
        for target in ["http://example.com/x", "https://user@example.com/x", "https://example.com/x"] {
            let request = URLRequest(url: URL(string: target)!)
            validator.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { accepted in
                callbackCount += 1
                XCTAssertEqual(accepted != nil, target == "https://example.com/x")
            }
        }
        XCTAssertEqual(callbackCount, 3)
    }

    func testFutureDatedAndAbandonedFilesAreRemoved() throws {
        let cache = RemoteImageCache(directory: directory)
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        let file = directory.appendingPathComponent(key)
        try cache.store(Data([1]), forKey: key)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3_600)], ofItemAtPath: file.path)
        XCTAssertNil(cache.data(forKey: key))
        let abandoned = directory.appendingPathComponent(".abandoned-atomic-write")
        try Data([1]).write(to: abandoned)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: abandoned.path)
        try cache.store(Data([2]), forKey: String(repeating: "1", count: 64))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testPersistenceFailureStillReturnsPreparedImage() async throws {
        let file = directory.appendingPathComponent("file-not-directory")
        try Data([1]).write(to: file)
        let loader = RemoteImageLoader(cache: .init(directory: file), downloader: StubDownloader(
            result: .init(data: try image(width: 10, height: 10), responseURL: url)
        ))
        let png = try await loader.load(url)
        XCTAssertNotNil(CGImageSourceCreateWithData(png as CFData, nil))
    }

    func testUnsupportedFormatAndExcessiveSourcePixelsAreRejected() throws {
        for data in [try image(width: 10, height: 10, type: .tiff), try image(width: 2_001, height: 2_000)] {
            XCTAssertThrowsError(try RemoteImageLoader.thumbnail(data)) { XCTAssertEqual($0 as? RemoteImageError, .invalidImage) }
        }
    }

    private func image(width: Int, height: Int, type: UTType = .png) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private struct StubDownloader: RemoteImageDownloading {
    let result: RemoteImageDownload
    func download(_: URL, maximumBytes _: Int) throws -> RemoteImageDownload { result }
}

private struct RejectingDownloader: RemoteImageDownloading {
    func download(_: URL, maximumBytes _: Int) throws -> RemoteImageDownload { throw URLError(.notConnectedToInternet) }
}

private actor SuspendedDownloader: RemoteImageDownloading {
    let result: RemoteImageDownload
    var continuation: CheckedContinuation<RemoteImageDownload, Never>?
    var startWaiter: CheckedContinuation<Void, Never>?

    init(result: RemoteImageDownload) { self.result = result }

    func download(_: URL, maximumBytes _: Int) async throws -> RemoteImageDownload {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() { continuation?.resume(returning: result); continuation = nil }
}

// swiftlint:enable no_raw_urlsession no_raw_urlrequest
