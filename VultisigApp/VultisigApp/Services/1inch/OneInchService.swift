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

    func fetchQuotes(chain: String, source: String, destination: String, amount: String) async throws -> OneInchQuote {
        let url = Endpoint.fetch1InchSwapQuote(
            chain: chain,
            source: source,
            destination: destination,
            amount: amount
        )
        let request = URLRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OneInchQuote.self, from: data)
        return response
    }
}
