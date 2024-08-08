import Foundation
import SwiftUI

public class CryptoPriceService: ObservableObject {

    struct ResolvedSources {
        let providerIds: [String]
        let contracts: [Chain: [String]]
    }

    public static let shared = CryptoPriceService()
    
    private init() {}

    func fetchPrices(vault: Vault) async throws {
        try await fetchPrices(coins: vault.coins)

        await refresh(vault: vault)
        await refresh(coins: vault.coins)
    }

    func fetchPrice(coin: Coin) async throws {
        try await fetchPrices(coins: [coin])

        await refresh(coins: [coin])
    }
}

private extension CryptoPriceService {

    @MainActor func refresh(vault: Vault) {
        vault.objectWillChange.send()
    }

    @MainActor func refresh(coins: [Coin]) {
        for coin in coins {
            coin.objectWillChange.send()
        }
    }

    func fetchPrices(coins: [Coin]) async throws {
        let sources = resolveSources(coins: coins)

        if !sources.providerIds.isEmpty {
            try await fetchPrices(ids: sources.providerIds)
        }

        if !sources.contracts.isEmpty {
            for (chain, contracts) in sources.contracts {
                try await fetchPrices(contracts: contracts, chain: chain)
            }
        }
    }

    func resolveSources(coins: [Coin]) -> ResolvedSources {
        var providerIds: [String] = []
        var contracts: [Chain: [String]] = [:]

        for coin in coins {
            switch RateProvider.cryptoId(for: coin) {
            case .priceProvider(let id):
                providerIds.append(id)
            case .contract(let id):
                contracts[coin.chain, default: []].append(id)
            }
        }

        return ResolvedSources(providerIds: providerIds, contracts: contracts)
    }

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
