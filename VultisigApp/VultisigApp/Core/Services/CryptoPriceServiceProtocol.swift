//
//  CryptoPriceServiceProtocol.swift
//  VultisigApp
//
//  Test seam over `CryptoPriceService`. Production wiring stays on
//  `CryptoPriceService.shared`; injecting the protocol lets `BalanceService`
//  drive price/rate fetching deterministically in tests without the network.
//

import Foundation

protocol CryptoPriceServiceProtocol {
    func fetchPrices(coins: [CoinMeta]) async throws
    func fetchPrice(coin: Coin) async throws
}

extension CryptoPriceService: CryptoPriceServiceProtocol {}
