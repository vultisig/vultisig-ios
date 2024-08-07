//
//  RateStorage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import SwiftUI
import SwiftData

final class RateProvider {

    static let shared = RateProvider()

    @Query var rates: [Rate]

    private init() { }

    func fiatBalance(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> Decimal {
        guard let rate = rate(for: coin, currency: currency) else {
            return .zero
        }
        return value * Decimal(rate.value)
    }

    func fiatBalance(for coin: Coin, currency: SettingsCurrency = .current) -> Decimal {
        return fiatBalance(value: coin.balanceDecimal, coin: coin, currency: currency)
    }

    func fiatBalanceString(for coin: Coin, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(for: coin, currency: currency)
        let balanceString = "\(balance) \(coin.ticker)"
        return balanceString
    }

    func rate(for coin: Coin, currency: SettingsCurrency) -> Rate? {
        let identifier = Rate.identifier(fiat: currency.rawValue, crypto: coin.priceProviderId)
        return rates.first(where: { $0.id == identifier })
    }

    @MainActor func save(value: Double, coin: Coin, currency: SettingsCurrency) async throws {
        let rate = rate(for: coin, currency: currency) ?? makeRate(coin: coin, currency: currency)
        rate.value = value

        try Storage.shared.modelContext.save()
    }
}

private extension RateProvider {

    func makeRate(coin: Coin, currency: SettingsCurrency) -> Rate {
        return Rate(fiat: currency.rawValue, crypto: coin.priceProviderId)
    }
}
