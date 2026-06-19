//
//  NativePoolEligibilityWiringTests.swift
//  VultisigAppTests
//
//  The UNION rule wired into Coin.swapProviders(thorPools:mayaPools:): live
//  `Available` pools ADD native routes; the static fallback is never subtracted;
//  cold start (nil snapshots) is byte-identical to today.
//

import XCTest
@testable import VultisigApp

final class NativePoolEligibilityWiringTests: XCTestCase {

    private let forcedKey = "forcedSwapProvider"
    private var savedForced: Any?

    override func setUpWithError() throws {
        savedForced = UserDefaults.standard.object(forKey: forcedKey)
        UserDefaults.standard.removeObject(forKey: forcedKey)
    }

    override func tearDownWithError() throws {
        if let savedForced {
            UserDefaults.standard.set(savedForced, forKey: forcedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: forcedKey)
        }
    }

    // MARK: - Acceptance #1: CACAO → ETH.USDT (Maya gains USDT though the static array lacks it)

    func testCacaoToEthUsdtBecomesEligibleFromFetchedPool() {
        let usdt = makeCoin(.ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isNative: false)
        // Static fallback: mayaEthTokens = ["ETH", "USDC"] — USDT absent.
        XCTAssertFalse(usdt.swapProviders.contains(.mayachain))

        let mayaPools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isAvailable: true, isTradingHalted: false)
        ]
        let dynamic = usdt.swapProviders(thorPools: nil, mayaPools: mayaPools)
        XCTAssertTrue(dynamic.contains(.mayachain), "Live Available Maya pool must add .mayachain for ETH.USDT")
    }

    func testEthMocaEligibleFromFetchedPoolWithoutCodeChange() {
        let moca = makeCoin(.ethereum, ticker: "MOCA", contract: "0x53312f85bba24c8cb99cffc13bf82420157230d3", isNative: false)
        XCTAssertFalse(moca.swapProviders.contains(.mayachain))

        let mayaPools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "MOCA", contract: "0x53312f85bba24c8cb99cffc13bf82420157230d3", isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertTrue(moca.swapProviders(thorPools: nil, mayaPools: mayaPools).contains(.mayachain))
    }

    // MARK: - Cold start parity (regression pin per chain)

    func testColdStartWithNoFetchMatchesStaticFallback() {
        let coins: [Coin] = [
            makeCoin(.ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isNative: false),
            makeCoin(.ethereum, ticker: "ETH"),
            makeCoin(.bscChain, ticker: "USDT", contract: "0x55d398", isNative: false),
            makeCoin(.avalanche, ticker: "USDC", contract: "0xb97ef9", isNative: false),
            makeCoin(.arbitrum, ticker: "ARB", contract: "0x912ce5", isNative: false),
            makeCoin(.base, ticker: "USDC", contract: "0x833589", isNative: false)
        ]
        for coin in coins {
            XCTAssertEqual(
                coin.swapProviders(thorPools: nil, mayaPools: nil),
                coin.swapProviders,
                "Cold start must equal the static provider set for \(coin.chain)/\(coin.ticker)"
            )
        }
    }

    // MARK: - UNION: a fetch only ADDS, never removes a fallback route

    func testFetchOnlyAddsNeverRemovesFallbackRoute() {
        // WBTC is in thorEthTokens (static fallback) but absent from the live fetch.
        let wbtc = makeCoin(.ethereum, ticker: "WBTC", contract: "0x2260fa", isNative: false)
        XCTAssertTrue(wbtc.swapProviders.contains(.thorchain))

        // Live THOR fetch returns only USDC — does not include WBTC.
        let thorPools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDC", contract: "0xa0b8", isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertTrue(
            wbtc.swapProviders(thorPools: thorPools, mayaPools: nil).contains(.thorchain),
            "A fallback route must survive a fetch that omits it (UNION, not replacement)"
        )
    }

    // MARK: - Collision: a foreign same-ticker contract is not eligible

    func testForeignContractSameTickerNotEligible() {
        let scamUsdt = makeCoin(.ethereum, ticker: "USDT", contract: "0xdeadbeef00000000000000000000000000000000", isNative: false)
        let mayaPools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isAvailable: true, isTradingHalted: false)
        ]
        XCTAssertFalse(
            scamUsdt.swapProviders(thorPools: nil, mayaPools: mayaPools).contains(.mayachain),
            "A same-ticker coin with a different contract must not borrow the pool's eligibility"
        )
    }

    func testStagedPoolDoesNotAddRoute() {
        let yfi = makeCoin(.ethereum, ticker: "YFI", contract: "0x0bc529", isNative: false)
        XCTAssertFalse(yfi.swapProviders.contains(.thorchain))
        let thorPools = [
            NativePoolAsset(poolChain: .ethereum, ticker: "YFI", contract: "0x0bc529", isAvailable: false, isTradingHalted: false)
        ]
        XCTAssertFalse(
            yfi.swapProviders(thorPools: thorPools, mayaPools: nil).contains(.thorchain),
            "A Staged pool must not add a route"
        )
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, contract: String = "", isNative: Bool = true) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "", hexPublicKey: "")
    }
}
