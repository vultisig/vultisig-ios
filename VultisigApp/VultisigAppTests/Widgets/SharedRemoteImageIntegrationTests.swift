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

    @MainActor
    func testDetailedImageFitsWidgetInlineBudgetAfterPreparation() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 250, height: 250), format: format)
        let jpeg = renderer.jpegData(withCompressionQuality: 0.3) { context in
            for y in 0..<250 {
                for x in 0..<250 {
                    let seed = (x * 73 + y * 157 + x * y * 13) % 256
                    UIColor(red: CGFloat(x) / 250, green: CGFloat(y) / 250,
                            blue: CGFloat(seed) / 255, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        XCTAssertLessThan(jpeg.count, 64 * 1_024)
        let prepared = try RemoteImageLoader.thumbnail(jpeg)
        XCTAssertGreaterThan(prepared.count, 64 * 1_024, "Fixture must exercise PNG expansion")
        let downloader = SharedImageTestDownloader(data: jpeg)
        let loader = RemoteImageLoader(cache: RemoteImageCache(directory: nil), downloader: downloader)
        let widget = WidgetMarketClient(imageLoader: loader)
        let url = try XCTUnwrap(URL(string: "https://images.example.org/detailed.jpg"))

        let inline = try await widget.iconData(from: url)

        XCTAssertLessThanOrEqual(inline.count, 64 * 1_024)
        let image = try XCTUnwrap(UIImage(data: inline))
        XCTAssertEqual(image.size.width, 120)
        XCTAssertEqual(image.size.height, 120)
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
