//
//  CardanoService.swift
//  VultisigApp
//

import Foundation
import BigInt
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "cardano-service")

class CardanoService {

    static let shared = CardanoService()

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getBalance(address: String) async throws -> String {
        let response = try await httpClient.request(
            CardanoAPI.getAddressInfo(address: address),
            responseType: CardanoAddressInfoResponse.self
        )

        return response.data.addresses.first?.balance ?? "0"
    }

    /// Fetch the balance of a specific Cardano native token
    /// contractAddress format: policyId + assetNameHex (the "unit" in Koios terminology)
    func getTokenBalance(address: String, contractAddress: String) async throws -> String {
        let response = try await httpClient.request(
            CardanoAPI.getAddressInfo(address: address),
            responseType: CardanoAddressInfoResponse.self
        )

        guard let addressInfo = response.data.addresses.first else {
            return "0"
        }

        let unit = contractAddress.lowercased()
        let assets = addressInfo.utxoSet.flatMap(\.assetList)

        for asset in assets {
            let assetUnit = (asset.policyId + asset.assetName).lowercased()
            if assetUnit == unit {
                return asset.quantity
            }
        }

        return "0"
    }

    func getUTXOs(coin: Coin) async throws -> [UtxoInfo] {
        let response = try await httpClient.request(
            CardanoAPI.getAddressInfo(address: coin.address),
            responseType: CardanoAddressInfoResponse.self
        )

        guard let addressInfo = response.data.addresses.first else {
            return []
        }

        return addressInfo.utxoSet.compactMap { utxo in
            guard let valueInt = Int64(utxo.value) else { return nil }

            let tokenAssets: [CardanoTokenAsset]? = utxo.assetList.isEmpty ? nil : utxo.assetList.map {
                CardanoTokenAsset(policyId: $0.policyId, assetNameHex: $0.assetName, amount: $0.quantity)
            }

            return UtxoInfo(
                hash: utxo.txHash,
                amount: valueInt,
                index: UInt32(utxo.txIndex),
                cardanoTokens: tokenAssets
            )
        }
    }

    func estimateTransactionFee() -> Int {
        // Use typical Cardano transaction fee range
        // Simple ADA transfers are usually around 170,000-200,000 lovelace (0.17-0.2 ADA)
        // This is much more reliable than trying to calculate from network parameters
        return 180000 // 0.18 ADA - middle of typical range
    }

    /// Fetch current Cardano slot from Koios API
    /// This is used for dynamic TTL calculation to ensure all TSS devices use the same slot reference
    func getCurrentSlot() async throws -> UInt64 {
        let response = try await httpClient.request(
            CardanoAPI.getTip,
            responseType: CardanoTipResponse.self
        )

        guard let tip = response.data.tips.first else {
            throw CardanoServiceError.failedToParseSlot
        }

        return tip.absSlot
    }

    /// Calculate TTL as current slot + 720 slots (approximately 12 minutes)
    /// This ensures all TSS devices get the same TTL when fetching chain specific data
    func calculateDynamicTTL() async throws -> UInt64 {
        let currentSlot = try await getCurrentSlot()
        return currentSlot + 720 // Add 720 slots (~12 minutes at 1 slot per second)
    }

    /// Validate that the amount meets Cardano's minimum UTXO requirements (Alonzo Era)
    /// Current protocol: minUTxO = utxoEntrySize × coinsPerUTxOWord ≈ 0.93 ADA for simple transactions
    /// - Parameter amountInLovelaces: The amount to send in lovelaces (smallest Cardano unit)
    /// - Throws: Error if amount is below minimum UTXO value
    func validateMinimumAmount(_ amountInLovelaces: BigInt) throws {
        let minUTXOValue = CardanoHelper.defaultMinUTXOValue

        guard amountInLovelaces >= minUTXOValue else {
            let minAmountADA = minUTXOValue.toADAString
            let sendAmountADA = amountInLovelaces.toADAString
            throw CardanoServiceError.belowMinimumUTXO(sendAmount: sendAmountADA, minimumAmount: minAmountADA)
        }
    }

