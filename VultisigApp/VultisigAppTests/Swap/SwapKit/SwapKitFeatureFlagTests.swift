//
//  SwapKitFeatureFlagTests.swift
//  VultisigAppTests
//
//  Locks the opt-in behaviour for SwapKit: the integration is off by
//  default; flipping the `swapkitEnabled` UserDefaults key (the same key
//  `SettingsViewModel.swapkitEnabled` writes to via `@AppStorage`) lights
//  it up. `Coin+Swaps.swapProviders` is the single point of gating.
//

import XCTest
@testable import VultisigApp

final class SwapKitFeatureFlagTests: XCTestCase {

    private let flagKey = "swapkitEnabled"
    private var savedValue: Any?

    override func setUpWithError() throws {
        savedValue = UserDefaults.standard.object(forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: flagKey)
    }

    override func tearDownWithError() throws {
        if let savedValue {
            UserDefaults.standard.set(savedValue, forKey: flagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: flagKey)
        }
    }

    // MARK: - isFeatureEnabled

    func testFeatureFlagDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: flagKey)
        XCTAssertFalse(
            SwapKitConfig.isFeatureEnabled,
            "SwapKit must be opt-in — default off while we smoke-test in production"
        )
    }

    func testFeatureFlagOnReadsTrue() {
        UserDefaults.standard.set(true, forKey: flagKey)
        XCTAssertTrue(SwapKitConfig.isFeatureEnabled)
    }

    func testFeatureFlagOffReadsFalse() {
        UserDefaults.standard.set(false, forKey: flagKey)
        XCTAssertFalse(SwapKitConfig.isFeatureEnabled)
    }

    // MARK: - Coin+Swaps gating

    func testSwapkitDroppedFromEthereumProvidersWhenFlagOff() {
        UserDefaults.standard.set(false, forKey: flagKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertFalse(
            providers.contains(.swapkit),
            "When the flag is off, `.swapkit` must not appear in Ethereum's provider list"
        )
        // Existing providers must still be intact — the flag only affects SwapKit.
        XCTAssertTrue(providers.contains(.lifi))
        XCTAssertTrue(providers.contains(.kyberswap(.ethereum)))
        XCTAssertTrue(providers.contains(.oneinch(.ethereum)))
    }

    func testSwapkitPresentInEthereumProvidersWhenFlagOn() {
        UserDefaults.standard.set(true, forKey: flagKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertTrue(
            providers.contains(.swapkit),
            "When the flag is on, Ethereum's provider list must include `.swapkit`"
        )
    }

    func testSwapkitDroppedFromSolanaProvidersWhenFlagOff() {
        UserDefaults.standard.set(false, forKey: flagKey)
        let providers = makeCoin(chain: .solana, ticker: "SOL").swapProviders
        XCTAssertFalse(providers.contains(.swapkit))
        XCTAssertTrue(providers.contains(.lifi))
        XCTAssertTrue(providers.contains(.thorchain))
    }

    func testFlagOffDoesNotAffectNonSwapKitChains() {
        // THORChain has no `.swapkit` arm in the switch (the SwapKit
        // integration explicitly filters THORChain/Maya routes upstream).
        // Toggling the flag must not change its provider list — pinned so a
        // future refactor doesn't drop it into the filter path.
        UserDefaults.standard.set(false, forKey: flagKey)
        let off = makeCoin(chain: .thorChain, ticker: "RUNE").swapProviders
        UserDefaults.standard.set(true, forKey: flagKey)
        let on = makeCoin(chain: .thorChain, ticker: "RUNE").swapProviders
        XCTAssertEqual(off, on)
    }

    // MARK: - Helpers

    private func makeCoin(chain: Chain, ticker: String) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "",
            decimals: 18,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "", hexPublicKey: "")
    }
}
