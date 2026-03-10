//
//  QBTCService.swift
//  VultisigApp
//
//  Native qBTC API service for balance fetching and transaction broadcasting.
//  qBTC is NOT a Cosmos chain — it has its own API at api.bitcoinqs.org.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "qbtc-service")

struct QBTCService {

    static let shared = QBTCService()

    // MARK: - Balance

    func fetchBalance(address: String) async throws -> String {
        guard let url = URL(string: Endpoint.fetchQbtcBalance(address: address)) else {
            throw QBTCServiceError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(QBTCBalanceResponse.self, from: data)
        return response.balance
    }

    // MARK: - Broadcast
 
    func broadcastTransaction(rawTransaction: String) async throws -> String {
        guard let url = URL(string: Endpoint.broadcastQbtcTransaction) else {
            throw QBTCServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawTransaction.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(QBTCBroadcastResponse.self, from: data)

        guard let txHash = response.txHash else {
            logger.error("Broadcast failed: \(response.error ?? "unknown error")")
            throw QBTCServiceError.broadcastFailed(response.error ?? "unknown error")
        }

        return txHash
    }
}

// MARK: - Response Models

private struct QBTCBalanceResponse: Decodable {
    let balance: String
}

private struct QBTCBroadcastResponse: Decodable {
    let txHash: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case txHash = "tx_hash"
        case error
    }
}

// MARK: - Errors

enum QBTCServiceError: Error, LocalizedError {
    case invalidURL
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid qBTC API URL"
        case .broadcastFailed(let message):
            return "qBTC broadcast failed: \(message)"
        }
    }
}
