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
        let state: String?
        let walletSetId: String?
        let custodyType: String?
        let name: String?
        let address: String
        let refId: String?
        let blockchain: String?
        let accountType: String?
        let updateDate: String?
        let createDate: String?
        let scaCore: String?
    }
    func fetchWallet(ethAddress: String) async throws -> String? {
        let fetchUrlString = Endpoint.fetchCircleWallets(refId: ethAddress)
        print("[CircleAPI] fetchWallet - URL: \(fetchUrlString)")
        guard let fetchUrl = URL(string: fetchUrlString) else {
            throw CircleApiError.invalidUrl
        }
        
        let (fetchData, fetchResponse) = try await URLSession.shared.data(from: fetchUrl)
        
        if let httpResponse = fetchResponse as? HTTPURLResponse {
            print("[CircleAPI] fetchWallet - Status: \(httpResponse.statusCode)")
            if let responseString = String(data: fetchData, encoding: .utf8) {
                print("[CircleAPI] fetchWallet - Response: \(responseString.prefix(500))")
            }
            
            if httpResponse.statusCode == 200 {
                let wallets = try JSONDecoder().decode([CircleWalletItem].self, from: fetchData)
                print("[CircleAPI] fetchWallet - Decoded \(wallets.count) wallets")
                if let firstWallet = wallets.first {
                    print("[CircleAPI] fetchWallet - Returning address: \(firstWallet.address)")
                    return firstWallet.address
                }
            }
        }
        print("[CircleAPI] fetchWallet - Returning nil")
        return nil
    }
    
    func createWallet(ethAddress: String, force: Bool = false) async throws -> String {
        guard !ethAddress.isEmpty else {
            throw CircleApiError.invalidUrl
        }
        
        // Fetch existing wallet via refId (Skip if force is true)
        if !force {
            if let existing = try? await fetchWallet(ethAddress: ethAddress) {
                return existing
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
