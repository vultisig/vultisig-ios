//
//  1InchService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import BigInt
import OSLog

struct OneInchService {

    static let shared = OneInchService()
    static let referredFee = 0.5

    private let logger = Logger(subsystem: "com.vultisig.app", category: "oneinch-service")
    private let httpClient: HTTPClientProtocol = HTTPClient()

    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }

    private var referrerAddress: String {
        return "0x8E247a480449c84a5fDD25974A8501f3EFa4ABb9"
    }

    private var supportedChain: [Chain] {
        return [
            .ethereum, .arbitrum, .avalanche, .bscChain, .solana, .optimism, .polygon, .polygonV2, .zksync, .base
        ]
    }
    func isChainSupported(chain: Chain) -> Bool {
        return supportedChain.contains(chain)
    }
    func fetchQuotes(
        chain: String,
        source: String,
        destination: String,
        amount: String,
        from: String,
        isAffiliate: Bool,
        vultTierDiscount: Int
    ) async throws -> (quote: EVMQuote, fee: BigInt?) {

        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = destination.isEmpty ? nullAddress : destination

        let params = OneInchAPI.SwapParams(
            source: sourceAddress,
            destination: destinationAddress,
            amount: amount,
            from: from,
            slippage: "0.5",
            referrer: referrerAddress,
            fee: isAffiliate ? bps(for: vultTierDiscount) : 0
        )

        do {
            let response = try await httpClient.request(
                OneInchAPI.swap(chain: chain, params: params),
                responseType: EVMQuote.self
            )

            let quote = response.data
            let gasPrice = BigInt(quote.tx.gasPrice) ?? 0
            let gas = BigInt(quote.tx.gas)
            let fee = gas * gasPrice

            return (quote, fee)
        } catch HTTPError.statusCode(_, let data) {
            if let data, let error = try? JSONDecoder().decode(OneInchQuoteError.self, from: data) {
                throw HelperError.runtimeError(error.description)
            }
            throw HelperError.runtimeError("1inch swap request failed")
        }
    }

    func fetchTokens(chain: Int) async throws -> [OneInchToken] {
        let response = try await httpClient.request(
            OneInchAPI.tokens(chain: chain),
            responseType: OneInchTokensResponse.self
        )
        return Array(response.data.tokens.values)
    }

    func bps(for discount: Int) -> Double {
        let formattedDiscount = Double(discount) / 100.0
        return max(0, Self.referredFee - formattedDiscount)
    }
}
