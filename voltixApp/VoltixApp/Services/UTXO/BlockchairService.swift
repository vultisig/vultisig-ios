//
//  BlockchairService.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt

class BlockchairService {
    static let shared = BlockchairService()
    private init() {}
    var blockchairData: [String: Blockchair] = [:]
    func fetchBlockchairData(address: String, coin: Coin) async throws -> Blockchair? {
        let coinName = coin.chain.name.lowercased()
        let key = "\(address)-\(coinName)"
        guard let url = URL(string: Endpoint.blockchairDashboard(address, coinName)) else {
            throw HelperError.runtimeError("invalid URL")
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decodedData = try decoder.decode(BlockchairResponse.self, from: data)
            if let blockchairData = decodedData.data[coin.address] {
                self.blockchairData[key] = blockchairData
                return blockchairData
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            throw error
        }
        return nil
    }
    
    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]
    func fetchSatsPrice(coin:Coin) async throws -> BigInt {
        let cacheKey = "utxo-\(coin.chain.name.lowercased())-fee-price"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return cachedData
        }
        let urlString = Endpoint.blockchairStats(coin.chain.name.lowercased())
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
