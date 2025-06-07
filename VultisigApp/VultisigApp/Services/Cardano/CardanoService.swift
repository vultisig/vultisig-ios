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
    
} 