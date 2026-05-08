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
        let logic = SwapCryptoLogic()
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        // 0.00086087 ETH expressed in wei (gasPrice × gasLimit pre-aggregated by LiFi).
        tx.quote = .lifi(makeEvmQuote(), fee: BigInt("860870000000000"), integratorFee: nil)

        let result = logic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
        XCTAssertFalse(result.contains("Gwei"), "EVM swap quote network fee must not be labelled Gwei")
    }

    func testSwapGasStringForOneInchEvmQuoteFormatsAsNativeEth() {
        let logic = SwapCryptoLogic()
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = .oneinch(makeEvmQuote(), fee: BigInt("860870000000000"))

        let result = logic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringForKyberSwapEvmQuoteFormatsAsNativeEth() {
        let logic = SwapCryptoLogic()
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = .kyberswap(makeEvmQuote(), fee: BigInt("860870000000000"))

        let result = logic.swapGasString(tx: tx)

        XCTAssertEqual(result, "0.00086087 ETH".localeDecimal)
    }

    func testSwapGasStringWithoutQuoteStillRendersGweiOnEvm() {
        // Without a quote `tx.gas` represents a gas price in wei and the
        // legacy "Gwei" label is correct in the user-editing flow.
        let logic = SwapCryptoLogic()
        let tx = SwapTransaction()
        let eth = makeEthCoin()
        tx.fromCoin = eth
        tx.quote = nil
        tx.gas = BigInt("25000000000") // 25 gwei

        let result = logic.swapGasString(tx: tx)

        XCTAssertTrue(result.contains("Gwei"), "Without a quote the EVM gas-price label should remain Gwei")
        XCTAssertTrue(result.hasPrefix("25"), "25 gwei should render as 25 Gwei, got \(result)")
    }
}
