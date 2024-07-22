//
//  BlowfishService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 22/07/24.
//

import Foundation

struct BlowfishService {
    static let shared = BlowfishService()
    
    func scanTransactions(userAccount: String, origin: String, txObjects: [BlowfishRequest.BlowfishTxObject], simulatorConfig: BlowfishRequest.BlowfishSimulatorConfig? = nil) async throws -> BlowfishResponse {
        let url = URL(string: "https://api.blowfish.xyz/ethereum/v0/mainnet/scan/transactions?language=en&method=eth_sendTransaction")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("YOUR_API_KEY", forHTTPHeaderField: "X-Api-Key")
        request.setValue("2023-06-05", forHTTPHeaderField: "X-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let blowfishRequest = BlowfishRequest(
            userAccount: userAccount,
            metadata: BlowfishRequest.BlowfishMetadata(origin: origin),
            txObjects: txObjects,
            simulatorConfig: simulatorConfig
        )
        
        request.httpBody = try JSONEncoder().encode(blowfishRequest)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(BlowfishResponse.self, from: data)
        
        return response
    }
}
