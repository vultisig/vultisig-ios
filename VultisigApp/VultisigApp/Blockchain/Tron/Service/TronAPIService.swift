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

    private static let DUP_TRANSACTION_ERROR_CODE = "DUP_TRANSACTION_ERROR"

    func broadcastTransaction(jsonString: String) async throws -> String {
        let response = try await httpClient.request(TronAPI.broadcastTransaction(jsonString: jsonString), responseType: TronBroadcastResponse.self)

        // Accept success (result == true) OR duplicate transaction error (already broadcast)
        // This matches Android behavior where DUP_TRANSACTION_ERROR is treated as success
        let isSuccess = response.data.result == true
        let isDuplicateTransaction = response.data.code == Self.DUP_TRANSACTION_ERROR_CODE

        guard let txid = response.data.txid, isSuccess || isDuplicateTransaction else {
            let errorMessage = response.data.message ?? response.data.code ?? "Unknown error"
            throw TronAPIError.broadcastFailed(errorMessage)
        }

        return txid
    }

    // MARK: - Balance

    func getNativeBalance(address: String) async throws -> String {
        let account = try await getAccount(address: address)
        return String(account.balance ?? 0)
    }

    // MARK: - Token Info

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        // Use a zero-padded dummy parameter (required by triggerConstantContract but not used by these view functions)
        let emptyParameter = String(repeating: "0", count: 64)

        // Fetch all three in parallel
        async let nameResponse = httpClient.request(
            TronAPI.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "name()",
                parameter: emptyParameter
            ),
            responseType: TronTriggerConstantResponse.self
        )

        async let symbolResponse = httpClient.request(
            TronAPI.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "symbol()",
                parameter: emptyParameter
            ),
            responseType: TronTriggerConstantResponse.self
        )

        async let decimalsResponse = httpClient.request(
            TronAPI.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "decimals()",
                parameter: emptyParameter
            ),
            responseType: TronTriggerConstantResponse.self
        )

        let nameResult = try await nameResponse.data
        let symbolResult = try await symbolResponse.data
        let decimalsResult = try await decimalsResponse.data

        // Decode name
        let name: String
        if let nameHex = nameResult.constant_result?.first {
            name = Self.decodeAbiString(from: nameHex)
        } else {
            name = ""
        }

        // Decode symbol
        let symbol: String
        if let symbolHex = symbolResult.constant_result?.first {
            symbol = Self.decodeAbiString(from: symbolHex)
        } else {
            symbol = ""
        }

        // Decode decimals
        let decimals: Int
        if let decimalsHex = decimalsResult.constant_result?.first {
            decimals = Int(decimalsHex, radix: 16) ?? 0
        } else {
            decimals = 0
        }

        return (name, symbol, decimals)
    }

    /// Decodes an ABI-encoded string from a hex result.
    /// ABI strings have: 32 bytes offset, 32 bytes length, then the string data.
    private static func decodeAbiString(from hex: String) -> String {
        guard let data = Data(hexString: hex), data.count >= 64 else {
            return ""
        }

        let lengthData = data[32..<64]
        let length = Int(BigInt(Data(lengthData)))

        guard length > 0, data.count >= 64 + length else {
            return ""
        }

        let stringData = data[64..<(64 + length)]
        return String(data: stringData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
    }

    // MARK: - Balance

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
