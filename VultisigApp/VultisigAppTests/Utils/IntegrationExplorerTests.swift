//
//  IntegrationExplorerTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class IntegrationExplorerTests: XCTestCase {

    private let mainnetChain = Chain.thorChain.rawValue
    private let stagenetChain = Chain.thorChainStagenet.rawValue
    private let fallback = "https://etherscan.io/tx/0xfallback"
    private let txHash = "0xABCDEF1234567890"

    // MARK: - Provider-specific routing

    func testLifiProviderReturnsLifiTracker() {
        let url = IntegrationExplorer.url(
            provider: "LI.FI",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, "https://scan.li.fi/tx/\(txHash)")
    }

    func testMayaProviderReturnsMayaExplorer() {
        let url = IntegrationExplorer.url(
            provider: "MayaChain",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        // Maya tracker strips the hex prefix.
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
    }

    func testThorChainMainnetReturnsRuneScan() {
        let url = IntegrationExplorer.url(
            provider: "THORChain",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        // RuneScan tracker strips the hex prefix.
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890"
        )
    }

    func testThorChainStagenetReturnsStagenetRuneScan() {
        let url = IntegrationExplorer.url(
            provider: "THORChain",
            txHash: txHash,
            chainRawValue: stagenetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=stagenet"
        )
    }

    func testThorSwapAliasIsTreatedAsThorChain() {
        let url = IntegrationExplorer.url(
            provider: "THORSwap",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890"
        )
    }

    // MARK: - Fallback behaviour

    func testUnknownProviderFallsBackToExplorerLink() {
        let url = IntegrationExplorer.url(
            provider: "1Inch",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, fallback)
    }

    func testKyberSwapFallsBackToExplorerLink() {
        let url = IntegrationExplorer.url(
            provider: "KyberSwap",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, fallback)
    }

    func testNilProviderFallsBackToExplorerLink() {
        let url = IntegrationExplorer.url(
            provider: nil,
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, fallback)
    }

    // MARK: - Case- and spacing-insensitive matching

    func testLifiMatchingIsCaseInsensitive() {
        let variants = ["LI.FI", "li.fi", "Lifi", "LIFI", "Li.Fi", "li fi"]
        for variant in variants {
            let url = IntegrationExplorer.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://scan.li.fi/tx/\(txHash)",
                "Expected LiFi tracker for variant \(variant)"
            )
        }
    }

    func testThorChainMatchingIsCaseInsensitive() {
        let variants = ["thorchain", "THORCHAIN", "ThorChain", "THOR Chain"]
        for variant in variants {
            let url = IntegrationExplorer.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://runescan.io/tx/ABCDEF1234567890",
                "Expected RuneScan for variant \(variant)"
            )
        }
    }

    func testMayaMatchingIsCaseInsensitive() {
        let variants = ["maya", "MAYA", "Maya", "MayaChain", "maya chain"]
        for variant in variants {
            let url = IntegrationExplorer.url(
                provider: variant,
                txHash: txHash,
                chainRawValue: mainnetChain,
                fallbackExplorerLink: fallback
            )
            XCTAssertEqual(
                url?.absoluteString,
                "https://www.explorer.mayachain.info/tx/ABCDEF1234567890",
                "Expected Maya explorer for variant \(variant)"
            )
        }
    }
}
