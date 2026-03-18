//
//  CardanoService.swift
//  VultisigApp
//

import Foundation
import BigInt

class CardanoService {

    static let shared = CardanoService()

    private init() {}

    func getBalance(address: String) async throws -> String {
        let url = URL(string: Endpoint.fetchCardanoBalance())!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Koios API expects JSON body with addresses array
        let requestBody = [
            "_addresses": [address]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "0"
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return "0"
            }

            // Parse Koios API response - it returns a direct array, not wrapped in "data"
            guard let dataArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return "0"
            }

            guard let addressInfo = dataArray.first else {
                return "0"
            }

            guard let balanceString = addressInfo["balance"] as? String else {
                return "0"
            }

            return balanceString

        } catch {
            return "0"
        }
    }

    func getUTXOs(coin: Coin) async throws -> [UtxoInfo] {
        let url = URL(string: Endpoint.fetchCardanoUTXOs())!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Koios API expects JSON body with addresses array
        let requestBody = [
            "_addresses": [coin.address]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return []
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            // Parse Koios API response for UTXOs
            guard let dataArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            var utxos: [UtxoInfo] = []

            for utxoData in dataArray {
                guard let txHash = utxoData["tx_hash"] as? String,
                      let txIndex = utxoData["tx_index"] as? Int,
                      let value = utxoData["value"] as? String,
                      let valueInt = Int64(value) else {
                    continue
                }

                let utxo = UtxoInfo(
                    hash: txHash,
                    amount: valueInt,
                    index: UInt32(txIndex)
                )
                utxos.append(utxo)
            }

            return utxos

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
        let url = URL(string: "https://api.koios.rest/api/v1/tip")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CardanoServiceError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "CardanoServiceError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
        }

        // Koios API returns an array with one object
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let tipInfo = jsonArray.first,
              let absSlot = tipInfo["abs_slot"] as? UInt64 else {
            throw NSError(domain: "CardanoServiceError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse slot from response"])
        }

        return absSlot
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
    /// - Parameters:
    ///   - sendAmount: Amount to send in lovelaces
    ///   - totalBalance: Total available balance in lovelaces
    ///   - estimatedFee: Estimated transaction fee in lovelaces
    /// - Throws: Error if transaction would violate minimum UTXO requirements
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

        // Also check for proactive "Send Max" recommendations
        let sendMaxRecommendation = CardanoHelper.shouldRecommendSendMax(
            totalBalance: totalBalance,
            estimatedFee: estimatedFee
        )

        if sendMaxRecommendation.shouldRecommend {
            // Log recommendation but don't throw error
            print("Cardano Service: \(sendMaxRecommendation.message ?? "Consider Send Max")")
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

        // TTL is an absolute slot number, so compare with current slot, not UNIX timestamp
        let currentSlot = try await getCurrentSlot()
        guard ttl > currentSlot else {
            throw NSError(domain: "CardanoServiceError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cardano TTL must be greater than current slot"])
        }
    }

    /// Broadcast a signed Cardano transaction using Vultisig API Proxy (JSON-RPC)
    /// - Parameter signedTransaction: The signed transaction in CBOR hex format
    /// - Returns: The transaction hash
    func broadcastTransaction(signedTransaction: String) async throws -> String {
        let url = Endpoint.cardanoBroadcast()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Construct JSON-RPC request
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "submitTransaction",
            "params": [
                "transaction": ["cbor": signedTransaction]
            ],
            "id": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CardanoServiceError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Try to parse JSON response first, as it might contain specific error codes we want to handle (like 3117)
        // even if the HTTP status code is an error (e.g., 400)
        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Check for RPC error
            if let error = jsonResponse["error"] as? [String: Any] {
                if let code = error["code"] as? Int, code == 3117 {
                    // Error 3117: "The transaction contains unknown UTxO references as inputs."
                    // This usually means the transaction was already broadcasted by another device in TSS.
                    // We should calculate the hash locally and return it as success.
                    if let txData = Data(hexString: signedTransaction) {
                        let txId = CardanoHelper.calculateCardanoTransactionHash(from: txData)
                        print("Cardano Service: Transaction already in mempool (3117). Returning local hash: \(txId)")
                        return txId
                    }
                }

                // If it's another error and status code is bad, we'll throw later or here
                if let message = error["message"] as? String {
                     // If we have a specific error message from RPC, prefer it over generic HTTP error
                     throw NSError(domain: "CardanoServiceError", code: 9, userInfo: [NSLocalizedDescriptionKey: "RPC Error: \(message)"])
                }
            }

            // Extract result (transaction hash)
            // Response structure: { "result": { "transaction": { "id": "hash" } } }
            if let result = jsonResponse["result"] as? [String: Any],
               let transaction = result["transaction"] as? [String: Any],
               let txId = transaction["id"] as? String {
                return txId
            }
        }

        // If we haven't returned yet, check HTTP status code
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to get error message from response
            var errorDetail = "HTTP \(httpResponse.statusCode)"
            if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                errorDetail += ": \(responseString)"
            }
            throw NSError(domain: "CardanoServiceError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Broadcast failed: \(errorDetail)"])
        }

        // If we got here, it means status was 200 OK but we failed to parse JSON or find result
        // Try to parse JSON again for debugging message if possible
        let jsonString = String(data: data, encoding: .utf8) ?? "invalid data"
        throw NSError(domain: "CardanoServiceError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing result in RPC response: \(jsonString)"])
    }
}
