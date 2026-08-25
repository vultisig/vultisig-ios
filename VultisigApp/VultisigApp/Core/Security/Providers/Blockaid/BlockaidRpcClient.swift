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
        let request = try buildEthereumScanRequest(
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

    func simulateEVMTransaction(
        chain: Chain,
        from: String,
        to: String,
        amount: String,
        data: String
    ) async throws -> BlockaidEvmSimulationResponseJson {
        let request = try buildEthereumSimulateRequest(
            chain: chain,
            from: from,
            to: to,
            data: data,
            amount: amount
        )
        let response = try await httpClient.request(
            BlockaidAPI.simulateEVMTransaction(request),
            responseType: BlockaidEvmSimulationResponseJson.self
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

    func simulateSolanaTransaction(
        address: String,
        rawTransactions: [String]
    ) async throws -> BlockaidSolanaSimulationResponseJson {
        let request = buildSolanaSimulateRequest(address: address, rawTransactions: rawTransactions)
        let response = try await httpClient.request(
            BlockaidAPI.scanSolanaTransaction(request),
            responseType: BlockaidSolanaSimulationResponseJson.self
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
            chain: BlockaidChainIdentifier.name(for: .bitcoin) ?? "bitcoin",
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
    ) throws -> EthereumScanTransactionRequestJson {
        guard let blockaidChain = BlockaidChainIdentifier.name(for: chain) else {
            throw BlockaidScannerError.scannerError(
                "Chain \(chain) is not supported",
                payload: nil
            )
        }
        return EthereumScanTransactionRequestJson(
            chain: blockaidChain,
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

    func buildEthereumSimulateRequest(
        chain: Chain,
        from: String,
        to: String,
        data: String,
        amount: String
    ) throws -> EthereumSimulateTransactionRequestJson {
        guard let blockaidChain = BlockaidChainIdentifier.name(for: chain) else {
            throw BlockaidScannerError.scannerError(
                "Chain \(chain) is not supported",
                payload: nil
            )
        }
        return EthereumSimulateTransactionRequestJson(
            data: EthereumSimulateTransactionRequestJson.DataJson(
                method: "eth_sendTransaction",
                params: [
                    EthereumSimulateTransactionRequestJson.DataJson.ParamsJson(
                        from: from,
                        to: to,
                        value: amount,
                        data: data
                    )
                ]
            ),
            chain: blockaidChain,
            metadata: EthereumSimulateTransactionRequestJson.MetadataJson(
                domain: BlockaidConstants.vultisigDomain
            ),
            options: ["simulation", "validation"]
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

    func buildSolanaSimulateRequest(
        address: String,
        rawTransactions: [String]
    ) -> SolanaScanTransactionRequestJson {
        // Ask for both simulation AND validation in the same call so the dApp
        // hero gets balance changes + the "Scanned by Blockaid" header state
        // without a second round-trip.
        return SolanaScanTransactionRequestJson(
            chain: BlockaidConstants.solanaChain,
            metadata: CommonMetadataJson(url: BlockaidConstants.vultisigDomain),
            options: ["simulation", "validation"],
            accountAddress: address,
            encoding: BlockaidConstants.solanaEncoding,
            transactions: rawTransactions,
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
