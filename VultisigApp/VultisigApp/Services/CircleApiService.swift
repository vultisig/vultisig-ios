//
//  CircleApiService.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import Foundation
import BigInt

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
    
    func createWallet(vaultPubkey: String) async throws -> String {
        guard let url = URL(string: Endpoint.createCircleWallet()) else {
            throw CircleApiError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["owner_address": vaultPubkey]
        request.httpBody = try? JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw CircleApiError.serverError("Failed to create wallet")
        }
        
        let decoded = try JSONDecoder().decode(CircleWalletResponse.self, from: data)
        return decoded.address
    }
    
    func fetchBalance(address: String) async throws -> Decimal {
        guard let url = URL(string: Endpoint.fetchCircleBalance(address: address)) else {
            throw CircleApiError.invalidUrl
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(CircleBalanceResponse.self, from: data)
        return Decimal(string: decoded.amount) ?? .zero
    }
    
    func fetchYield(address: String) async throws -> CircleYieldResponse {
        guard let url = URL(string: Endpoint.fetchCircleYield(address: address)) else {
            throw CircleApiError.invalidUrl
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CircleYieldResponse.self, from: data)
    }
    
    /// Prepares a withdrawal transaction by calling the backend.
    /// Returns the transaction data (to, value, data, gas) needed for signing.
    func withdraw(walletAddress: String, recipientAddress: String, amount: String) async throws -> CircleTransactionData {
        guard let url = URL(string: Endpoint.withdrawCircleWallet(address: walletAddress)) else {
            throw CircleApiError.invalidUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "recipient_address": recipientAddress,
            "amount": amount
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message
            if let errorString = String(data: data, encoding: .utf8) {
                throw CircleApiError.serverError(errorString)
            }
            throw CircleApiError.serverError("Failed to prepare withdrawal")
        }
        
        return try JSONDecoder().decode(CircleTransactionData.self, from: data)
    }
}
