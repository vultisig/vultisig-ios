//
//  SwapKitFeatureFlagTests.swift
//  VultisigAppTests
//
//  Locks the shipped behaviour for SwapKit: the integration is enabled for
//  everyone now that the former Settings → Advanced opt-out toggle has been
//  removed. `Coin+Swaps.swapProviders` is the single point of gating, and
//  the `forcedSwapProvider` debug picker still narrows the provider list.
//

import XCTest
@testable import VultisigApp

final class SwapKitFeatureFlagTests: XCTestCase {

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

    // MARK: - isFeatureEnabled

    func testFeatureFlagIsAlwaysEnabled() {
        XCTAssertTrue(
            SwapKitConfig.isFeatureEnabled,
            "SwapKit has shipped — the feature is always enabled"
        )
    }

    // MARK: - Coin+Swaps gating

    func testSwapkitPresentInEthereumProviders() {
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertTrue(
            providers.contains(.swapkit),
            "Ethereum's provider list must include `.swapkit`"
        )
        XCTAssertTrue(providers.contains(.lifi))
        XCTAssertTrue(providers.contains(.kyberswap(.ethereum)))
        XCTAssertTrue(providers.contains(.oneinch(.ethereum)))
    }

    func testSwapkitPresentInSolanaProviders() {
        let providers = makeCoin(chain: .solana, ticker: "SOL").swapProviders
        XCTAssertTrue(providers.contains(.swapkit))
        XCTAssertTrue(providers.contains(.lifi))
        XCTAssertTrue(providers.contains(.thorchain))
    }

    // MARK: - Forced swap provider (debug picker)

    func testForcedProviderDefaultPreservesAllProviders() {
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
        UserDefaults.standard.set("swapkit", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.swapkit])
    }

    func testForcedOneInchFiltersOutOthers() {
        UserDefaults.standard.set("oneInch", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.oneinch(.ethereum)])
    }

    func testForcedKyberFiltersOutOthers() {
        UserDefaults.standard.set("kyberSwap", forKey: forcedKey)
        let providers = makeCoin(chain: .ethereum, ticker: "ETH").swapProviders
        XCTAssertEqual(providers, [.kyberswap(.ethereum)])
    }

    func testForcedLiFiFiltersOutOthers() {
        UserDefaults.standard.set("lifi", forKey: forcedKey)
        let providers = makeCoin(chain: .solana, ticker: "SOL").swapProviders
        XCTAssertEqual(providers, [.lifi])
    }

    func testForcedThorchainKeepsAllThreeVariants() {
        // The "thorchain" force token matches all three THORChain network
        // variants (.thorchain / .thorchainChainnet / .thorchainStagenet)
        // so a tester debugging THORChain doesn't have to know which
        // network variant Vultisig is configured for.
        UserDefaults.standard.set("thorchain", forKey: forcedKey)
        let btc = makeCoin(chain: .bitcoin, ticker: "BTC").swapProviders
        XCTAssertEqual(btc, [.thorchain])
    }

    func testForcedProviderNotEligibleForChainReturnsEmpty() {
        // Ripple has only [.thorchain] naturally. Forcing 1inch produces
        // an empty list — Vultisig won't route through a provider that
        // doesn't support the chain at all.
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
