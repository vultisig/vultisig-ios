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

    func fetchQuotes(fromCoin: Coin, toCoin: Coin, fromAmount: BigInt) async throws -> OneInchQuote {
        guard let fromChain = fromCoin.chain.chainID, let toChain = fromCoin.chain.chainID else {
            throw Errors.unexpectedError
        }
        let endpoint = Endpoint.fetchLiFiQuote(
            fromChain: String(fromChain),
            toChain: String(toChain),
            fromToken: fromCoin.ticker,
            toToken: toCoin.ticker,
            fromAmount: String(fromAmount),
            fromAddress: fromCoin.address
        )

        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(QuoteResponse.self, from: data)

        guard 
            let gasPrice = Int64(response.transactionRequest.gasPrice.stripHexPrefix(), radix: 16),
            let gas = Int64(response.transactionRequest.gasLimit.stripHexPrefix(), radix: 16) else {
            throw Errors.unexpectedError
        }

        let quote = OneInchQuote(
            dstAmount: response.estimate.toAmount,
            tx: OneInchQuote.Transaction(
                from: response.transactionRequest.from,
                to: response.transactionRequest.to,
                data: response.transactionRequest.data,
                value: response.transactionRequest.value,
                gasPrice: String(gasPrice),
                gas: gas
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
            let executionDuration: Int
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
