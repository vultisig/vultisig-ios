//
//  EtherfaceService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 11.11.2024.
//

import Foundation

final class EtherfaceService {

    static let shared = EtherfaceService()

    func decode(memo: String) async throws -> String? {
        guard memo.count >= 8 else { return nil }
        
        let hash = memo.stripHexPrefix().prefix(8)
        let endpoint = Endpoint.fetchMemoInfo(hash: String(hash))

        struct Response: Decodable {
            struct Item: Decodable {
                let text: String
            }
            let items: [Item]
        }

        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(Response.self, from: data)

        return response.items.first?.text
    }
}
