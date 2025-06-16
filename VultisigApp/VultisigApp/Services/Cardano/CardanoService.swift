//
//  CardanoService.swift
//  VultisigApp
//

import Foundation
import BigInt

class CardanoService {
    
    static let shared = CardanoService()
    
    private init() {}
    
    func getBalance(coin: Coin) async throws -> String {
        let url = URL(string: Endpoint.fetchCardanoBalance(address: coin.address))!
        
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
        let url = URL(string: Endpoint.fetchCardanoUTXOs(address: coin.address))!
        
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
            let minAmountADA = Double(minUTXOValue) / 1_000_000.0
            throw NSError(
                domain: "CardanoServiceError", 
                code: 5, 
                userInfo: [
                    NSLocalizedDescriptionKey: "Amount \(Double(amountInLovelaces) / 1_000_000.0) ADA is below the minimum UTXO requirement of \(minAmountADA) ADA. Cardano protocol (Alonzo era) requires this minimum to prevent spam and maintain network efficiency."
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
        guard case .Cardano(let byteFee, let sendMaxAmount, let ttl) = chainSpecific else {
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
    
} 
