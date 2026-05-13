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

/// Pins the format produced by `SwapCryptoLogic.swapGasString(tx:)` for
/// quote-driven EVM swaps (LI.FI / OneInch / KyberSwap). The bug being
/// guarded against: when a quote was attached, the function divided
/// `tx.fee` (already wei) by 1e9 and labelled the result `Gwei`, so the
/// verify screen displayed numbers like `121,094 Gwei` — visually
/// indistinguishable from a gas-limit. Expected behaviour is to format
/// the wei value as a native amount (`0.000861 ETH`) the same way the
/// non-EVM branch does.
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

    func testSwapGasStringForLiFiEvmQuoteFormatsAsNativeEth() {
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        // 0.00086087 ETH expressed in wei (gasPrice × gasLimit pre-aggregated by LiFi).
        tx.quote = .lifi(makeEvmQuote(), fee: BigInt("860870000000000"), integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
        XCTAssertFalse(result.contains("Gwei"), "EVM swap quote network fee must not be labelled Gwei")
    }

    func testSwapGasStringForOneInchEvmQuoteFormatsAsNativeEth() {
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = .oneinch(makeEvmQuote(), fee: BigInt("860870000000000"))

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringForKyberSwapEvmQuoteFormatsAsNativeEth() {
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = .kyberswap(makeEvmQuote(), fee: BigInt("860870000000000"))

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringFromNonNativeCoinWithoutNativeInListReturnsEmpty() {
        // Regression: when `tx.fromCoin` is a non-native ERC20 and `tx.fromCoins`
        // doesn't contain the chain's native asset, `feeCoin(tx:)` falls back to
        // `tx.fromCoin`. Without the guard we'd format a wei-denominated fee with
        // USDC's 6 decimals + "USDC" ticker, producing an absurd number labelled
        // with the wrong asset. The display should suppress the row instead.
        let tx = SwapTransaction()
        tx.fromCoin = makeUsdcCoin()
        tx.fromCoins = [makeUsdcCoin()] // no native ETH in list
        tx.quote = .lifi(makeEvmQuote(), fee: BigInt("860870000000000"), integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertEqual(result, "", "Should return empty when no native asset is available to denominate the fee")
    }

    func testSwapGasStringFromNonNativeCoinWithNativeInListUsesNativeForDisplay() {
        // When `tx.fromCoin` is USDC but the user's wallet has ETH on the same
        // chain, `feeCoin(tx:)` resolves to ETH and the fee renders correctly.
        let tx = SwapTransaction()
        tx.fromCoin = makeUsdcCoin()
        tx.fromCoins = [makeUsdcCoin(), makeEthCoin()]
        tx.quote = .lifi(makeEvmQuote(), fee: BigInt("860870000000000"), integratorFee: nil)

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringWithoutQuoteStillRendersGweiOnEvm() {
        // Without a quote `tx.gas` represents a gas price in wei and the
        // legacy "Gwei" label is correct in the user-editing flow.
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = nil
        tx.gas = BigInt("25000000000") // 25 gwei

        let result = SwapCryptoLogic.swapGasString(tx: tx)

        XCTAssertTrue(result.contains("Gwei"), "Without a quote the EVM gas-price label should remain Gwei")
        XCTAssertTrue(result.hasPrefix("25"), "25 gwei should render as 25 Gwei, got \(result)")
    }
}
