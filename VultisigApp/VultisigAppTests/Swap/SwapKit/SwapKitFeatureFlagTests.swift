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
    private let forcedKey = "forcedSwapProvider"
    private var savedFlag: Any?
    private var savedForced: Any?

    override func setUpWithError() throws {
        savedFlag = UserDefaults.standard.object(forKey: flagKey)
        savedForced = UserDefaults.standard.object(forKey: forcedKey)
        UserDefaults.standard.removeObject(forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: forcedKey)
    }

    override func tearDownWithError() throws {
        if let savedFlag {
            UserDefaults.standard.set(savedFlag, forKey: flagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: flagKey)
        }
        if let savedForced {
            UserDefaults.standard.set(savedForced, forKey: forcedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: forcedKey)
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

    // MARK: - Forced swap provider (debug picker)

    func testForcedProviderDefaultPreservesAllProviders() {
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.removeObject(forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        // Default (empty string) → no force. Production ranking sees the
        // full list — SwapKit + 1inch + Kyber + LiFi.
        XCTAssertTrue(providers.contains(.swapkit))
        XCTAssertTrue(providers.contains(.lifi))
        XCTAssertTrue(providers.contains(.oneinch(.ethereum)))
        XCTAssertTrue(providers.contains(.kyberswap(.ethereum)))
    }

    func testForcedSwapKitFiltersOutOthers() {
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("swapkit", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.swapkit])
    }

    func testForcedOneInchFiltersOutOthers() {
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("oneInch", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.oneinch(.ethereum)])
    }

    func testForcedKyberFiltersOutOthers() {
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("kyberSwap", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.kyberswap(.ethereum)])
    }

    func testForcedLiFiFiltersOutOthers() {
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("lifi", forKey: forcedKey)
        let providers = makeCoin(chain: .solana, ticker: "SOL").swapProviders
        XCTAssertEqual(providers, [.lifi])
    }

    func testForcedThorchainKeepsAllThreeVariants() {
        // The "thorchain" force token matches all three THORChain network
        // variants (.thorchain / .thorchainChainnet / .thorchainStagenet)
        // so a tester debugging THORChain doesn't have to know which
        // network variant Vultisig is configured for.
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("thorchain", forKey: forcedKey)
        let btc = makeCoin(chain: .bitcoin, ticker: "BTC").swapProviders
        XCTAssertEqual(btc, [.thorchain])
    }

    func testForcedSwapKitWithFeatureFlagOffReturnsEmpty() {
        // The SwapKit flag still takes precedence — if SwapKit is off
        // globally, forcing it produces an empty array (no fallback to
        // any other provider). The tester sees "no providers" in the UI
        // instead of silently routing through a different provider.
        UserDefaults.standard.set(false, forKey: flagKey)
        UserDefaults.standard.set("swapkit", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertTrue(providers.isEmpty)
    }

    func testForcedProviderNotEligibleForChainReturnsEmpty() {
        // Ripple has only [.thorchain] naturally. Forcing 1inch produces
        // an empty list — Vultisig won't route through a provider that
        // doesn't support the chain at all.
        UserDefaults.standard.set(true, forKey: flagKey)
        UserDefaults.standard.set("oneInch", forKey: forcedKey)
        let providers = makeCoin(chain: .ripple, ticker: "XRP").swapProviders
        XCTAssertTrue(providers.isEmpty)
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
