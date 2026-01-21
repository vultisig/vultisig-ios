//
//  BlockchairService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt

actor BlockchairService {

    private init() {}

    static let shared = BlockchairService()

    var blockchairData: ThreadSafeDictionary<String, Blockchair> = ThreadSafeDictionary()

    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]

    func fetchBlockchairData(coin: CoinMeta, address: String) async throws -> Blockchair {
        let coinName = coin.chain.name.lowercased()
        let url = Endpoint.blockchairDashboard(address, coinName)
        let (data, _) = try await URLSession.shared.data(from: url)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let decodedData = try decoder.decode(BlockchairResponse.self, from: data)

        guard let d = decodedData.data[address] else {
            throw Errors.fetchBlockchairDataFailed
        }

        blockchairData.set(blockchairKey(for: coin, address: address), d)

        return d
    }

    func blockchairKey(for coin: CoinMeta, address: String) -> String {
        return "\(address)-\(coin.chain.name.lowercased())"
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

    func getByKey(key: String) -> Blockchair? {
        return blockchairData.get(key)
    }

    /// Clear UTXO cache for a specific address to force fresh UTXO fetch
    func clearUTXOCache(for coin: Coin) {
        blockchairData.remove(coin.blockchairKey)
        print("Cleared UTXO cache for \(coin.chain.name) address: \(coin.address)")
    }

    /// Clear all UTXO cache
    func clearAllUTXOCache() {
        blockchairData.clear()
        print("Cleared all UTXO cache")
    }
}

private extension BlockchairService {

    enum Errors: Error {
        case fetchSatsPriceFailed
        case fetchBlockchairDataFailed
    }
}
