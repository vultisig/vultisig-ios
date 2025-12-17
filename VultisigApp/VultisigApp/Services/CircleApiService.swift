//
//  CircleApiService.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import Foundation

enum CircleApiError: Error {
    case invalidUrl
    case decodingError
    case serverError(String)
    case unauthorized
    case unknown
}

struct CircleApiService {
    static let shared = CircleApiService()
    
    private init() {}
    
    // MARK: - DTOs
    
    struct CircleWalletResponse: Decodable {
        let address: String
        let status: String
    }
    
    struct CircleBalanceResponse: Decodable {
        let amount: String
        let currency: String
    }
    
    struct CircleYieldResponse: Decodable {
        let apy: String
        let totalRewards: String
        let currentRewards: String
    }
    
    struct CircleTransactionData: Decodable {
        let to: String
        let value: String
        let data: String
        let gasLimit: String
        let maxFeePerGas: String
        let maxPriorityFeePerGas: String
    }
    
    // MARK: - Public API
    
    struct CircleWalletItem: Decodable {
        let id: String
        let state: String
        let walletSetId: String
        let custodyType: String
        let name: String
        let address: String
        let refId: String
        let blockchain: String
        let accountType: String
        let updateDate: String
        let createDate: String
        let scaCore: String
    }
    
    func createWallet(ethAddress: String, force: Bool = false) async throws -> String {
        guard !ethAddress.isEmpty else {
            throw CircleApiError.invalidUrl
        }
        
        // Fetch existing wallet via refId (Skip if force is true)
        if !force {
            let fetchUrlString = Endpoint.fetchCircleWallets(refId: ethAddress)
            guard let fetchUrl = URL(string: fetchUrlString) else {
                throw CircleApiError.invalidUrl
            }
            
            let (fetchData, fetchResponse) = try await URLSession.shared.data(from: fetchUrl)
            
            if let httpResponse = fetchResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let wallets = try JSONDecoder().decode([CircleWalletItem].self, from: fetchData)
                if let firstWallet = wallets.first {
                    return firstWallet.address
                }
            }
        }
        
        // Create new wallet
        guard let createUrl = URL(string: Endpoint.createCircleWallet()) else {
            throw CircleApiError.invalidUrl
        }
        
        var request = URLRequest(url: createUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: String] = [
            "idempotency_key": UUID().uuidString,
            "account_type": "SCA",
            "name": "Vultisig Wallet",
            "owner": ethAddress
        ]
        
        request.httpBody = try? JSONEncoder().encode(payload)
        
        let (createData, createResponse) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = createResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw CircleApiError.serverError("Failed to create wallet")
        }
        
        if let addressString = try? JSONDecoder().decode(String.self, from: createData) {
            return addressString
        }
        
        throw CircleApiError.decodingError
    }
}
