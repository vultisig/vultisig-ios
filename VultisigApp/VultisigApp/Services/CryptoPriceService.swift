import Foundation
import SwiftUI

public class CryptoPriceService: ObservableObject {
    
    public static let shared = CryptoPriceService()
    
    private init() {}

    func fetchPrices(vault: Vault) async throws {
        let coin = vault.coins
            .map { $0.priceProviderId }
            .joined(separator: ",")

        let fiat = SettingsCurrency.allCases
            .map { $0.rawValue }
            .joined(separator: ",")

        let url = Endpoint.fetchCryptoPrices(coin: coin, fiat: fiat)
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode([String: [String: Double]].self, from: data)

        let rates: [[Rate]] = response.map { crypto, map in
            return SettingsCurrency.allCases.compactMap { currency in
                let fiat = currency.rawValue.lowercased()
                guard let value = map[fiat] else {
                    return nil
                }
                return Rate(fiat: fiat, crypto: crypto, value: value)
            }
        }

        RateProvider.shared.subscribe {
            vault.objectWillChange.send()
        }

        try await RateProvider.shared.save(rates: Array(rates.joined()))
    }
}
