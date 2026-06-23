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
            slippage: Self.lifiSlippageFraction(bps: slippageBps)
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

            // Extract swap fee and token contract from LiFi response
            let (swapFee, swapFeeTokenContract) = extractSwapFee(from: quote)

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

            let quote = EVMQuote(
                dstAmount: quote.estimate.toAmount,
                tx: EVMQuote.Transaction(
                    from: .empty,
                    to: .empty,
                    data: quote.transactionRequest.data,
                    value: .empty,
                    gasPrice: .empty,
                    gas: gas,
                    swapFee: "0",
                    swapFeeTokenContract: ""
                )
            )

            return (quote, response.fee, integratorFee)
        }
    }

    /// Convert a user slippage in basis points to the decimal fraction in
    /// [0,1] that LI.FI's `slippage` query param expects (50 bps → "0.005",
    /// 100 bps → "0.01", 300 bps → "0.03"). `nil` (Auto) returns `nil` so the
    /// param is omitted and LI.FI applies its own default — never "0".
    ///
    /// The bps value is clamped to 0–5000 (0–50%) before conversion, mirroring
    /// the 1inch path, so a bogus custom value can't produce an out-of-range
    /// fraction. Rendered with a C-locale `%`-format (always a dot separator),
    /// so it is locale-independent and never emits a comma.
    static func lifiSlippageFraction(bps: Int?) -> String? {
        guard let bps else { return nil }
        let clamped = min(max(bps, 0), 5000)
        let fraction = Double(clamped) / 10_000
        return String(format: "%g", fraction)
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

    func extractSwapFee(from response: LifiQuoteResponse.EvmQuoteResponse) -> (fee: String, tokenContract: String) {
        // Find "LIFI Fixed Fee" in feeCosts array (case-insensitive)
        guard let feeCosts = response.estimate.feeCosts,
              let swapFeeCost = feeCosts.first(where: { $0.name.lowercased() == "lifi fixed fee" }) else {
            return ("0", "")
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
