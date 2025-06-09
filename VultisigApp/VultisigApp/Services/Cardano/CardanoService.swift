//
//  CardanoService.swift
//  VultisigApp
//

import Foundation

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
    
    /// Validate Cardano chain specific parameters
    func validateChainSpecific(_ chainSpecific: BlockChainSpecific) throws {
        guard case .Cardano(let byteFee, let sendMaxAmount, let ttl) = chainSpecific else {
            throw NSError(domain: "CardanoServiceError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid chain specific type for Cardano"])
        }
        
        guard byteFee > 0 else {
            throw NSError(domain: "CardanoServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cardano byte fee must be positive"])
        }
        
        guard ttl > getCurrentUNIXTimestamp() else {
            throw NSError(domain: "CardanoServiceError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cardano TTL must be in the future"])
        }
    }
    
    /// Get current UNIX timestamp (used for TTL validation)
    private func getCurrentUNIXTimestamp() -> UInt64 {
        return UInt64(Date().timeIntervalSince1970)
    }
    
} 