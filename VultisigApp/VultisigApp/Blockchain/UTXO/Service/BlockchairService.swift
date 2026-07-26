//
//  BlockchairService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/03/2024.
//

import Foundation
import BigInt
import OSLog

actor BlockchairService {

    private let logger = Logger(subsystem: "com.vultisig.app", category: "blockchair-service")
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    static let shared = BlockchairService()

    var blockchairData: ThreadSafeDictionary<String, Blockchair> = ThreadSafeDictionary()

    private var cacheFeePrice: [String: (data: BigInt, timestamp: Date)] = [:]

    func fetchBlockchairData(coin: CoinMeta, address: String) async throws -> Blockchair {
        let response = try await fetchBlockchairResponse(coin: coin, address: address)

        guard let d = response.data[address] else {
            throw Errors.fetchBlockchairDataFailed
        }

        blockchairData.set(blockchairKey(for: coin, address: address), d)

        return d
    }

    /// Fetches the full Blockchair dashboard response (data + request
    /// `context`). `fetchBlockchairData` wraps this to return only the
    /// per-address entry; the QBTC claim flow uses the raw response to read
    /// `context.state` (the chain tip) for confirmation counting.
    func fetchBlockchairResponse(coin: CoinMeta, address: String) async throws -> BlockchairResponse {
        let coinName = coin.chain.name.lowercased()
        return try await httpClient.request(
            BlockchairAPI.dashboard(address: address, chain: coinName),
            responseType: BlockchairResponse.self
        ).data
    }

    func blockchairKey(for coin: CoinMeta, address: String) -> String {
        return "\(address)-\(coin.chain.name.lowercased())"
    }

    func fetchSatsPrice(coin: Coin) async throws -> BigInt {
        let cacheKey = "utxo-\(coin.chain.name.lowercased())-fee-price"
        if let cachedData: BigInt = Utils.getCachedData(cacheKey: cacheKey, cache: cacheFeePrice, timeInSeconds: 60*5) {
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
        logger.info("Cleared UTXO cache for \(coin.chain.name) address: \(coin.address)")
    }

}

private extension BlockchairService {

    enum Errors: Error {
        case fetchSatsPriceFailed
        case fetchBlockchairDataFailed
    }
}
