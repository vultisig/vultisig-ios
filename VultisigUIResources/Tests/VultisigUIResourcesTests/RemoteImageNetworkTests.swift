import Foundation
import XCTest
@testable import VultisigUIResources

// The standalone downloader owns its network session; URLProtocol keeps these tests entirely offline.
// swiftlint:disable no_raw_urlrequest
final class RemoteImageNetworkTests: XCTestCase {
    func testStreamingBodyLimitWithoutContentLength() async {
        await assertError(path: "oversized-body", expected: .tooLarge)
    }

    func testAdvertisedContentLengthLimit() async {
        await assertError(path: "oversized-header", expected: .tooLarge)
    }

    func testHTTPErrorStatus() async {
        await assertError(path: "error-status", expected: .invalidResponse)
    }

    func testInvalidFinalURL() async {
        await assertError(path: "bad-final", expected: .invalidResponse)
    }

    func testRealSessionRejectsHTTPRedirect() async {
        let before = RemoteImageURLProtocol.insecureRequests.value
        await assertError(path: "redirect-http", expected: .invalidResponse)
        XCTAssertEqual(RemoteImageURLProtocol.insecureRequests.value, before)
    }

    func testRealSessionFollowsHTTPSRedirect() async throws {
        let result = try await downloader().download(URL(string: "https://images.example.com/redirect-https")!, maximumBytes: 1_024)
        XCTAssertEqual(result.responseURL.absoluteString, "https://images.example.com/success")
        XCTAssertEqual(result.data, Data([1, 2, 3]))
    }

    private func assertError(path: String, expected: RemoteImageError) async {
        do {
            _ = try await downloader().download(URL(string: "https://images.example.com/\(path)")!, maximumBytes: 1_024)
            XCTFail("Expected \(expected)")
        } catch { XCTAssertEqual(error as? RemoteImageError, expected) }
    }

    private func downloader() -> HTTPSImageDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteImageURLProtocol.self]
        return HTTPSImageDownloader(configuration: configuration)
    }
}

private class RemoteImageURLProtocol: URLProtocol, @unchecked Sendable {
    static let insecureRequests = RequestCounter()
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.scheme == "http" { Self.insecureRequests.increment() }
        if url.path.hasPrefix("/redirect-") {
            let scheme = url.path == "/redirect-http" ? "http" : "https"
            let target = URL(string: "\(scheme)://images.example.com/success")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            if scheme == "http" {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        let responseURL = url.path == "/bad-final" ? URL(string: "http://images.example.com/success")! : url
        let status = url.path == "/error-status" ? 404 : 200
        let headers = url.path == "/oversized-header" ? ["Content-Length": "2048"] : [:]
        let response = HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path == "/oversized-body" {
            for _ in 0..<3 { client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 512)) }
        } else {
            client?.urlProtocol(self, didLoad: Data([1, 2, 3]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
// swiftlint:enable no_raw_urlrequest
