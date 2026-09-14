import XCTest
import UIKit
import VultisigUIResources
@testable import VultisigApp

final class SharedRemoteImageIntegrationTests: XCTestCase {
    @MainActor
    func testAppPreparedImageLoadsOfflineFromIndependentWidgetLoader() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RemoteImageCache(directory: directory)
        let url = try XCTUnwrap(URL(string: "https://tokens.example.org/rune.png"))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let png = renderer.pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        let downloader = SharedImageTestDownloader(data: png)
        let appLoader = RemoteImageLoader(cache: cache, downloader: downloader)
        let prepared = try await appLoader.load(url)
        let offlineDownloader = SharedImageTestDownloader(data: nil)
        let widgetLoader = RemoteImageLoader(cache: RemoteImageCache(directory: directory), downloader: offlineDownloader)
        let widget = WidgetMarketClient(imageLoader: widgetLoader)

        let cached = try await widget.iconData(from: url)

        XCTAssertEqual(cached, prepared)
        XCTAssertNotNil(SharedImageLoading.image(from: cached))
        let downloads = await downloader.calls
        let offlineDownloads = await offlineDownloader.calls
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(offlineDownloads, 0)
    }

    func testWidgetRejectsInsecureImageBeforeDownloading() async throws {
        let downloader = SharedImageTestDownloader(data: nil)
        let loader = RemoteImageLoader(cache: RemoteImageCache(directory: nil), downloader: downloader)
        let widget = WidgetMarketClient(imageLoader: loader)
        let url = try XCTUnwrap(URL(string: "http://tokens.example.org/rune.png"))
        do {
            _ = try await widget.iconData(from: url)
            XCTFail("Insecure image should be rejected")
        } catch {
            XCTAssertEqual(error as? WidgetMarketError, .unapprovedImageURL)
        }
        let downloads = await downloader.calls
        XCTAssertEqual(downloads, 0)
    }
}

private actor SharedImageTestDownloader: RemoteImageDownloading {
    let data: Data?
    private(set) var calls = 0

    init(data: Data?) {
        self.data = data
    }

    func download(_ url: URL, maximumBytes _: Int) throws -> RemoteImageDownload {
        calls += 1
        guard let data else { throw URLError(.notConnectedToInternet) }
        return RemoteImageDownload(data: data, responseURL: url)
    }
}
