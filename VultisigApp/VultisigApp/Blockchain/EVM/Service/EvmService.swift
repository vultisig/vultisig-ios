//
//  EvmService.swift
//  VultisigApp
//
//  Enum-based EVM service - value types only, no classes
//

import Foundation
import BigInt

enum EvmService {
    case ethereum
    case ethereumSepolia
    case bscChain
    case avalanche
    case base
    case arbitrum
    case polygon
    case polygonV2
    case optimism
    case blast
    case cronosChain
    case zksync
    case mantle
    case hyperliquid
    case sei
    case tron

    // MARK: - Constants

    static let defaultMantleSwapLimit = BigInt("3000000000")

    // MARK: - Factory Methods

    /// Get EVM service for a chain - returns enum (value type)
    static func getService(forChain chain: Chain) throws -> EvmService {
        return try forChain(chain)
    }

    /// Alternative factory method
    static func forChain(_ chain: Chain) throws -> EvmService {
        switch chain {
        case .ethereum:
            return .ethereum
        case .ethereumSepolia:
            return .ethereumSepolia
        case .bscChain:
            return .bscChain
        case .avalanche:
            return .avalanche
        case .base:
            return .base
        case .arbitrum:
            return .arbitrum
        case .polygon:
            return .polygon
        case .polygonV2:
            return .polygonV2
        case .optimism:
            return .optimism
        case .blast:
            return .blast
        case .cronosChain:
            return .cronosChain
        case .zksync:
            return .zksync
        case .mantle:
            return .mantle
        case .hyperliquid:
            return .hyperliquid
        case .sei:
            return .sei
        case .tron:
            return .tron
        default:
            throw RpcEvmServiceError.rpcError(code: 500, message: "EVM service not found")
        }
    }

    // MARK: - Configuration

    var rpcEndpoint: String {
        switch self {
        case .ethereum:
            return Endpoint.ethServiceRpcService
        case .ethereumSepolia:
            return Endpoint.ethSepoliaServiceRpcService
        case .bscChain:
            return Endpoint.bscServiceRpcService
        case .avalanche:
            return Endpoint.avalancheServiceRpcService
        case .base:
            return Endpoint.baseServiceRpcService
        case .arbitrum:
            return Endpoint.arbitrumOneServiceRpcService
        case .polygon, .polygonV2:
            return Endpoint.polygonServiceRpcService
        case .optimism:
            return Endpoint.optimismServiceRpcService
        case .blast:
            return Endpoint.blastServiceRpcService
        case .cronosChain:
            return Endpoint.cronosServiceRpcService
        case .zksync:
            return Endpoint.zksyncServiceRpcService
        case .mantle:
            return Endpoint.mantleServiceRpcService
        case .hyperliquid:
            return Endpoint.hyperliquidServiceRpcService
        case .sei:
            return Endpoint.seiServiceRpcService
        case .tron:
            return Endpoint.tronEvmServiceRpc
        }
    }

    var tokenProvider: EvmServiceConfig.TokenProvider {
        switch self {
        case .ethereumSepolia:
            return .sepolia
        default:
            return .standard
        }
    }

    // MARK: - Service Implementation

    private var service: EvmServiceStruct {
        get throws {
            let config = EvmServiceConfig(
                chain: chain,
                rpcEndpoint: rpcEndpoint,
                tokenProvider: tokenProvider
            )
            return try EvmServiceStruct(config: config)
        }
    }

    var chain: Chain {
        switch self {
        case .ethereum:
            return .ethereum
        case .ethereumSepolia:
            return .ethereumSepolia
        case .bscChain:
            return .bscChain
        case .avalanche:
            return .avalanche
        case .base:
            return .base
        case .arbitrum:
            return .arbitrum
        case .polygon:
            return .polygon
        case .polygonV2:
            return .polygonV2
        case .optimism:
            return .optimism
        case .blast:
            return .blast
        case .cronosChain:
            return .cronosChain
        case .zksync:
            return .zksync
        case .mantle:
            return .mantle
        case .hyperliquid:
            return .hyperliquid
        case .sei:
            return .sei
        case .tron:
            return .tron
        }
    }

    // MARK: - Protocol Methods

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        return try await (try service).getBalance(coin: coin, address: address)
    }

    func getCode(address: String) async throws -> String {
        return try await (try service).getCode(address: address)
    }

    func fetchContractOwner(contractAddress: String) async -> String? {
        return await (try? service)?.fetchContractOwner(contractAddress: contractAddress)
    }

    func getGasInfo(fromAddress: String, mode: FeeMode) async throws -> (gasPrice: BigInt, priorityFee: BigInt, nonce: Int64) {
        return try await (try service).getGasInfo(fromAddress: fromAddress, mode: mode)
    }

    func fetchMaxPriorityFeesPerGas() async throws -> [FeeMode: BigInt] {
        return try await (try service).fetchMaxPriorityFeesPerGas()
    }

    func getFeeHistory() async throws -> [BigInt] {
        return try await (try service).getFeeHistory()
    }

    func getBaseFee() async throws -> BigInt {
        return try await (try service).getBaseFee()
    }

    func getGasInfoZk(fromAddress: String, toAddress: String, memo: String = "0xffffffff") async throws -> (gasLimit: BigInt, gasPerPubdataLimit: BigInt, maxFeePerGas: BigInt, maxPriorityFeePerGas: BigInt, nonce: Int64) {
        return try await (try service).getGasInfoZk(fromAddress: fromAddress, toAddress: toAddress, memo: memo)
    }

    func broadcastTransaction(hex: String) async throws -> String {
        return try await (try service).broadcastTransaction(hex: hex)
    }

    func estimateGasForEthTransaction(senderAddress: String, recipientAddress: String, value: BigInt, memo: String?) async throws -> BigInt {
        return try await (try service).estimateGasForEthTransaction(senderAddress: senderAddress, recipientAddress: recipientAddress, value: value, memo: memo)
    }

    func estimateGasForERC20Transfer(senderAddress: String, contractAddress: String, recipientAddress: String, value: BigInt) async throws -> BigInt {
        return try await (try service).estimateGasForERC20Transfer(senderAddress: senderAddress, contractAddress: contractAddress, recipientAddress: recipientAddress, value: value)
    }

    func estimateGasLimitForSwap(senderAddress: String, toAddress: String, value: BigInt, data: String) async throws -> BigInt {
        return try await (try service).estimateGasLimitForSwap(senderAddress: senderAddress, toAddress: toAddress, value: value, data: data)
    }

    func fetchERC20TokenBalance(contractAddress: String, walletAddress: String) async throws -> BigInt {
        return try await (try service).fetchERC20TokenBalance(contractAddress: contractAddress, walletAddress: walletAddress)
    }

    func fetchAllowance(contractAddress: String, owner: String, spender: String) async throws -> BigInt {
        return try await (try service).fetchAllowance(contractAddress: contractAddress, owner: owner, spender: spender)
    }

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        return try await (try service).getTokenInfo(contractAddress: contractAddress)
    }

    func getTokens(nativeToken: CoinMeta, address: String) async throws -> [CoinMeta] {
        return await (try service).getTokens(nativeToken: nativeToken, address: address)
    }

    func resolveENS(ensName: String) async throws -> String {
        return try await (try service).resolveENS(ensName: ensName)
    }
}
