//
//  BlockchairService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt

//TODO: Next PR I should must this to UTXO service
@MainActor
public class BlockchairService: ObservableObject {
    static let shared = BlockchairService()
    private init() {}
    
    @Published var blockchairData: [String: Blockchair] = [:]
    @Published var errorMessage: [String: String] = [:]
    
    func fetchBlockchairData(for tx: SendTransaction) async {
        
        let address = tx.fromAddress
        let coinName = tx.coin.chain.name.lowercased()
        let key = "\(address)-\(coinName)"
        
        guard let url = URL(string: Endpoint.blockchairDashboard(address, coinName)) else {
            print("Invalid URL")
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decodedData = try decoder.decode(BlockchairResponse.self, from: data)
            if let blockchairData = decodedData.data[address] {
                self.blockchairData[key] = blockchairData
            }
        } catch let error as DecodingError {
            self.errorMessage[key] = Utils.handleJsonDecodingError(error)
        } catch {
            print("Error: \(error.localizedDescription)")
            self.errorMessage[key] = "Error: \(error.localizedDescription)"
        }
    }
    
    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]
    func fetchSatsPrice(tx: SendTransaction) async throws -> BigInt {
        
        let cacheKey = "utxo-\(tx.coin.chain.name.lowercased())-fee-price"
        
        do {
            if let cachedData: BigInt = try await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
                return cachedData
            }
        } catch {
            throw error
        }
        
        let urlString = Endpoint.blockchairStats(tx.coin.chain.name.lowercased())
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        
        if let result = Utils.extractResultFromJson(fromData: data, path: "data.suggested_transaction_fee_per_byte_sat"),
           let resultNumber = result as? NSNumber {
            let bigIntResult = BigInt(resultNumber.intValue)
            self.cacheFeePrice[cacheKey] = (data: bigIntResult, timestamp: Date())
            return bigIntResult
        } else {
            print("JSON decoding error")
        }
        return BigInt(-1)
    }
}
