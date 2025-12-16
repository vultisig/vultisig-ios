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
        // Simple approach: Just use the vault's ETH address directly
        // No need to re-derive - the address already exists in vault.coins
        
        print("CircleApiService: createWallet called.")
        print("CircleApiService: ETH Address (owner): \(ethAddress)")
        print("CircleApiService: Force: \(force)")
        
        guard !ethAddress.isEmpty else {
            print("CircleApiService: ERROR - ETH address is empty!")
            throw CircleApiError.invalidUrl
        }
        
        // 2. Fetch existing wallet via refId (Skip if force is true)
        if !force {
            let fetchUrlString = Endpoint.fetchCircleWallets(refId: ethAddress)
            guard let fetchUrl = URL(string: fetchUrlString) else {
                throw CircleApiError.invalidUrl
            }
            
            print("CircleApiService: Fetching wallet from: \(fetchUrl.absoluteString)")
            let (fetchData, fetchResponse) = try await URLSession.shared.data(from: fetchUrl)
            
            if let httpResponse = fetchResponse as? HTTPURLResponse {
                 print("CircleApiService: createWallet (FETCH) Status: \(httpResponse.statusCode)")
            }
            
            if let httpResponse = fetchResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let wallets = try JSONDecoder().decode([CircleWalletItem].self, from: fetchData)
                if let firstWallet = wallets.first {
                    print("CircleApiService: Found existing wallet: \(firstWallet.address)")
                    return firstWallet.address
                } else {
                    print("CircleApiService: No existing wallet found for this refId.")
                }
            }
        } else {
             print("CircleApiService: FORCE flag enabled. Skipping check for existing wallet.")
        }
        
        // 3. If not found, try to Create (POST)
        guard let createUrl = URL(string: Endpoint.createCircleWallet()) else {
            throw CircleApiError.invalidUrl
        }
        
        print("CircleApiService: Attempting to create wallet via POST at: \(createUrl.absoluteString)")
        
        var request = URLRequest(url: createUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Payload matching CreateWalletReq in server.go (snake_case inferred from successful curl)
        let payload: [String: String] = [
            "idempotency_key": UUID().uuidString,
            "account_type": "SCA",
            "name": "Vultisig Wallet",
            "owner": ethAddress
        ]
        
        request.httpBody = try? JSONEncoder().encode(payload)
        
        let (createData, createResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = createResponse as? HTTPURLResponse {
             print("CircleApiService: createWallet (POST) Status: \(httpResponse.statusCode)")
        }
        
        guard let httpResponse = createResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorString = String(data: createData, encoding: .utf8) ?? "Unknown error"
            print("CircleApiService: createWallet failed. Response: \(errorString)")
            throw CircleApiError.serverError("Failed to create wallet")
        }
        
        // The CreateWalletResp in server.go returns "contractAddr" (String) directly if using JSON?
        // Wait, server.go returns: c.JSON(http.StatusCreated, contractAddr) -> This is a JSON String, not an object?
        // "return c.JSON(http.StatusCreated, contractAddr)" in Echo sends just the string "0x..." but quoted?
        // Or if contractAddr is string, it sends "0x123...".
        // Let's assume it sends a raw string or single value.
        // But invalid JSON is simpler: let's try to decode as String first.
        
        // Actually, Echo c.JSON usually sends `json.Marshal(contractAddr)`, so it's a quoted string: `"0x..."`.
        
        if let addressString = try? JSONDecoder().decode(String.self, from: createData) {
            print("CircleApiService: createWallet success. Address: \(addressString)")
            return addressString
        }
        
        // Fallback: Try decoding as object if my assumption is wrong
        // But server.go says `c.JSON(..., contractAddr)`.
        
        throw CircleApiError.decodingError
    }
    
}
