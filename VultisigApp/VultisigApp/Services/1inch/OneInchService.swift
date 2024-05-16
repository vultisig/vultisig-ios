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

    func fetchQuotes(chain: String, source: String, destination: String, amount: String, from: String) async throws -> OneInchQuote {

        let sourceAddress = source.isEmpty ? nullAddress : source
        let destinationAddress = sourceAddress.isEmpty ? nullAddress : destination

        let url = Endpoint.fetch1InchSwapQuote(
            chain: chain,
            source: sourceAddress,
            destination: destinationAddress,
            amount: amount,
            from: from,
            slippage: "0.5"
        )

        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = [
            "accept": "application/json",
        ]

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OneInchQuote.self, from: data)
        return response
    }
}
