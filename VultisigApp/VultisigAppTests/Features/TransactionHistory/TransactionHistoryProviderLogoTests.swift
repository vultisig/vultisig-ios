//
//  TransactionHistoryProviderLogoTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

/// End-to-end coverage of the tx-history `via {provider}` badge logo: the
/// persisted display string resolves, through `SwapProviderKind`, to the shared
/// brand-asset name. Exhaustive per-case coverage of the kind itself lives in
/// `SwapProviderKindTests`; this pins the Transaction History wiring.
final class TransactionHistoryProviderLogoTests: XCTestCase {

    private func swapProviderLogo(for swapProvider: String?) -> String? {
        Self.makeData(swapProvider: swapProvider).swapProviderLogo
    }

    func testThorchainFamilyMapsToThorchainAsset() {
        for name in ["THORChain", "THORChain-Chainnet", "THORChain-Stagenet"] {
            XCTAssertEqual(swapProviderLogo(for: name), "THORChain", "for \(name)")
        }
    }

    func testMayaBothCasingsMapToMayaProtocolAsset() {
        for name in ["Maya protocol", "Maya Protocol"] {
            XCTAssertEqual(swapProviderLogo(for: name), "Maya protocol", "for \(name)")
        }
    }

    func testOneInchMapsToOneInchAsset() {
        XCTAssertEqual(swapProviderLogo(for: "1Inch"), "1Inch")
    }

    func testKyberSwapMapsToKyberswapAsset() {
        XCTAssertEqual(swapProviderLogo(for: "KyberSwap"), "kyberswap")
    }

    func testLifiMapsToLifiAsset() {
        XCTAssertEqual(swapProviderLogo(for: "LI.FI"), "LI.FI")
    }

    func testSwapKitAndSubProvidersMapToSwapkitAsset() {
        for name in ["SwapKit", "SwapKit (Chainflip)", "SwapKit (NEAR Intents)"] {
            XCTAssertEqual(swapProviderLogo(for: name), "swapkit", "for \(name)")
        }
    }

    func testJupiterMapsToJupiterAsset() {
        XCTAssertEqual(swapProviderLogo(for: "Jupiter"), "jupiter")
    }

    func testNilOrEmptyMapsToNil() {
        XCTAssertNil(swapProviderLogo(for: nil))
        XCTAssertNil(swapProviderLogo(for: ""))
        XCTAssertNil(swapProviderLogo(for: "   "))
    }

    func testUnknownProviderMapsToNil() {
        XCTAssertNil(swapProviderLogo(for: "SomeUnknownProvider"))
    }

    // MARK: - Helper

    /// Minimal `TransactionHistoryData` fixture — `swapProviderLogo` depends only
    /// on `swapProvider`, so every other field is placeholder.
    private static func makeData(swapProvider: String?) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "",
            approveTxHash: nil,
            pubKeyECDSA: "",
            type: .swap,
            status: .successful,
            chainRawValue: "",
            coinTicker: "",
            coinLogo: "",
            coinChainLogo: nil,
            amountCrypto: "",
            amountFiat: "",
            fromAddress: "",
            toAddress: "",
            toCoinTicker: nil,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: nil,
            toAmountFiat: nil,
            swapProvider: swapProvider,
            feeCrypto: "",
            feeFiat: "",
            network: "",
            explorerLink: "",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil
        )
    }
}
