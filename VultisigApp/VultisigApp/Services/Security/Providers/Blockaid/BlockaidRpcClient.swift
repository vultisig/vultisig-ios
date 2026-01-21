//
//  BlockaidRpcClient.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/07/2025.
//

import Foundation

// MARK: - BlockaidRpcClient Implementation

struct BlockaidRpcClient: BlockaidRpcClientProtocol {
    
    private let httpClient: HTTPClientProtocol
    
    init(httpClient: HTTPClientProtocol) {
        self.httpClient = httpClient
    }
    
    func scanBitcoinTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        let request = buildBitcoinScanRequest(address: address, serializedTransaction: serializedTransaction)
        let response = try await httpClient.request(
            BlockaidAPI.scanBitcoinTransaction(request),
            responseType: BlockaidTransactionScanResponseJson.self
        )
        return response.data
    }
    
    func scanEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        let request = buildEthereumScanRequest(
            chain: chain,
            from: from,
            to: to,
            data: data,
            amount: amount
        )
        let response = try await httpClient.request(
            BlockaidAPI.scanEVMTransaction(request),
            responseType: BlockaidTransactionScanResponseJson.self
        )
        return response.data
    }
    
    func scanSolanaTransaction(
        address: String,
        serializedMessage: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        let request = buildSolanaScanRequest(address: address, serializedMessage: serializedMessage)
        let response = try await httpClient.request(
            BlockaidAPI.scanSolanaTransaction(request),
            responseType: BlockaidTransactionScanResponseJson.self
        )
        return response.data
    }
    
    func scanSuiTransaction(
        address: String,
        serializedTransaction: String
    ) async throws -> BlockaidTransactionScanResponseJson {
        let request = buildSuiScanRequest(address: address, serializedTransaction: serializedTransaction)
        let response = try await httpClient.request(
            BlockaidAPI.scanSuiTransaction(request),
            responseType: BlockaidTransactionScanResponseJson.self
        )
        return response.data
    }
}

// MARK: - Private Helper Methods

private extension BlockaidRpcClient {
    
    func buildBitcoinScanRequest(
        address: String,
        serializedTransaction: String
    ) -> BitcoinScanTransactionRequestJson {
        return BitcoinScanTransactionRequestJson(
            chain: Chain.bitcoin.toBlockaidName(),
            metadata: CommonMetadataJson(url: BlockaidConstants.vultisigDomain),
            options: ["validation"],
            accountAddress: address,
            transaction: serializedTransaction
        )
    }
    
    func buildEthereumScanRequest(
        chain: Chain,
        from: String,
        to: String,
        data: String,
        amount: String
    ) -> EthereumScanTransactionRequestJson {
        return EthereumScanTransactionRequestJson(
            chain: chain.toBlockaidName(),
            metadata: EthereumScanTransactionRequestJson.MetadataJson(
                domain: BlockaidConstants.vultisigDomain
            ),
            options: ["validation"],
            accountAddress: from,
            data: EthereumScanTransactionRequestJson.DataJson(
                from: from,
                to: to,
                data: data,
                value: amount
            ),
            simulatedWithEstimatedGas: false
        )
    }
    
    func buildSolanaScanRequest(
        address: String,
        serializedMessage: String
    ) -> SolanaScanTransactionRequestJson {
        return SolanaScanTransactionRequestJson(
            chain: BlockaidConstants.solanaChain,
            metadata: CommonMetadataJson(url: BlockaidConstants.vultisigDomain),
            options: ["validation"],
            accountAddress: address,
            encoding: BlockaidConstants.solanaEncoding,
            transactions: [serializedMessage],
            method: BlockaidConstants.solanaSignAndSend
        )
    }
    
    func buildSuiScanRequest(
        address: String,
        serializedTransaction: String
    ) -> SuiScanTransactionRequestJson {
        return SuiScanTransactionRequestJson(
            chain: BlockaidConstants.suiChain,
            metadata: CommonMetadataJson(url: BlockaidConstants.vultisigDomain),
            options: ["validation"],
            accountAddress: address,
            transaction: serializedTransaction
        )
    }
}

// MARK: - Chain Extension

private extension Chain {
    func toBlockaidName() -> String {
        switch self {
        case .arbitrum:
            return "arbitrum"
        case .avalanche:
            return "avalanche"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .bscChain:
            return "bsc"
        case .bitcoin:
            return "bitcoin"
        case .ethereum:
            return "ethereum"
        case .optimism:
            return "optimism"
        case .polygon, .polygonV2:
            return "polygon"
        case .sui:
            return "sui"
        case .solana:
            return "solana"
        default:
            return .empty
        }
    }
}
