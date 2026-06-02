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

    /// Resolves the TRON custom RPC override. Injected so the API values are
    /// built from a dependency rather than a global reach-in; resolution happens
    /// per request inside `api(_:)` so a runtime override change is picked up
    /// live. The default host stays the Vultisig proxy (REST), so default users
    /// are unaffected; an override only swaps the host.
    private let resolver: RPCEndpointResolving

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) {
        self.httpClient = httpClient
        self.resolver = resolver
    }

    /// The override-aware TRON REST host. Falls back to the default proxy host
    /// when no override is set.
    private var resolvedHost: URL {
        if let override = resolver.url(for: .tron), let url = URL(string: override) {
            return url
        }
        return TronAPI.defaultHost
    }

    /// Builds a pure `TronAPI` value with the resolved host baked in. The
    /// `TargetType` itself never consults the resolver.
    private func api(_ endpoint: TronAPI.Endpoint) -> TronAPI {
        TronAPI(endpoint, host: resolvedHost)
    }

    // MARK: - Block Info

    func getNowBlock() async throws -> TronNowBlockResponse {
        let response = try await httpClient.request(api(.getNowBlock), responseType: TronNowBlockResponse.self)
        return response.data
    }

    // MARK: - Account

    func getAccount(address: String) async throws -> TronAccountResponse {
        let response = try await httpClient.request(api(.getAccount(address: address)), responseType: TronAccountResponse.self)
        return response.data
    }

    func getAccountResource(address: String) async throws -> TronAccountResourceResponse {
        let response = try await httpClient.request(api(.getAccountResource(address: address)), responseType: TronAccountResourceResponse.self)
        return response.data
    }

    // MARK: - Chain Parameters

    func getChainParameters() async throws -> TronChainParametersResponse {
        let response = try await httpClient.request(api(.getChainParameters), responseType: TronChainParametersResponse.self)
        return response.data
    }

    // MARK: - Broadcast

    private static let DUP_TRANSACTION_ERROR_CODE = "DUP_TRANSACTION_ERROR"

    func broadcastTransaction(jsonString: String) async throws -> String {
        let response = try await httpClient.request(api(.broadcastTransaction(jsonString: jsonString)), responseType: TronBroadcastResponse.self)

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

    // MARK: - Contract simulation

    /// Simulates a TRC20 `transfer(address,uint256)` call via TRON's
    /// `/wallet/triggerconstantcontract` endpoint and returns the decoded
    /// response (`energy_used` is the field consumed by fee estimation).
    /// A placeholder `amount` of `1` is used — energy cost of an ERC20-style
    /// transfer is dominated by storage-slot writes and is effectively
    /// constant across amounts on typical TRC20 contracts.
    ///
    /// See https://developers.tron.network/docs/resource-model#dynamic-energy-model.
    func simulateTRC20Transfer(
        ownerAddress: String,
        contractAddress: String,
        toAddress: String
    ) async throws -> TronTriggerConstantResponse {
        let parameter = try Self.encodeTrc20TransferParameter(toAddress: toAddress, amount: 1)
        let response = try await httpClient.request(
            api(.triggerConstantContract(
                ownerAddress: ownerAddress,
                contractAddress: contractAddress,
                functionSelector: "transfer(address,uint256)",
                parameter: parameter
            )),
            responseType: TronTriggerConstantResponse.self
        )
        return response.data
    }

    /// ABI-encodes `(address, uint256)` for `transfer(address,uint256)`.
    /// Strips the TRON `41` prefix from the decoded base58 address so the
    /// resulting hex matches the EVM-style 20-byte address that the TVM
    /// expects in the calldata.
    private static func encodeTrc20TransferParameter(
        toAddress: String,
        amount: BigInt
    ) throws -> String {
        guard let toAddressData = Base58.decode(string: toAddress) else {
            throw TronAPIError.invalidAddress
        }
        var addressHex = toAddressData.hexString
        if addressHex.lowercased().hasPrefix("41") {
            addressHex = String(addressHex.dropFirst(2))
        }
        // Reject any payload that doesn't yield a canonical 20-byte (40 hex chars)
        // address after stripping the optional TRON `41` prefix. Without this
        // guard, a malformed base58 input could produce ABI calldata that the
        // TVM silently accepts but simulates against the wrong recipient,
        // returning a misleading `energy_used`.
        guard addressHex.count == 40 else {
            throw TronAPIError.invalidAddress
        }
        let paddedAddress = String(repeating: "0", count: max(0, 64 - addressHex.count)) + addressHex

        let amountHex = String(amount, radix: 16)
        let paddedAmount = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex

        return paddedAddress + paddedAmount
    }

    // MARK: - Token Info

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        // Use a zero-padded dummy parameter (required by triggerConstantContract but not used by these view functions)
        let emptyParameter = String(repeating: "0", count: 64)

        // Fetch all three in parallel
        async let nameResponse = httpClient.request(
            api(.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "name()",
                parameter: emptyParameter
            )),
            responseType: TronTriggerConstantResponse.self
        )

        async let symbolResponse = httpClient.request(
            api(.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "symbol()",
                parameter: emptyParameter
            )),
            responseType: TronTriggerConstantResponse.self
        )

        async let decimalsResponse = httpClient.request(
            api(.triggerConstantContract(
                ownerAddress: contractAddress,
                contractAddress: contractAddress,
                functionSelector: "decimals()",
                parameter: emptyParameter
            )),
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
            api(.triggerConstantContract(
                ownerAddress: walletAddress,
                contractAddress: contractAddress,
                functionSelector: "balanceOf(address)",
                parameter: parameter
            )),
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
