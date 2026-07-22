//
//  TransactionHistoryProviderLogoTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TransactionHistoryProviderLogoTests: XCTestCase {

    func testThorchainFamilyMapsToThorchainAsset() {
        for name in ["THORChain", "THORChain-Chainnet", "THORChain-Stagenet"] {
            XCTAssertEqual(
                TransactionHistoryData.providerLogoAsset(for: name),
                "THORChain",
                "expected THORChain asset for \(name)"
            )
        }
    }

    func testMayaBothCasingsMapToMayaProtocolAsset() {
        for name in ["Maya protocol", "Maya Protocol"] {
            XCTAssertEqual(
                TransactionHistoryData.providerLogoAsset(for: name),
                "Maya protocol",
                "expected Maya protocol asset for \(name)"
            )
        }
    }

    func testOneInchMapsToOneInchAsset() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "1Inch"), "1Inch")
    }

    func testKyberSwapMapsToKyberswapAsset() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "KyberSwap"), "kyberswap")
    }

    func testLifiMapsToLifiAsset() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "LI.FI"), "LI.FI")
    }

    func testSwapKitAndSubProvidersMapToSwapkitAsset() {
        for name in ["SwapKit", "SwapKit (Chainflip)", "SwapKit (NEAR Intents)"] {
            XCTAssertEqual(
                TransactionHistoryData.providerLogoAsset(for: name),
                "swapkit",
                "expected swapkit asset for \(name)"
            )
        }
    }

    func testJupiterMapsToJupiterAsset() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "Jupiter"), "jupiter")
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "thorchain"), "THORChain")
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "JUPITER"), "jupiter")
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(TransactionHistoryData.providerLogoAsset(for: "  SwapKit  "), "swapkit")
    }

    func testNilOrEmptyMapsToNil() {
        XCTAssertNil(TransactionHistoryData.providerLogoAsset(for: nil))
        XCTAssertNil(TransactionHistoryData.providerLogoAsset(for: ""))
        XCTAssertNil(TransactionHistoryData.providerLogoAsset(for: "   "))
    }

    func testUnknownProviderMapsToNil() {
        XCTAssertNil(TransactionHistoryData.providerLogoAsset(for: "SomeUnknownProvider"))
    }
}
