//
//  BlockchairService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt

class BlockchairService {
    
    static let shared = BlockchairService()

    var blockchairData: ThreadSafeDictionary<String,Blockchair> = ThreadSafeDictionary()

    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]

    private init() {}

    func fetchBlockchairData(coin: Coin) async throws -> Blockchair {
        let coinName = coin.chain.name.lowercased()
        let url = Endpoint.blockchairDashboard(coin.address, coinName)
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let decodedData = try decoder.decode(BlockchairResponse.self, from: data)

        guard let d = decodedData.data[coin.address] else {
            throw Errors.fetchBlockchairDataFailed
        }

        // DETAILED UTXO LOGGING - This will show you exactly what UTXOs you have
        print("=== DETAILED UTXO ANALYSIS FOR \(coin.ticker) ===")
        print("Address: \(coin.address)")
        print("Chain: \(coinName)")
        
        if let utxos = d.utxo {
            let totalBalance = utxos.reduce(0) { $0 + Int64($1.value ?? 0) }
            let dustThreshold = coin.coinType.getFixedDustThreshold()
            let usableUtxos = utxos.filter { ($0.value ?? 0) >= Int(dustThreshold) }
            let dustUtxos = utxos.filter { ($0.value ?? 0) < Int(dustThreshold) }
            
            print("📊 UTXO SUMMARY:")
            print("  Total UTXOs: \(utxos.count)")
            print("  Total Balance: \(totalBalance) satoshis (\(Double(totalBalance)/100_000_000) \(coin.ticker))")
            print("  Dust Threshold: \(dustThreshold) satoshis")
            print("  Usable UTXOs: \(usableUtxos.count)")
            print("  Dust UTXOs: \(dustUtxos.count)")
            
            if !usableUtxos.isEmpty {
                let usableBalance = usableUtxos.reduce(0) { $0 + Int64($1.value ?? 0) }
                print("  Usable Balance: \(usableBalance) satoshis (\(Double(usableBalance)/100_000_000) \(coin.ticker))")
                
                print("\n💰 USABLE UTXOs (above dust):")
                for (index, utxo) in usableUtxos.enumerated() {
                    let value = utxo.value ?? 0
                    let hash = utxo.transactionHash ?? "unknown"
                    let idx = utxo.index ?? -1
                    print("  [\(index+1)] \(value) sats (\(Double(value)/100_000_000) \(coin.ticker)) - \(hash):\(idx)")
                }
            }
            
            if !dustUtxos.isEmpty {
                let dustBalance = dustUtxos.reduce(0) { $0 + Int64($1.value ?? 0) }
                print("\n🗑️  DUST UTXOs (below threshold):")
                print("  Count: \(dustUtxos.count)")
                print("  Total Dust: \(dustBalance) satoshis (\(Double(dustBalance)/100_000_000) \(coin.ticker))")
                
                // Show first 10 dust UTXOs as examples
                let sampleDust = Array(dustUtxos.prefix(10))
                for (index, utxo) in sampleDust.enumerated() {
                    let value = utxo.value ?? 0
                    let hash = utxo.transactionHash ?? "unknown"
                    let idx = utxo.index ?? -1
                    print("  [\(index+1)] \(value) sats (\(Double(value)/100_000_000) \(coin.ticker)) - \(hash):\(idx)")
                }
                if dustUtxos.count > 10 {
                    print("  ... and \(dustUtxos.count - 10) more dust UTXOs")
                }
            }
            
            // Show UTXO size distribution
            print("\n📈 UTXO SIZE DISTRIBUTION:")
            let ranges = [
                (0, 1000, "Micro (0-1000 sats)"),
                (1000, 10000, "Small (1K-10K sats)"),
                (10000, 100000, "Medium (10K-100K sats)"),
                (100000, 1000000, "Large (100K-1M sats)"),
                (1000000, Int.max, "Huge (1M+ sats)")
            ]
            
            for (min, max, label) in ranges {
                let count = utxos.filter { 
                    let val = $0.value ?? 0
                    return val >= min && (max == Int.max ? true : val < max)
                }.count
                if count > 0 {
                    print("  \(label): \(count) UTXOs")
                }
            }
            
        } else {
            print("❌ NO UTXOs FOUND!")
        }
        
        print("=== END UTXO ANALYSIS ===\n")

        blockchairData.set(coin.blockchairKey, d)

        return d
    }
    
    func fetchSatsPrice(coin: Coin) async throws -> BigInt {
        let cacheKey = "utxo-\(coin.chain.name.lowercased())-fee-price"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            print("\n💾 USING CACHED FEE DATA:")
            print("  Cache key: \(cacheKey)")
            print("  Cached fee: \(cachedData) sats/byte")
            print("  In DOGE: \(Double(Int64(cachedData))/100_000_000) DOGE/byte")
            return cachedData
        }
        
        let urlString = Endpoint.blockchairStats(coin.chain.name.lowercased()).absoluteString
        print("\n🌐 FETCHING FEE FROM BLOCKCHAIR:")
        print("  URL: \(urlString)")
        
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        // Log the raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("  Raw JSON response: \(jsonString)")
        }
        
        if let result = Utils.extractResultFromJson(fromData: data, path: "data.suggested_transaction_fee_per_byte_sat"),
           let resultNumber = result as? NSNumber {
            let bigIntResult = BigInt(resultNumber.intValue)
            
            print("  Extracted fee value: \(resultNumber)")
            print("  As BigInt: \(bigIntResult) sats/byte")
            print("  In DOGE: \(Double(Int64(bigIntResult))/100_000_000) DOGE/byte")
            print("  ⚠️  THIS LOOKS SUSPICIOUS IF > 1000 sats/byte!")
            
            self.cacheFeePrice[cacheKey] = (data: bigIntResult, timestamp: Date())
            return bigIntResult
        } else {
            print("  ❌ Failed to extract fee from JSON")
            throw Errors.fetchSatsPriceFailed
        }
    }
}

private extension BlockchairService {

    enum Errors: Error {
        case fetchSatsPriceFailed
        case fetchBlockchairDataFailed
    }
}
