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

        blockchairData.set(coin.blockchairKey, d)

        return d
    }
    
    func fetchSatsPrice(coin: Coin) async throws -> BigInt {
        let cacheKey = "utxo-\(coin.chain.name.lowercased())-fee-price"
        if let cachedData: BigInt = await Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
            return cachedData
        }
        let urlString = Endpoint.blockchairStats(coin.chain.name.lowercased()).absoluteString
        let data = try await Utils.asyncGetRequest(urlString: urlString, headers: [:])
        if let result = Utils.extractResultFromJson(fromData: data, path: "data.suggested_transaction_fee_per_byte_sat"),
           let resultNumber = result as? NSNumber {
            let bigIntResult = BigInt(resultNumber.intValue)
            self.cacheFeePrice[cacheKey] = (data: bigIntResult, timestamp: Date())
            return bigIntResult
        } else {
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
