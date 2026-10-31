//
//  MayaLPPoolsTests.swift
//  VultisigAppTests
//
//  Which MayaChain pools the app pairs. A paired CACAO add only completes when
//  the matching asset deposit can be sent from here, so every other pool stays a
//  single-sided add rather than sitting pending until it is refunded.
//

import XCTest
@testable import VultisigApp

final class MayaLPPoolsTests: XCTestCase {

    func testEachNativePoolIsFixedByItsChain() {
        XCTAssertEqual(MayaLPPools.nativePool(for: .bitcoin), "BTC.BTC")
        XCTAssertEqual(MayaLPPools.nativePool(for: .ethereum), "ETH.ETH")
        XCTAssertEqual(MayaLPPools.nativePool(for: .arbitrum), "ARB.ETH")
        XCTAssertEqual(MayaLPPools.nativePool(for: .dash), "DASH.DASH")
        XCTAssertEqual(MayaLPPools.nativePool(for: .zcash), "ZEC.ZEC")
    }

    func testAChainMayaDoesNotPoolHasNoNativePool() {
        XCTAssertNil(MayaLPPools.nativePool(for: .litecoin))
        XCTAssertNil(MayaLPPools.nativePool(for: .cardano))
        XCTAssertNil(MayaLPPools.nativePool(for: .mayaChain))
    }

    func testPoolsTheAppCanCompleteArePaired() {
        for pool in ["BTC.BTC", "ETH.ETH", "ARB.ETH", "DASH.DASH", "ZEC.ZEC", "eth.eth"] {
            XCTAssertTrue(MayaLPPools.isPairable(pool: pool), pool)
        }
    }

    func testERC20PoolsOnSupportedEVMChainsArePaired() {
        XCTAssertTrue(MayaLPPools.isPairable(pool: AddLPFixture.usdcPool))
        XCTAssertTrue(MayaLPPools.isPairable(pool: "ARB.USDC-0XAF88D065E77C8CC2239327C5EDB3A432268E5831"))
    }

    func testPoolsTheAppCannotCompleteStaySingleSided() {
        for pool in ["ADA.ADA", "MAYA.MAYA", "THOR.RUNE", "AVAX.AVAX", "", "BTC"] {
            XCTAssertFalse(MayaLPPools.isPairable(pool: pool), pool)
        }
    }

    func testThePoolResolvesTheChainThatHoldsItsAsset() {
        XCTAssertEqual(MayaLPPools.assetChain(ofPool: "ARB.ETH"), .arbitrum)
        XCTAssertEqual(MayaLPPools.assetChain(ofPool: AddLPFixture.usdcPool), .ethereum)
        XCTAssertNil(MayaLPPools.assetChain(ofPool: "ADA.ADA"))
    }
}
