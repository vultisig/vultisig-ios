import XCTest
import BigInt
@testable import VultisigApp

// `formatToDecimal` uses `Locale.current`, so hardcoded `.`-separated
// expected strings fail on simulators in comma-decimal locales.
private extension String {
    var localeDecimal: String {
        let sep = Locale.current.decimalSeparator ?? "."
        return replacingOccurrences(of: ".", with: sep)
    }
}

/// Pins the format produced by `SwapCryptoLogic.swapGasString(quote:feeCoin:gas:fee:)`
/// for quote-driven EVM swaps (LI.FI / OneInch / KyberSwap). The bug being
/// guarded against: when a quote was attached, the function divided the fee
/// (already wei) by 1e9 and labelled the result `Gwei`, so the verify screen
/// displayed numbers like `121,094 Gwei` — visually indistinguishable from a
/// gas-limit. Expected behaviour is to format the wei value as a native
/// amount (`0.000861 ETH`) the same way the non-EVM branch does.
final class SwapNetworkFeeTests: XCTestCase {

    private func makeEthCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: "ETH",
            logo: "eth",
            decimals: 18,
            priceProviderId: "ethereum",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }

    private func makeUsdcCoin() -> Coin {
        let meta = CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            isNativeToken: false
        )
        return Coin(asset: meta, address: "test", hexPublicKey: "test")
    }

    private func makeEvmQuote() -> EVMQuote {
        EVMQuote(
            dstAmount: "0",
            tx: EVMQuote.Transaction(
                from: "0x0",
                to: "0x0",
                data: "0x",
                value: "0",
                gasPrice: "0",
                gas: 0
            )
        )
    }

    private let fee = BigInt("860870000000000") // 0.00086087 ETH in wei

    func testSwapGasStringForLiFiEvmQuoteFormatsAsNativeEth() {
        let eth = makeEthCoin()
        let quote: SwapQuote = .lifi(makeEvmQuote(), fee: fee, integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(quote: quote, feeCoin: eth, gas: .zero, fee: fee)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
        XCTAssertFalse(result.contains("Gwei"), "EVM swap quote network fee must not be labelled Gwei")
    }

    func testSwapGasStringForOneInchEvmQuoteFormatsAsNativeEth() {
        let eth = makeEthCoin()
        let quote: SwapQuote = .oneinch(makeEvmQuote(), fee: fee)

        let result = SwapCryptoLogic.swapGasString(quote: quote, feeCoin: eth, gas: .zero, fee: fee)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringForKyberSwapEvmQuoteFormatsAsNativeEth() {
        let eth = makeEthCoin()
        let quote: SwapQuote = .kyberswap(makeEvmQuote(), fee: fee)

        let result = SwapCryptoLogic.swapGasString(quote: quote, feeCoin: eth, gas: .zero, fee: fee)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringFromNonNativeCoinWithoutNativeInListReturnsEmpty() {
        // Regression: when the source is a non-native ERC20 and the fromCoins
        // list doesn't contain the chain's native asset, `feeCoin(fromCoin:fromCoins:)`
        // falls back to the source coin. Without the `isNativeToken` guard we'd
        // format a wei-denominated fee with USDC's 6 decimals + "USDC" ticker,
        // producing an absurd number labelled with the wrong asset. The display
        // should suppress the row instead.
        let usdc = makeUsdcCoin()
        let resolvedFeeCoin = SwapCryptoLogic.feeCoin(fromCoin: usdc, fromCoins: [usdc])
        let quote: SwapQuote = .lifi(makeEvmQuote(), fee: fee, integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(quote: quote, feeCoin: resolvedFeeCoin, gas: .zero, fee: fee)

        XCTAssertEqual(result, "", "Should return empty when no native asset is available to denominate the fee")
    }

    func testSwapGasStringFromNonNativeCoinWithNativeInListUsesNativeForDisplay() {
        // When the source is USDC but the user's wallet has ETH on the same
        // chain, `feeCoin(fromCoin:fromCoins:)` resolves to ETH and the fee
        // renders correctly.
        let usdc = makeUsdcCoin()
        let resolvedFeeCoin = SwapCryptoLogic.feeCoin(fromCoin: usdc, fromCoins: [usdc, makeEthCoin()])
        let quote: SwapQuote = .lifi(makeEvmQuote(), fee: fee, integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(quote: quote, feeCoin: resolvedFeeCoin, gas: .zero, fee: fee)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringWithoutQuoteStillRendersGweiOnEvm() {
        // Without a quote `gas` represents a gas price in wei and the
        // legacy "Gwei" label is correct in the user-editing flow.
        let eth = makeEthCoin()
        let gas = BigInt("25000000000") // 25 gwei

        let result = SwapCryptoLogic.swapGasString(quote: nil, feeCoin: eth, gas: gas, fee: .zero)

        XCTAssertTrue(result.contains("Gwei"), "Without a quote the EVM gas-price label should remain Gwei")
        XCTAssertTrue(result.hasPrefix("25"), "25 gwei should render as 25 Gwei, got \(result)")
    }
}
