//
//  1InchService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import BigInt

struct OneInchService {
    
    static let shared = OneInchService()
    
    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
    
    private var referrerAddress: String {
        return "0xa4a4f610e89488eb4ecc6c63069f241a54485269"
    }
    
    private var supportedChain: [Chain] {
        return [
            .ethereum,.arbitrum,.avalanche,.bscChain,.solana,.optimism,.polygon,.polygonV2,.zksync,.base
        ]
    }
    func isChainSupported(chain: Chain) -> Bool {
        return supportedChain.contains(chain)
    }
    func fetchQuotes(chain: String, source: String, destination: String, amount: String, from: String, isAffiliate: Bool) async throws -> (quote: OneInchQuote, fee: BigInt?) {
        
        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = destination.isEmpty ? nullAddress : destination
        
        let url = Endpoint.fetch1InchSwapQuote(
            chain: chain,
            source: sourceAddress,
            destination: destinationAddress,
            amount: amount,
            from: from,
            slippage: "0.5",
            referrer: referrerAddress,
            fee: 0.5,
            isAffiliate: isAffiliate
        )
        
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = [
            "accept": "application/json",
        ]
        
        let (data, resp) = try await URLSession.shared.data(for: request)
        
        print("1inch response: \(String(data: data, encoding: .utf8) ?? "")")
        guard let httpResponse = resp as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let result = try JSONDecoder().decode(OneInchQuoteError.self, from: data)
            throw HelperError.runtimeError(result.description)
        }
        
        let response = try JSONDecoder().decode(OneInchQuote.self, from: data)
        
        let gasPrice = BigInt(response.tx.gasPrice) ?? 0
        let gas = BigInt(response.tx.gas)
        let fee = gas * gasPrice
        
        return (response, fee)
    }
    
    func fetchTokens(chain: Int) async throws -> [OneInchToken] {
        let response: OneInchTokensResponse = try await Utils.fetchObject(from: Endpoint.fetchTokens(chain: chain))
        let tokens = Array(arrayLiteral: response.tokens.values).reduce([], +)
        return tokens
    }
    
}

private extension OneInchService {
    
    struct OneInchTokensResponse: Codable {
        let tokens: [String: OneInchToken]
    }
}
