//
//  TronAPIService.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/01/2026.
//

import Foundation
import BigInt
import WalletCore

struct TronAPIService {
    let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - Block Info

    func getNowBlock() async throws -> TronNowBlockResponse {
        let response = try await httpClient.request(TronAPI.getNowBlock, responseType: TronNowBlockResponse.self)
        return response.data
    }

    // MARK: - Account

    func getAccount(address: String) async throws -> TronAccountResponse {
        let response = try await httpClient.request(TronAPI.getAccount(address: address), responseType: TronAccountResponse.self)
        return response.data
    }

    func getAccountResource(address: String) async throws -> TronAccountResourceResponse {
        let response = try await httpClient.request(TronAPI.getAccountResource(address: address), responseType: TronAccountResourceResponse.self)
        return response.data
    }

    // MARK: - Chain Parameters

    func getChainParameters() async throws -> TronChainParametersResponse {
        let response = try await httpClient.request(TronAPI.getChainParameters, responseType: TronChainParametersResponse.self)
        return response.data
    }

    // MARK: - Broadcast

    func broadcastTransaction(jsonString: String) async throws -> String {
        let response = try await httpClient.request(TronAPI.broadcastTransaction(jsonString: jsonString), responseType: TronBroadcastResponse.self)

        guard response.data.result == true, let txid = response.data.txid else {
            let errorMessage = response.data.message ?? "Unknown error"
            throw TronAPIError.broadcastFailed(errorMessage)
        }

        return txid
    }

    // MARK: - Balance

    func getNativeBalance(address: String) async throws -> String {
        let account = try await getAccount(address: address)
        return String(account.balance ?? 0)
    }

    func getTRC20Balance(contractAddress: String, walletAddress: String) async throws -> BigInt {
        // Convert wallet address to hex parameter for balanceOf(address) call
        guard let addressData = Base58.decode(string: walletAddress) else {
            return BigInt(0)
        }

        // Full 21-byte address as hex (includes 41 prefix), padded to 32 bytes (64 hex chars)
        let addressHex = addressData.hexString
        let parameter = String(repeating: "0", count: max(0, 64 - addressHex.count)) + addressHex

        let response = try await httpClient.request(
            TronAPI.triggerConstantContract(
                ownerAddress: walletAddress,
                contractAddress: contractAddress,
                functionSelector: "balanceOf(address)",
                parameter: parameter
            ),
            responseType: TronTriggerConstantResponse.self
        )

        // Parse constant_result from response
        guard let resultArray = response.data.constant_result,
              let hexResult = resultArray.first else {
            return BigInt(0)
        }

        // Convert hex to BigInt
        return BigInt(hexResult, radix: 16) ?? BigInt(0)
    }
}

// MARK: - Errors

enum TronAPIError: LocalizedError {
    case broadcastFailed(String)
    case invalidAddress
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .broadcastFailed(let message):
            return "Broadcast failed: \(message)"
        case .invalidAddress:
            return "Invalid Tron address"
        case .invalidResponse:
            return "Invalid response from Tron API"
        }
    }
}
