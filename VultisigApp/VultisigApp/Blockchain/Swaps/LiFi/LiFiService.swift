//
//  LiFiService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 13.07.2024.
//

import Foundation
import BigInt

struct LiFiService {

    static let shared = LiFiService()
    static let integratorFeeBps: Int = 50
    static let stableTickers: Set<String> = [
        "USDC", "USDT", "DAI", "BUSD", "TUSD", "FRAX",
        "USDP", "GUSD", "LUSD", "USDD", "FDUSD", "PYUSD"
    ]

    private let integratorName: String = "vultisig-ios"
    private let httpClient: HTTPClientProtocol = HTTPClient()

    func fetchQuotes(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: BigInt,
        vultTierDiscount: Int,
        slippageBps: Int?
    ) async throws -> (quote: EVMQuote, fee: BigInt?, integratorFee: Decimal?) {

        guard let fromChain = fromCoin.chain.chainID, let toChain = toCoin.chain.chainID else {
            throw Errors.unexpectedError
        }
        let fromToken = fromCoin.contractAddress.isEmpty ? fromCoin.ticker : fromCoin.contractAddress
        let toToken = toCoin.contractAddress.isEmpty ? toCoin.ticker : toCoin.contractAddress
        let integrator = fromCoin.isLifiFeesSupported ? integratorName : nil
        let integratorFee = fromCoin.isLifiFeesSupported ? bps(for: vultTierDiscount) : nil
        var integratorFeeString: String?
        if let integratorFee {
            integratorFeeString = String(format: "%.3f", NSDecimalNumber(decimal: integratorFee).doubleValue)
        }

        let params = LiFiAPI.QuoteParams(
            fromChain: String(fromChain),
            toChain: String(toChain),
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: String(fromAmount),
            fromAddress: fromCoin.address,
            toAddress: toCoin.address,
            integrator: integrator,
            fee: integratorFeeString,
            slippage: Self.lifiSlippageFraction(
                bps: slippageBps,
                fromTicker: fromCoin.ticker,
                toTicker: toCoin.ticker
            )
        )

        let response: LifiQuoteResponse
        do {
            response = try await httpClient.request(
                LiFiAPI.quote(params: params),
                responseType: LifiQuoteResponse.self
            ).data
        } catch HTTPError.statusCode(_, let data) {
            if let data, let error = try? JSONDecoder().decode(LiFiSwapError.self, from: data) {
                throw error
            }
            throw Errors.unexpectedError
        }

        switch response {
        case .evm(let quote):
            guard
                let value = BigInt(quote.transactionRequest.value.stripHexPrefix(), radix: 16),
                let gasPrice = BigInt(quote.transactionRequest.gasPrice.stripHexPrefix(), radix: 16),
                let gas = Int64(quote.transactionRequest.gasLimit.stripHexPrefix(), radix: 16) else {
                throw Errors.unexpectedError
            }

            let normalizedGas = gas == 0 ? EVMHelper.defaultETHSwapGasUnit : gas

            let (swapFee, swapFeeTokenContract) = Self.extractSwapFee(from: quote, integratorFee: integratorFee)

            let quote = EVMQuote(
                dstAmount: quote.estimate.toAmount,
                tx: EVMQuote.Transaction(
                    from: quote.transactionRequest.from,
                    to: quote.transactionRequest.to,
                    data: quote.transactionRequest.data,
                    value: String(value),
                    gasPrice: String(gasPrice),
                    gas: normalizedGas,
                    swapFee: swapFee,
                    swapFeeTokenContract: swapFeeTokenContract
                )
            )

            return (quote, response.fee, integratorFee)
        case .solana(let quote):
            var gas: Int64 = 0
            if !quote.estimate.gasCosts.isEmpty {
                gas = Int64(quote.estimate.gasCosts[0].estimate) ?? 0
            }
            let swapFee = Self.solanaSwapFee(toAmount: quote.estimate.toAmount, integratorFee: integratorFee, toCoin: toCoin)

            let quote = EVMQuote(
                dstAmount: quote.estimate.toAmount,
                tx: EVMQuote.Transaction(
                    from: .empty,
                    to: .empty,
                    data: quote.transactionRequest.data,
                    value: .empty,
                    gasPrice: .empty,
                    gas: gas,
                    swapFee: swapFee,
                    swapFeeTokenContract: swapFee == nil ? "" : toCoin.contractAddress
                )
            )

            return (quote, response.fee, integratorFee)
        }
    }

    /// Convert a user slippage in basis points to the decimal fraction in
    /// [0,1] that LI.FI's `slippage` query param expects (50 bps → "0.005",
    /// 100 bps → "0.01", 300 bps → "0.03"). Auto uses the same pair-aware
    /// tiers as the SDK: 30 bps for stable-to-stable pairs, 100 bps otherwise.
    ///
    /// A non-positive explicit value falls back to the pair-aware Auto tier so
    /// LI.FI never receives a zero tolerance. Positive values are capped at
    /// 5000 bps (50%), mirroring the 1inch upper bound. The POSIX locale keeps
    /// the wire format locale-independent and guarantees a dot separator.
    static func lifiSlippageFraction(
        bps: Int?,
        fromTicker: String,
        toTicker: String
    ) -> String {
        let autoBps = isStablePair(fromTicker: fromTicker, toTicker: toTicker) ? 30 : 100
        let resolvedBps = bps.flatMap { $0 > 0 ? $0 : nil } ?? autoBps
        let clamped = min(resolvedBps, 5000)
        let fraction = Double(clamped) / 10_000
        return String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), fraction)
    }

    private static func isStablePair(fromTicker: String, toTicker: String) -> Bool {
        stableTickers.contains(fromTicker.uppercased()) && stableTickers.contains(toTicker.uppercased())
    }
}

private extension LiFiService {

    enum Errors: Error {
        case unexpectedError
    }

    func bps(for discount: Int) -> Decimal {
        let feeInt = max(0, LiFiService.integratorFeeBps - discount)
        let formattedFee: Decimal = Decimal(feeInt) / 10_000
        return formattedFee
    }
}

extension LiFiService {

    /// Solana routes take the integrator fee as a fraction of the output, so it
    /// is stated in `toCoin`.
    static func solanaSwapFee(toAmount: String, integratorFee: Decimal?, toCoin: Coin) -> String? {
        guard let integratorFee, let toAmount = BigInt(toAmount) else { return nil }
        return toCoin.raw(for: toCoin.decimal(for: toAmount) * integratorFee).description
    }

    static func extractSwapFee(
        from response: LifiQuoteResponse.EvmQuoteResponse,
        integratorFee: Decimal?
    ) -> (fee: String?, tokenContract: String) {
        guard let feeCosts = response.estimate.feeCosts,
              let swapFeeCost = feeCosts.first(where: { $0.name.lowercased() == "lifi fixed fee" }) else {
            // A missing entry is a stated zero only when the app asked for none.
            return (integratorFee == 0 ? "0" : nil, "")
        }

        let feeAmount = swapFeeCost.amount

        // Extract token contract if present and non-empty
        let tokenContract: String
        if let address = swapFeeCost.token?.address,
           !address.isEmpty,
           address.lowercased() != "0x0000000000000000000000000000000000000000" {
            tokenContract = address
        } else {
            tokenContract = ""
        }

        return (feeAmount, tokenContract)
    }
}
