//
//  DAppRequestBannerTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// Exercises the host-extraction and field-fallback logic on `DAppMetadata`.
/// `DAppRequestBanner` is a pure render of these values, so testing the model
/// covers the banner's display behavior without standing up a SwiftUI host.
final class DAppRequestBannerTests: XCTestCase {

    // MARK: - host

    func testHostExtractsFromHTTPSURL() {
        let metadata = DAppMetadata(
            name: "Uniswap",
            url: "https://app.uniswap.org/swap",
            iconURL: ""
        )
        XCTAssertEqual(metadata.host, "app.uniswap.org")
    }

    func testHostExtractsFromHTTPURLWithPort() {
        let metadata = DAppMetadata(
            name: "Local",
            url: "http://localhost:3000/page",
            iconURL: ""
        )
        XCTAssertEqual(metadata.host, "localhost")
    }

    func testHostFallsBackToRawWhenNoSchemeParseable() {
        // `URL(string:)` returns a URL whose host is nil for bare strings — the
        // fallback should echo the raw input so the user still sees something
        // actionable.
        let metadata = DAppMetadata(
            name: "Site",
            url: "not-a-url",
            iconURL: ""
        )
        XCTAssertEqual(metadata.host, "not-a-url")
    }

    func testHostIsEmptyWhenURLIsEmpty() {
        let metadata = DAppMetadata(name: "X", url: "", iconURL: "")
        XCTAssertEqual(metadata.host, "")
    }

    // MARK: - isEmpty

    func testIsEmptyTrueWhenAllFieldsEmpty() {
        let metadata = DAppMetadata(name: "", url: "", iconURL: "")
        XCTAssertTrue(metadata.isEmpty)
    }

    func testIsEmptyFalseWhenAnyFieldPopulated() {
        XCTAssertFalse(DAppMetadata(name: "X", url: "", iconURL: "").isEmpty)
        XCTAssertFalse(DAppMetadata(name: "", url: "https://x", iconURL: "").isEmpty)
        XCTAssertFalse(DAppMetadata(name: "", url: "", iconURL: "https://x.png").isEmpty)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = DAppMetadata(
            name: "Uniswap",
            url: "https://app.uniswap.org",
            iconURL: "https://app.uniswap.org/favicon.png"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DAppMetadata.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
