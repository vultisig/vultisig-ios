//
//  NativePoolAssetTests.swift
//  VultisigAppTests
//
//  Pool-id parsing + the synchronous eligibility predicate (the contract-match
//  collision rule). Pure, no I/O.
//

import XCTest
@testable import VultisigApp

final class NativePoolAssetTests: XCTestCase {

    // MARK: - parse

    func testParseEthErc20EmbedsTickerAndLowercasedContract() {
        let pool = NativePoolAsset.parse(
            assetId: "ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7",
            status: "Available",
            tradingHalted: false
        )
        XCTAssertEqual(pool?.poolChain, .ethereum)
        XCTAssertEqual(pool?.ticker, "USDT")
        XCTAssertEqual(pool?.contract, "0xdac17f958d2ee523a2206206994597c13d831ec7")
        XCTAssertEqual(pool?.isAvailable, true)
    }

    func testParseL1NativeHasNilContract() {
        let pool = NativePoolAsset.parse(assetId: "ETH.ETH", status: "Available", tradingHalted: nil)
        XCTAssertEqual(pool?.poolChain, .ethereum)
        XCTAssertEqual(pool?.ticker, "ETH")
        XCTAssertNil(pool?.contract)
        XCTAssertEqual(pool?.isTradingHalted, false)
    }

    func testParseArbAndBaseAndBscAndAvaxPrefixes() {
        XCTAssertEqual(
            NativePoolAsset.parse(assetId: "ARB.LEO-0x93864d81175095dd93360ffa2a529b8642f76a6e", status: "Available", tradingHalted: nil)?.poolChain,
            .arbitrum
        )
        XCTAssertEqual(
            NativePoolAsset.parse(assetId: "BASE.USDC-0x833589", status: "Available", tradingHalted: nil)?.poolChain,
            .base
        )
        XCTAssertEqual(
            NativePoolAsset.parse(assetId: "BSC.USDT-0x55d398", status: "Available", tradingHalted: nil)?.poolChain,
            .bscChain
        )
        XCTAssertEqual(
            NativePoolAsset.parse(assetId: "AVAX.USDC-0xb97ef9", status: "Available", tradingHalted: nil)?.poolChain,
            .avalanche
        )
    }

    func testParseUnknownPrefixReturnsNil() {
        XCTAssertNil(NativePoolAsset.parse(assetId: "DOT.DOT", status: "Available", tradingHalted: nil))
        XCTAssertNil(NativePoolAsset.parse(assetId: "NOTACHAIN.FOO-0x1", status: "Available", tradingHalted: nil))
    }

    func testParseMalformedReturnsNil() {
        XCTAssertNil(NativePoolAsset.parse(assetId: "ETH", status: "Available", tradingHalted: nil))
        XCTAssertNil(NativePoolAsset.parse(assetId: "", status: "Available", tradingHalted: nil))
        XCTAssertNil(NativePoolAsset.parse(assetId: "ETH.", status: "Available", tradingHalted: nil))
    }

    func testParseStagedIsNotAvailable() {
        let pool = NativePoolAsset.parse(assetId: "ETH.WSTETH-0x7f39", status: "Staged", tradingHalted: nil)
        XCTAssertEqual(pool?.isAvailable, false)
    }

    func testParseAvailableCaseInsensitive() {
        let pool = NativePoolAsset.parse(assetId: "ETH.ETH", status: "available", tradingHalted: nil)
        XCTAssertEqual(pool?.isAvailable, true)
    }

    func testParseNilStatusIsNotAvailable() {
        let pool = NativePoolAsset.parse(assetId: "ETH.ETH", status: nil, tradingHalted: nil)
        XCTAssertEqual(pool?.isAvailable, false)
    }

    func testParseThorTradingHaltedFlag() {
        let pool = NativePoolAsset.parse(assetId: "ETH.USDC-0xa0b8", status: "Available", tradingHalted: true)
        XCTAssertEqual(pool?.isTradingHalted, true)
    }

    // MARK: - isEligible

    func testIsEligibleTickerMatchForNative() {
        let pools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "ETH", contract: nil, isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertTrue(NativePoolEligibility.isEligible(chain: .ethereum, ticker: "ETH", contract: nil, in: pools))
    }

    func testIsEligibleRequiresContractMatchWhenPoolHasContract() {
        let pools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertTrue(
            NativePoolEligibility.isEligible(
                chain: .ethereum, ticker: "USDT",
                contract: "0xDAC17F958D2EE523A2206206994597C13D831EC7",
                in: pools
            )
        )
    }

    func testIsEligibleRejectsForeignContractSameTicker() {
        let pools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertFalse(
            NativePoolEligibility.isEligible(
                chain: .ethereum, ticker: "USDT",
                contract: "0xdeadbeef00000000000000000000000000000000",
                in: pools
            )
        )
    }

    func testIsEligibleRejectsStagedPool() {
        let pools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xabc", isAvailable: false, isTradingHalted: false)
        ]
        XCTAssertFalse(NativePoolEligibility.isEligible(chain: .ethereum, ticker: "USDT", contract: "0xabc", in: pools))
    }

    func testIsEligibleRejectsWrongChain() {
        let pools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDC", contract: nil, isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertFalse(NativePoolEligibility.isEligible(chain: .arbitrum, ticker: "USDC", contract: nil, in: pools))
    }
}
