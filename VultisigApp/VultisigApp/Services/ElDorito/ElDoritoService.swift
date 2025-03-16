//
//  1InchService.swift
//  VoltixApp
//
//  Created by Artur Guseinov on 07.05.2024.
//

import Foundation
import BigInt

struct ElDoritoService {
    
    static let shared = ElDoritoService()
    
    private var nullAddress: String {
        return "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
    
    private var referrerAddress: String {
        return "0xa4a4f610e89488eb4ecc6c63069f241a54485269"
    }
    
    func fetchQuotes(
        chain: String,
        source: String,
        destination: String,
        amount: String,
        from: String,
        isAffiliate: Bool
    ) async throws -> (quote: ElDoritoQuote, fee: BigInt?) {
        
        let url = Endpoint.fetchElDoritoSwapQuote()
        
        var body: [String: Any] = [
            "sellAsset": source, // The asset being sold (e.g. "ETH.ETH").
            "buyAsset": destination, // The asset being bought (e.g. "BTC.BTC").
            "sellAmount": amount, // Amount in basic units (decimals separated with a dot).
            "sourceAddress": from,
            "destinationAddress": destination,
            "slippage": 1,
            "includeTx": true
        ]
        
        // Add affiliate parameters if enabled
        if isAffiliate {
            body["affiliate"] = "0xa4a4f610e89488eb4ecc6c63069f241a54485269"
            body["affiliateFee"] = 50 // Example: 0.5% fee
        }
        
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = dataPayload
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ElDoritoQuote.self, from: data)
        
        let gasPrice = BigInt(response.tx.gasPrice) ?? 0
        let gas = BigInt(response.tx.gas)
        let fee = gas * gasPrice
        
        return (response, fee)
    }
    
//    func fetchTokens(chain: Int) async throws -> [OneInchToken] {
//        let response: ElDoritoTokensResponse = try await Utils.fetchObject(from: Endpoint.fetchTokens(chain: chain))
//        let tokens = Array(arrayLiteral: response.tokens.values).reduce([], +)
//        return tokens
//    }
    
}

private extension ElDoritoService {
    
    struct ElDoritoTokensResponse: Codable {
        let tokens: [String: ElDoritoToken]
    }
}
