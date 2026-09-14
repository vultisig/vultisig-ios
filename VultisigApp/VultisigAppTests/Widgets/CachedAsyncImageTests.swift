import XCTest
import SwiftUI
import UIKit
import VultisigUIResources
@testable import VultisigApp

@MainActor
final class CachedAsyncImageTests: XCTestCase {
    func testCachedAppearanceDoesNotRewritePreparedImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://images.example.org/cached.png"))
        let cache = RemoteImageCache(directory: directory)
        let key = try XCTUnwrap(RemoteImageCache.key(for: url))
        try cache.store(png(), forKey: key)
        let file = directory.appendingPathComponent(key)
        let before = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let rendered = expectation(description: "Cached image rendered")
        rendered.assertForOverFulfill = false
        let downloader = ControlledViewImageDownloader { _ in XCTFail("Cache hit must not download") }
        let model = ImageViewProbeModel(url: url)
        let view = ImageViewProbe(model: model, cache: cache, loader: RemoteImageLoader(cache: cache, downloader: downloader)) {
            if $0 { rendered.fulfill() }
        }
        let window = try host(view)
        defer { window.isHidden = true }
        await fulfillment(of: [rendered], timeout: 2)
        try await Task.sleep(for: .milliseconds(100))
        let after = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(after, before)
    }

    func testURLChangeDiscardsLateCancelledImage() async throws {
        let first = try XCTUnwrap(URL(string: "https://images.example.org/first.png"))
        let second = try XCTUnwrap(URL(string: "https://images.example.org/second.png"))
        let firstStarted = expectation(description: "First download")
        let secondStarted = expectation(description: "Second download")
        let unexpectedImage = expectation(description: "Cancelled image must not render")
        unexpectedImage.isInverted = true
        let secondRendered = expectation(description: "Current image rendered")
        secondRendered.assertForOverFulfill = false
        var secondReleased = false
        let downloader = ControlledViewImageDownloader { url in
            (url == first ? firstStarted : secondStarted).fulfill()
        }
        let cache = RemoteImageCache(directory: nil)
        let model = ImageViewProbeModel(url: first)
        let view = ImageViewProbe(model: model, cache: cache, loader: RemoteImageLoader(cache: cache, downloader: downloader)) {
            guard $0 else { return }
            if secondReleased { secondRendered.fulfill() } else { unexpectedImage.fulfill() }
        }
        let window = try host(view)
        defer { window.isHidden = true }
        await fulfillment(of: [firstStarted], timeout: 2)
        model.url = second
        await fulfillment(of: [secondStarted], timeout: 2)
        await downloader.complete(first, data: png())
        await fulfillment(of: [unexpectedImage], timeout: 0.2)
        secondReleased = true
        await downloader.complete(second, data: png())
        await fulfillment(of: [secondRendered], timeout: 2)
    }

    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }

    private func host(_ view: some View) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }
}

@MainActor
private final class ImageViewProbeModel: ObservableObject {
    @Published var url: URL
    init(url: URL) { self.url = url }
}

private struct ImageViewProbe: View {
    @ObservedObject var model: ImageViewProbeModel
    let cache: RemoteImageCache
    let loader: RemoteImageLoader
    let changed: (Bool) -> Void

    var body: some View {
        CachedAsyncImage(url: model.url, cache: cache, loader: loader) { phase in
            Text(phase.image == nil ? "Pending" : "Loaded")
                .onChange(of: phase.image != nil, initial: true) { _, loaded in changed(loaded) }
        }
    }
}

private actor ControlledViewImageDownloader: RemoteImageDownloading {
    let started: @Sendable (URL) -> Void
    private var pending: [URL: CheckedContinuation<RemoteImageDownload, Never>] = [:]

    init(started: @escaping @Sendable (URL) -> Void) { self.started = started }

    func download(_ url: URL, maximumBytes _: Int) async -> RemoteImageDownload {
        await withCheckedContinuation { continuation in
            pending[url] = continuation
            started(url)
        }
    }

    func complete(_ url: URL, data: Data) {
        pending.removeValue(forKey: url)?.resume(returning: RemoteImageDownload(data: data, responseURL: url))
    }
}
