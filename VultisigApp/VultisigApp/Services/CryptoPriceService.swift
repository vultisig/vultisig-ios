import Foundation
import SwiftUI

public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private init() {}

    func fetchPrices(vault: Vault) async throws {
        let ids = vault.coins.map { $0.priceProviderId }

        RateProvider.shared.subscribe {
            vault.objectWillChange.send()
        }

        try await fetchPrices(ids: ids)
    }

    func fetchPrice(coin: Coin) async throws {
        let ids = coin.priceProviderId.lowercased()
        try await fetchPrices(ids: [ids])
    }
}

private extension CryptoPriceService {

    func fetchPrices(ids: [String]) async throws {
        let idsQuery = ids
            .filter { !$0.isEmpty }
            .joined(separator: ",")

        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        let url = Endpoint.fetchCryptoPrices(
            ids: idsQuery,
            currencies: currencies
        )

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)

        try await RateProvider.shared.save(rates: mapRates(response: response))
    }

    func fetchPrices(contracts: [String], chain: Chain) async throws {
        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        let url = Endpoint.fetchTokenPrice(
            network: coinGeckoPlatform(chain: chain),
            addresses: contracts,
            currencies: currencies
        )

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)

        try await RateProvider.shared.save(rates: mapRates(response: response))
    }

    func mapRates(response: [String: [String: Double]]) -> [Rate] {
        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else { return nil }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }

        return Array(rates.joined())
    }

    private func coinGeckoPlatform(chain: Chain) -> String {
        switch chain {
        case .ethereum:
            return "ethereum"
        case .avalanche:
            return "avalanche"
        case .base:
            return "base"
        case .blast:
            return "blast"
        case .arbitrum:
            return "arbitrum-one"
        case .polygon:
            return "polygon-pos"
        case .optimism:
            return "optimistic-ethereum"
        case .bscChain:
            return "binance-smart-chain"
        case .zksync:
            return "zksync"
        case .thorChain, .solana, .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .gaiaChain, .kujira, .mayaChain, .cronosChain, .polkadot, .dydx, .sui:
            return .empty
        }
    }
}
