//
//  SwapKitServiceInboundFeeTests.swift
//  VultisigAppTests
//
//  Pins the SwapKit source-chain network fee extraction. SwapKit surfaces
//  the source-chain inbound fee as the `fees[]` entry with
//  `type == "inbound"` and `chain` matching the canonical SwapKit prefix
//  for the source coin's chain. The amount is a decimal string in the
//  native unit (e.g. "0.000005" SOL). `SwapKitService.inboundFee` converts
//  it to raw `BigInt`, which feeds:
//
//    * `validateForm` (Continue button lights up only when fee != .zero)
//    * `balanceError`'s gas-coin sufficiency check (`fromFee > feeCoinBalance`)
//
//  A regression here either disables Continue silently or lets a swap
//  through despite insufficient gas — both visible only in live testing.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitServiceInboundFeeTests: XCTestCase {

    private let service = SwapKitService()

    func testEvmInboundFeeParsedAsWei() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let fee = service.inboundFee(from: response, fromCoin: eth)
        // Fixture: "0.000098846611703085" ETH at 18 decimals → 98_846_611_703_085 wei.
        XCTAssertEqual(fee, BigInt("98846611703085"))
    }

    func testSolanaInboundFeeParsedAsLamports() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9)
        let fee = service.inboundFee(from: response, fromCoin: sol)
        // Fixture: "0.000005" SOL at 9 decimals → 5000 lamports.
        XCTAssertEqual(fee, BigInt(5_000))
    }

    func testTronInboundFeeParsedAsSun() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-tron-final-swap-fresh"
        )
        let trx = makeCoin(.tron, ticker: "TRX", decimals: 6)
        let fee = service.inboundFee(from: response, fromCoin: trx)
        // Fixture: "13.3735" TRX at 6 decimals → 13_373_500 sun.
        XCTAssertEqual(fee, BigInt(13_373_500))
    }

    func testErc20SourceFeeScalesByNativeDecimalsNotSellTokenDecimals() throws {
        // Regression: the inbound fee asset is the source chain's NATIVE coin (ETH.ETH, 18dp) even
        // when the SELL token is an ERC-20 (USDC, 6dp). Scaling by the sell token's decimals would
        // under-count the native-ETH fee by 10^12 (98_846_611 instead of the real wei). The native
        // ETH source for this same fixture is pinned in testEvmInboundFeeParsedAsWei.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let fee = service.inboundFee(from: response, fromCoin: usdc)
        // Must scale by ETH's 18 native decimals, NOT USDC's 6.
        XCTAssertEqual(fee, BigInt("98846611703085"))
    }

    func testWrongChainPrefixDoesNotMatch() throws {
        // If we hand the fee parser a coin whose chain doesn't appear in
        // `fees[]`, the parser returns nil rather than picking the wrong
        // inbound entry. Guards against future cross-chain routes where the
        // response carries multiple `inbound` entries for hop chains.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        let wrongCoin = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        XCTAssertNil(service.inboundFee(from: response, fromCoin: wrongCoin))
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool = true) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}
