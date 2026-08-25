//
//  SwapKitFeatureFlagTests.swift
//  VultisigAppTests
//
//  Locks SwapKit provider availability and verifies that the
//  `forcedSwapProvider` debug picker still narrows the provider list.
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

    // MARK: - Coin+Swaps availability

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

    func testSwapkitIsAddedCentrallyToHyperEvmAndOtherHeldEvmChains() {
        XCTAssertTrue(makeCoin(chain: .hyperliquid, ticker: "HYPE").swapProviders.contains(.swapkit))
        XCTAssertTrue(makeCoin(chain: .cronosChain, ticker: "CRO").swapProviders.contains(.swapkit))
    }

    func testRobinhoodIsSwapKitDestinationOnly() {
        let ethereum = makeCoin(chain: .ethereum, ticker: "ETH")
        let robinhood = makeCoin(chain: .robinhood, ticker: "ETH")

        XCTAssertTrue(
            SwapCoinsResolver.resolveAllProviders(
                fromCoin: ethereum,
                toCoin: robinhood
            ).contains(.swapkit)
        )
        XCTAssertFalse(
            SwapCoinsResolver.resolveAllProviders(
                fromCoin: robinhood,
                toCoin: ethereum
            ).contains(.swapkit)
        )
    }

    func testHyperEvmCanOriginateSwapKitQuotes() {
        let hyperEvm = makeCoin(chain: .hyperliquid, ticker: "HYPE")
        let ethereum = makeCoin(chain: .ethereum, ticker: "ETH")

        XCTAssertTrue(
            SwapCoinsResolver.resolveAllProviders(
                fromCoin: hyperEvm,
                toCoin: ethereum
            ).contains(.swapkit)
        )
    }

    func testDestinationResolverDropsSwapKitOnlyCoinFromRobinhoodSource() {
        let robinhood = makeCoin(chain: .robinhood, ticker: "ETH")
        let ton = makeCoin(chain: .ton, ticker: "GRAM")
        let ethereum = makeCoin(chain: .ethereum, ticker: "ETH")

        let resolved = SwapCoinsResolver.resolveToCoins(
            fromCoin: robinhood,
            allCoins: [ton, ethereum],
            selectedToCoin: ton
        )

        XCTAssertEqual(resolved.coins, [ethereum])
        XCTAssertEqual(resolved.selected, ethereum)
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
        // Ripple has no 1inch route. Forcing 1inch produces
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
