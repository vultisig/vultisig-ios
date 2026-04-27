//
//  CardanoService.swift
//  VultisigApp
//

import Foundation
import BigInt
import OSLog

class CardanoService {

    static let shared = CardanoService()

    private let logger = Logger(subsystem: "com.vultisig.app", category: "cardano-service")
    private let httpClient: HTTPClientProtocol

    private init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getBalance(address: String) async throws -> String {
        do {
            let response = try await httpClient.request(
                CardanoAPI.addressInfo(addresses: [address]),
                responseType: [CardanoAddressInfo].self
            )
            return response.data.first?.balance ?? "0"
        } catch {
            return "0"
        }
    }

    func getUTXOs(coin: Coin) async throws -> [UtxoInfo] {
        do {
            let response = try await httpClient.request(
                CardanoAPI.addressUtxos(addresses: [coin.address]),
                responseType: [CardanoUtxoEntry].self
            )

            return response.data.compactMap { utxo in
                guard let valueInt = Int64(utxo.value) else { return nil }
                return UtxoInfo(
                    hash: utxo.txHash,
                    amount: valueInt,
                    index: UInt32(utxo.txIndex)
                )
            }
        } catch {
            return []
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
            CardanoAPI.tip,
            responseType: [CardanoTipEntry].self
        )

        guard let tip = response.data.first else {
            throw NSError(domain: "CardanoServiceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse slot from response"])
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
    func validateMinimumAmount(_ amountInLovelaces: BigInt) throws {
        let minUTXOValue = CardanoHelper.defaultMinUTXOValue

        guard amountInLovelaces >= minUTXOValue else {
            let minAmountADA = minUTXOValue.toADAString
            let sendAmountADA = amountInLovelaces.toADAString
            throw NSError(
                domain: "CardanoServiceError",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: "Amount \(sendAmountADA) ADA is below the minimum UTXO requirement of \(minAmountADA) ADA. Cardano protocol (Alonzo era) requires this minimum to prevent spam and maintain network efficiency."
                ]
            )
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
            throw NSError(
                domain: "CardanoServiceError",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey: validation.errorMessage ?? "Cardano UTXO validation failed"
                ]
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
            throw NSError(domain: "CardanoServiceError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid chain specific type for Cardano"])
        }

        guard byteFee > 0 else {
            throw NSError(domain: "CardanoServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cardano byte fee must be positive"])
        }

        let currentSlot = try await getCurrentSlot()
        guard ttl > currentSlot else {
            throw NSError(domain: "CardanoServiceError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cardano TTL must be greater than current slot"])
        }
    }

    /// Broadcast a signed Cardano transaction using Vultisig API Proxy (Ogmios JSON-RPC)
    /// - Parameter signedTransaction: The signed transaction in CBOR hex format
    /// - Returns: The transaction hash
    func broadcastTransaction(signedTransaction: String) async throws -> String {
        // The endpoint returns 200 on success and 400 with a JSON-RPC error
        // envelope on Ogmios-level errors (e.g. code 3117 "already in mempool").
        // The TargetType accepts both codes; decode the envelope here, but if
        // the 400 body isn't a recognisable JSON-RPC envelope, surface the
        // raw body in an HTTP-style error rather than a generic decoding error.
        let raw = try await httpClient.request(CardanoAPI.submitTransaction(cbor: signedTransaction))
        let body: CardanoSubmitTransactionResponse
        do {
            body = try JSONDecoder().decode(CardanoSubmitTransactionResponse.self, from: raw.data)
        } catch {
            let bodyText = String(data: raw.data, encoding: .utf8) ?? "<non-utf8 body>"
            throw NSError(
                domain: "CardanoServiceError",
                code: raw.response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(raw.response.statusCode): \(bodyText)"]
            )
        }

        if let error = body.error {
            if error.code == 3117 {
                // "The transaction contains unknown UTxO references as inputs."
                // Usually means another TSS device already broadcast it. Hash locally.
                if let txData = Data(hexString: signedTransaction) {
                    let txId = CardanoHelper.calculateCardanoTransactionHash(from: txData)
                    logger.info("Transaction already in mempool (3117). Returning local hash: \(txId)")
                    return txId
                }
            }

            throw NSError(
                domain: "CardanoServiceError",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "RPC Error: \(error.message ?? "code \(error.code)")"]
            )
        }

        guard let txId = body.result?.transaction.id else {
            throw NSError(
                domain: "CardanoServiceError",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Missing result in RPC response"]
            )
        }

        return txId
    }
}
