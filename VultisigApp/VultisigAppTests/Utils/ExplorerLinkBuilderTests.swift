//
//  ExplorerLinkBuilderTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class ExplorerLinkBuilderTests: XCTestCase {

    private let mainnetChain = Chain.thorChain.rawValue
    private let stagenetChain = Chain.thorChainStagenet.rawValue
    private let fallback = "https://etherscan.io/tx/0xfallback"
    private let txHash = "0xABCDEF1234567890"

    // MARK: - Provider-specific routing

    func testLifiProviderReturnsLifiTracker() {
        let url = ExplorerLinkBuilder.url(
            provider: "LI.FI",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, "https://scan.li.fi/tx/\(txHash)")
    }

    func testMayaProviderReturnsMayaExplorer() {
        let url = ExplorerLinkBuilder.url(
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
        let url = ExplorerLinkBuilder.url(
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
        let url = ExplorerLinkBuilder.url(
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
        let url = ExplorerLinkBuilder.url(
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

    func testUnknownProviderFallsBackToChainExplorer() {
        // chainRawValue resolves to .thorChain — fallback derives the URL from
        // ExplorerLinkBuilder.getExplorerURL, NOT the stored explorerLink, so it stays in
        // sync with the rest of the app even if the stored link is stale.
        let url = ExplorerLinkBuilder.url(
            provider: "1Inch",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .thorChain, txid: txHash)
        )
    }

    func testKyberSwapFallsBackToChainExplorer() {
        let ethereumChain = Chain.ethereum.rawValue
        let url = ExplorerLinkBuilder.url(
            provider: "KyberSwap",
            txHash: txHash,
            chainRawValue: ethereumChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .ethereum, txid: txHash)
        )
    }

    func testNilProviderFallsBackToChainExplorer() {
        let ethereumChain = Chain.ethereum.rawValue
        let url = ExplorerLinkBuilder.url(
            provider: nil,
            txHash: txHash,
            chainRawValue: ethereumChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .ethereum, txid: txHash)
        )
    }

    func testUnresolvableChainRawValueFallsBackToStoredExplorerLink() {
        // Last-ditch safety net: if chainRawValue can't be parsed back to a
        // Chain (e.g. legacy data, deprecated chain), use the stored link.
        let url = ExplorerLinkBuilder.url(
            provider: nil,
            txHash: txHash,
            chainRawValue: "not-a-real-chain",
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(url?.absoluteString, fallback)
    }

    // MARK: - Case- and spacing-insensitive matching

    func testLifiMatchingIsCaseInsensitive() {
        let variants = ["LI.FI", "li.fi", "Lifi", "LIFI", "Li.Fi", "li fi"]
        for variant in variants {
            let url = ExplorerLinkBuilder.url(
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
            let url = ExplorerLinkBuilder.url(
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
            let url = ExplorerLinkBuilder.url(
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

    // MARK: - Real-world displayName / providerName values

    /// `SwapQuote.displayName` returns "Maya protocol" (lowercase p) and
    /// `SwapPayload.providerName` returns "Maya Protocol" (capital P). For a
    /// cross-chain swap (e.g. BTC→Maya) `chainRawValue` is the from-chain, so
    /// without an explicit alias the fallback would route to the wrong chain
    /// explorer (mempool.space for BTC). Lock the alias in.
    func testMayaProtocolDisplayNameRoutesToMayaExplorer() {
        let bitcoinChain = Chain.bitcoin.rawValue
        let lowercase = ExplorerLinkBuilder.url(
            provider: "Maya protocol",
            txHash: txHash,
            chainRawValue: bitcoinChain,
            fallbackExplorerLink: fallback
        )
        let capital = ExplorerLinkBuilder.url(
            provider: "Maya Protocol",
            txHash: txHash,
            chainRawValue: bitcoinChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            lowercase?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
        XCTAssertEqual(
            capital?.absoluteString,
            "https://www.explorer.mayachain.info/tx/ABCDEF1234567890"
        )
    }

    func testThorChainStagenetDisplayNameRoutesToStagenetTracker() {
        // Stagenet alias must work even when chainRawValue isn't the stagenet
        // raw value (e.g. cross-chain stagenet swap).
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain-Stagenet",
            txHash: txHash,
            chainRawValue: Chain.bitcoin.rawValue,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890?network=stagenet"
        )
    }

    func testThorChainChainnetDisplayNameRoutesToThorchainTracker() {
        let url = ExplorerLinkBuilder.url(
            provider: "THORChain-Chainnet",
            txHash: txHash,
            chainRawValue: mainnetChain,
            fallbackExplorerLink: fallback
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://runescan.io/tx/ABCDEF1234567890"
        )
    }
}
