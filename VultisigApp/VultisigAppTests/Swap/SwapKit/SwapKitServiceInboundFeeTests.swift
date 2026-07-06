//
//  SwapKitServiceInboundFeeTests.swift
//  VultisigAppTests
//
//  Pins the SwapKit source-chain network fee extraction. The fee feeds:
//
//    * the verify-screen Network Fee row + Total Fee (fiat)
//    * `validateForm` (Continue button lights up only when fee != .zero)
//    * `balanceError`'s gas-coin sufficiency check (`fromFee > feeCoinBalance`)
//
//  Two source-shape families:
//
//    * EVM sources: the fee is the realised `tx.gas × tx.gasPrice` (the value
//      the keysign path commits to), NOT the wire `inbound` `fees[]` entry.
//      The `inbound` amount is a per-provider estimate — FLASHNET-on-EVM
//      returns a near-zero placeholder there that rendered as garbage
//      (`0.00000000000000013 ETH` ≈ 130 wei) with a `$0.00` total.
//    * Non-EVM sources (Solana, TRON, UTXO): the `inbound` entry carries the
//      real native fee as a decimal native amount (e.g. "0.000005" SOL), so
//      those keep the wire path.
//
//  A regression here either disables Continue silently, lets a swap through
//  despite insufficient gas, or shows a misleading fee — all visible only in
//  live testing.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapKitServiceInboundFeeTests: XCTestCase {

    private let service = SwapKitService()

    func testEvmFeeDerivedFromGasTimesGasPrice() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let fee = service.inboundFee(from: response, fromCoin: eth)
        // EVM fee is the realised tx gas, NOT the wire `inbound` estimate.
        // Fixture tx: gas 0x55730 (350_000) × gasPrice 0x2aaa0b23 (715_787_043 wei)
        // = 250_525_465_050_000 wei. The wire `inbound` entry on this fixture is a
        // smaller estimate (0.000098846611703085 ETH); we deliberately ignore it.
        XCTAssertEqual(fee, BigInt("250525465050000"))
    }

    func testFlashnetEvmSourceUsesGasTimesGasPriceNotInboundPlaceholder() throws {
        // Regression for the FLASHNET-on-EVM garbage fee. SwapKit returns a
        // near-zero `inbound` placeholder ("0.00000000000000013" ETH ≈ 130 wei)
        // for FLASHNET on an EVM source; the old wire path rendered that as
        // `0.00000000000000013 ETH` on the Network Fee row with a `$0.00` total.
        // The real gas is on `tx.gas`/`tx.gasPrice`.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-flashnet-evm-usdc-btc-swap"
        )
        // Sell token is USDC (6dp) — the fee must still come out in ETH wei
        // (18dp gas units), independent of the sell token's decimals.
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let fee = service.inboundFee(from: response, fromCoin: usdc)
        // Fixture tx: gas 0x33450 (210_000) × gasPrice 0x3b9aca00 (1 gwei)
        // = 210_000_000_000_000 wei (0.00021 ETH). NOT the 130-wei placeholder.
        XCTAssertEqual(fee, BigInt("210000000000000"))
        XCTAssertNotEqual(fee, BigInt(130), "Must not regress to the inbound placeholder (~130 wei)")
    }

    func testEvmFeeFallsBackToDefaultGasUnitWhenGasZero() throws {
        // A native route that omits the gas limit (gas == 0) must still surface a
        // representative fee using `EVMHelper.defaultETHSwapGasUnit`, mirroring
        // the keysign-path normalisation, rather than collapsing to zero.
        let tx = SwapKitEvmTx(
            from: "0xfrom",
            to: "0xto",
            value: "0",
            data: "0x",
            gas: "0x0",
            gasPrice: "0x3b9aca00" // 1 gwei
        )
        let fee = service.evmNetworkFee(from: tx, isNativeSource: true)
        let expected = BigInt(EVMHelper.defaultETHSwapGasUnit) * BigInt(1_000_000_000)
        XCTAssertEqual(fee, expected)
    }

    func testEvmFeeFallsBackToErc20UnitWhenGasZeroForTokenSource() throws {
        // An ERC-20 route that omits the gas limit falls back to the token
        // operation unit rather than the native swap unit.
        let tx = SwapKitEvmTx(
            from: "0xfrom",
            to: "0xto",
            value: "0",
            data: "0x",
            gas: "0x0",
            gasPrice: "0x3b9aca00" // 1 gwei
        )
        let fee = service.evmNetworkFee(from: tx, isNativeSource: false)
        let expected = BigInt(EVMHelper.defaultERC20TransferGasUnit) * BigInt(1_000_000_000)
        XCTAssertEqual(fee, expected)
    }

    func testEvmFeeRespectsReportedGasWhenNonZero() throws {
        // SwapKit's reported gas is respected verbatim when present — we don't
        // floor or substitute it, even for an ERC-20 source.
        let tx = SwapKitEvmTx(
            from: "0xfrom",
            to: "0xto",
            value: "0",
            data: "0x",
            gas: "0x33450", // 210_000
            gasPrice: "0x3b9aca00" // 1 gwei
        )
        let fee = service.evmNetworkFee(from: tx, isNativeSource: false)
        XCTAssertEqual(fee, BigInt(210_000) * BigInt(1_000_000_000))
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

    func testBitcoinFlashnetInboundFeeUnchangedByEvmFix() throws {
        // Regression guard: the EVM fee change must not touch non-EVM FLASHNET.
        // BTC FLASHNET ships txType "PSBT", so `inboundFee` stays on the wire
        // `inbound` path and reads BTC.BTC at 8 decimals verbatim.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-btc-FLASHNET-swap"
        )
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
        let fee = service.inboundFee(from: response, fromCoin: btc)
        // Fixture: "0.000004" BTC at 8 decimals → 400 sats.
        XCTAssertEqual(fee, BigInt(400))
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

    func testEvmFeeIsIndependentOfSellTokenDecimals() throws {
        // The EVM fee is `tx.gas × tx.gasPrice` in wei — denominated in the
        // chain's native gas coin (ETH, 18dp) regardless of the sell token's
        // decimals. An ERC-20 source (USDC, 6dp) must produce the identical fee
        // as the native ETH source for the same fixture tx.
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let fee = service.inboundFee(from: response, fromCoin: usdc)
        // Same gas × gasPrice as testEvmFeeDerivedFromGasTimesGasPrice (native ETH source).
        XCTAssertEqual(fee, BigInt("250525465050000"))
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
