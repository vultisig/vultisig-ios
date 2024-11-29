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

    private let integratorName: String = "vultisig-iOS"
    private let integratorFee: String = "0.005"

    func fetchQuotes(fromCoin: Coin, toCoin: Coin, fromAmount: BigInt) async throws -> OneInchQuote {
        guard let fromChain = fromCoin.chain.chainID, let toChain = toCoin.chain.chainID else {
            throw Errors.unexpectedError
        }
        let fromToken = fromCoin.contractAddress.isEmpty ? fromCoin.ticker : fromCoin.contractAddress
        let toToken = toCoin.contractAddress.isEmpty ? toCoin.ticker : toCoin.contractAddress

        let endpoint = Endpoint.fetchLiFiQuote(
            fromChain: String(fromChain),
            toChain: String(toChain),
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: String(fromAmount),
            fromAddress: fromCoin.address,
            integrator: integratorName,
            fee: integratorFee
        )

        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(QuoteResponse.self, from: data)

        guard 
            let value = BigInt(response.transactionRequest.value.stripHexPrefix(), radix: 16),
            let gasPrice = BigInt(response.transactionRequest.gasPrice.stripHexPrefix(), radix: 16),
            let gas = Int64(response.transactionRequest.gasLimit.stripHexPrefix(), radix: 16) else {
            throw Errors.unexpectedError
        }

        let normalizedGas = gas == 0 ? EVMHelper.defaultETHSwapGasUnit : gas

        let quote = OneInchQuote(
            dstAmount: response.estimate.toAmount,
            tx: OneInchQuote.Transaction(
                from: response.transactionRequest.from,
                to: response.transactionRequest.to,
                data: response.transactionRequest.data,
                value: String(value),
                gasPrice: String(gasPrice),
                gas: normalizedGas
            )
        )

        return quote
    }
}

private extension LiFiService {

    enum Errors: Error {
        case unexpectedError
    }

    struct QuoteResponse: Codable {
        struct Estimate: Codable {
            let toAmount: String
            let toAmountMin: String
            let executionDuration: Decimal
        }
        struct TransactionRequest: Codable {
            let data: String
            let to: String
            let value: String
            let from: String
            let chainId: Int
            let gasLimit: String
            let gasPrice: String
        }
        let estimate: Estimate
        let transactionRequest: TransactionRequest
    }
}
