//
//  TronService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 02/01/25.
//

import Foundation
import BigInt

class TronService: RpcService {
    
    static let rpcEndpoint = Endpoint.tronServiceRpc
    static let shared = TronService(rpcEndpoint)
    
    func getBalance(coin: Coin) async throws -> String {
        
        let body: [String: Any] = ["address": coin.address, "visible": true]
        let dataPayload = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )
        let data = try await Utils.asyncPostRequest(
            urlString: Endpoint.fetchAccountInfoTron(),
            headers: [:],
            body: dataPayload
        )
        
        if let balance = Utils.extractResultFromJson(fromData: data, path: "balance") as? String {
            return balance
        }
        
        return "0"
        
    }
    
}