    /// Comprehensive validation for Cardano transactions including change/remaining balance validation
    func validateTransaction(sendAmount: BigInt, totalBalance: BigInt, estimatedFee: BigInt) throws {
        let validation = CardanoHelper.validateUTXORequirements(
            sendAmount: sendAmount,
            totalBalance: totalBalance,
            estimatedFee: estimatedFee
        )

        if !validation.isValid {
            throw CardanoServiceError.utxoValidationFailed(
                validation.errorMessage ?? "Cardano UTXO validation failed"
            )
        }

        let sendMaxRecommendation = CardanoHelper.shouldRecommendSendMax(
            totalBalance: totalBalance,
            estimatedFee: estimatedFee
        )

        if sendMaxRecommendation.shouldRecommend {
            logger.info("\(sendMaxRecommendation.message ?? "Consider Send Max")")
        }
    }

    /// Validate Cardano chain specific parameters
    func validateChainSpecific(_ chainSpecific: BlockChainSpecific) async throws {
        guard case .Cardano(let byteFee, _, let ttl) = chainSpecific else {
            throw CardanoServiceError.invalidChainSpecific
        }

        guard byteFee > 0 else {
            throw CardanoServiceError.invalidByteFee
        }

        let currentSlot = try await getCurrentSlot()
        guard ttl > currentSlot else {
            throw CardanoServiceError.expiredTTL
        }
    }

    /// Broadcast a signed Cardano transaction using Vultisig API Proxy (JSON-RPC)
    /// - Parameter signedTransaction: The signed transaction in CBOR hex format
    /// - Returns: The transaction hash
    func broadcastTransaction(signedTransaction: String) async throws -> String {
        let response: HTTPResponse<Data>
        do {
            response = try await httpClient.request(
                CardanoAPI.broadcastTransaction(cborHex: signedTransaction)
            )
        } catch let error as HTTPError {
            // For HTTP errors, try to parse the response body for RPC error codes
            if case .statusCode(_, let data) = error, let data {
                if let txId = try? handleBroadcastResponse(data: data, signedTransaction: signedTransaction) {
                    return txId
                }
            }
            throw error
        }

        return try handleBroadcastResponse(data: response.data, signedTransaction: signedTransaction)
    }

    // MARK: - Private

    private func handleBroadcastResponse(data: Data, signedTransaction: String) throws -> String {
        guard let response = try? JSONDecoder().decode(CardanoBroadcastResponse.self, from: data) else {
            let jsonString = String(data: data, encoding: .utf8) ?? "invalid data"
            throw CardanoServiceError.invalidBroadcastResponse(jsonString)
        }

        // Check for RPC error
        if let error = response.error {
            if error.code == 3117 {
                // Error 3117: Transaction already broadcasted by another TSS device
                if let txData = Data(hexString: signedTransaction) {
                    let txId = CardanoHelper.calculateCardanoTransactionHash(from: txData)
                    logger.info("Transaction already in mempool (3117). Returning local hash: \(txId)")
                    return txId
                }
            }

            throw CardanoServiceError.rpcError(error.message)
        }

        if let txId = response.result?.transaction.id {
            return txId
        }

        let jsonString = String(data: data, encoding: .utf8) ?? "invalid data"
        throw CardanoServiceError.invalidBroadcastResponse(jsonString)
    }
}

// MARK: - Error

enum CardanoServiceError: Error, LocalizedError {
    case failedToParseSlot
    case belowMinimumUTXO(sendAmount: String, minimumAmount: String)
    case utxoValidationFailed(String)
    case invalidChainSpecific
    case invalidByteFee
    case expiredTTL
    case rpcError(String)
    case invalidBroadcastResponse(String)

    var errorDescription: String? {
        switch self {
        case .failedToParseSlot:
            return "Failed to parse slot from Koios response"
        case .belowMinimumUTXO(let sendAmount, let minimumAmount):
            return "Amount \(sendAmount) ADA is below the minimum UTXO requirement of \(minimumAmount) ADA. Cardano protocol (Alonzo era) requires this minimum to prevent spam and maintain network efficiency."
        case .utxoValidationFailed(let message):
            return message
        case .invalidChainSpecific:
            return "Invalid chain specific type for Cardano"
        case .invalidByteFee:
            return "Cardano byte fee must be positive"
        case .expiredTTL:
            return "Cardano TTL must be greater than current slot"
        case .rpcError(let message):
            return "RPC Error: \(message)"
        case .invalidBroadcastResponse(let response):
            return "Missing result in RPC response: \(response)"
        }
    }
}
