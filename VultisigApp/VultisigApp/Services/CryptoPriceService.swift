import Foundation
import SwiftUI

public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private init() {}

    func fetchPrices(vault: Vault) async throws {
        let ids = vault.coins
            .map { $0.priceProviderId }
            .joined(separator: ",")

        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        RateProvider.shared.subscribe {
            vault.objectWillChange.send()
        }

        try await fetchPrices(ids: ids, currencies: currencies)
    }

    func fetchPrice(coin: Coin) async throws {
        let ids = coin.ticker.lowercased()

        let currencies = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        try await fetchPrices(ids: ids, currencies: currencies)
    }
}

private extension CryptoPriceService {

    func fetchPrices(ids: String, currencies: String) async throws {
        let url = Endpoint.fetchCryptoPrices(ids: ids, currencies: currencies)
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)

        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else { return nil }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }

        try await RateProvider.shared.save(rates: Array(rates.joined()))
    }
}
