//
//  JupiterRoutingTests.swift
//  VultisigAppTests
//
//  Routing + provider-plumbing coverage for the Jupiter Solana swap provider:
//  the `.solana` natural-provider list, the same-chain-only intersection,
//  forced-provider gating, the `SwapProviderId` wire round-trip, and the
//  deterministic `JupiterService` / `JupiterQuoteParams` helpers.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class JupiterRoutingTests: XCTestCase {

    private let forcedProviderKey = "forcedSwapProvider"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: forcedProviderKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: forcedProviderKey)
        super.tearDown()
    }

    // MARK: - Natural provider list

    func testSolanaCoinOffersJupiter() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        XCTAssertEqual(sol.swapProviders, [.thorchain, .jupiter, .lifi, .swapkit])
    }

    func testNonSolanaCoinNeverOffersJupiter() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertFalse(eth.swapProviders.contains(.jupiter))
    }

    // MARK: - Same-chain-only intersection

    func testSolToSplResolvesJupiter() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        let usdc = makeSplUSDC()
        let providers = SwapCoinsResolver.resolveAllProviders(fromCoin: sol, toCoin: usdc)
        XCTAssertTrue(providers.contains(.jupiter), "SOL↔SPL stays on Solana → Jupiter eligible")
    }

    func testSplToSplResolvesJupiter() {
        let usdc = makeSplUSDC()
        let bonk = makeCoin(
            .solana, ticker: "BONK", decimals: 5, isNative: false,
            contract: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        )
        let providers = SwapCoinsResolver.resolveAllProviders(fromCoin: usdc, toCoin: bonk)
        XCTAssertTrue(providers.contains(.jupiter), "SPL↔SPL stays on Solana → Jupiter eligible")
    }

    func testSolToEthDropsJupiter() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let providers = SwapCoinsResolver.resolveAllProviders(fromCoin: sol, toCoin: eth)
        XCTAssertFalse(providers.contains(.jupiter), "Cross-chain drops Jupiter via the from∩to intersection")
        XCTAssertTrue(providers.contains(.thorchain), "THORChain stays for cross-chain Solana routes")
    }

    // MARK: - Forced-provider gate

    func testForcedJupiterFiltersToJupiterOnly() {
        UserDefaults.standard.set("jupiter", forKey: forcedProviderKey)
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        XCTAssertEqual(sol.swapProviders, [.jupiter])
    }

    // MARK: - SwapProviderId wire round-trip

    func testSwapProviderIdJupiterWireMapping() {
        XCTAssertEqual(SwapProviderId.jupiter.rawValue, "jupiter")
        XCTAssertEqual(SwapProviderId.jupiter.name, "Jupiter")
        XCTAssertEqual(SwapProviderId.from(rawValue: "jupiter"), .jupiter)
    }

    func testSwapProviderIdJupiterCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(SwapProviderId.jupiter)
        let decoded = try JSONDecoder().decode(SwapProviderId.self, from: data)
        XCTAssertEqual(decoded, .jupiter)
    }

    // MARK: - JupiterService helpers

    func testJupiterMintMapsNativeSolToWrappedSol() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        XCTAssertEqual(JupiterService().jupiterMint(for: sol), JupiterService.wrappedSolMint)
    }

    func testJupiterMintMapsSplToContractAddress() {
        let usdc = makeSplUSDC()
        XCTAssertEqual(JupiterService().jupiterMint(for: usdc), usdc.contractAddress)
    }

    func testPlatformFeeBpsAppliesDiscountWithFloor() {
        XCTAssertEqual(JupiterService.platformFeeBps(vultTierDiscount: 0), 50)
        XCTAssertEqual(JupiterService.platformFeeBps(vultTierDiscount: 20), 30)
        XCTAssertEqual(JupiterService.platformFeeBps(vultTierDiscount: 50), 0)
        XCTAssertEqual(JupiterService.platformFeeBps(vultTierDiscount: 80), 0, "Floored at 0")
    }

    func testFeeMintUsesInputForNativeSolOutput() {
        let wsol = JupiterService.wrappedSolMint
        let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        // SPL output → fee on the output mint (spec default).
        XCTAssertEqual(JupiterService.feeMint(inputMint: wsol, outputMint: usdc), usdc)
        // Native-SOL (wrapped SOL) output → fee on the INPUT mint, so we don't
        // need a wSOL fee ATA and never accrue fees in wSOL.
        XCTAssertEqual(JupiterService.feeMint(inputMint: usdc, outputMint: wsol), usdc)
    }

    // MARK: - Quote params

    func testQuoteParamsIncludesPlatformFeeWhenPositive() {
        let params = JupiterQuoteParams(
            inputMint: "in", outputMint: "out", amount: "1000", slippageBps: 50, platformFeeBps: 30
        )
        XCTAssertEqual(params.queryItems["platformFeeBps"] as? Int, 30)
    }

    func testQuoteParamsOmitsPlatformFeeWhenZeroOrNil() {
        let zero = JupiterQuoteParams(
            inputMint: "in", outputMint: "out", amount: "1000", slippageBps: 50, platformFeeBps: 0
        )
        XCTAssertNil(zero.queryItems["platformFeeBps"], "Zero fee must not be sent")

        let none = JupiterQuoteParams(
            inputMint: "in", outputMint: "out", amount: "1000", slippageBps: 50, platformFeeBps: nil
        )
        XCTAssertNil(none.queryItems["platformFeeBps"])
    }

    // MARK: - Fixtures

    private func makeSplUSDC() -> Coin {
        makeCoin(
            .solana, ticker: "USDC", decimals: 6, isNative: false,
            contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
