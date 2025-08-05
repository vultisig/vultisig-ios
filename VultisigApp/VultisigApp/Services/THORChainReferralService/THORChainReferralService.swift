//
//  THORChainReferralService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 05/08/2025.
//

struct THORChainReferralService {
    private let httpClient: HTTPClientProtocol
    
    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }
    
    func getThornameDetails(name: String) async throws -> THORName {
        let response = try await httpClient.request(THORChainAPI.thornameDetails(name: name), responseType: THORName.self)
        return response.data
    }
    
    func getLastBlock() async throws -> UInt64 {
        let response = try await httpClient.request(THORChainAPI.lastBlock, responseType: [LastBlockResponse].self)
        return response.data.first?.thorchain ?? 0
    }
}


