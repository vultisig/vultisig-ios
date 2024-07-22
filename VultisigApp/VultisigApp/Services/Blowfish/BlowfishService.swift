//
//  BlowfishService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

struct BlowfishService {
    static let shared = BlowfishService()
    
    func scanTransactions
    (
        chain: String,
        userAccount: String,
        origin: String,
        txObjects: [BlowfishRequest.BlowfishTxObject],
        simulatorConfig: BlowfishRequest.BlowfishSimulatorConfig? = nil
    ) async throws -> BlowfishResponse {
        
        let blowfishRequest = BlowfishRequest(
            userAccount: userAccount,
            metadata: BlowfishRequest.BlowfishMetadata(origin: origin),
            txObjects: txObjects,
            simulatorConfig: simulatorConfig
        )
        
        let endpoint = Endpoint.fetchBlowfishTransactions(chain: chain)
        let headers = ["X-Api-Version" : "2023-06-05"]
        let body = try JSONEncoder().encode(blowfishRequest)
        let dataResponse = try await Utils.asyncPostRequest(urlString: endpoint, headers: headers, body: body)
        let response = try JSONDecoder().decode(BlowfishResponse.self, from: dataResponse)
        
        return response
    }
}
