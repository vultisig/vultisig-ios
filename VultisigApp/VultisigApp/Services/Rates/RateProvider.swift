//
//  RateStorage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import Combine
import SwiftData

final class RateProvider {

    static let shared = RateProvider()

    private var rates: [Rate] = []

    private var cancallables = Set<AnyCancellable>()

    private init() {
        let descriptor = FetchDescriptor<Rate>()

        do {
            self.rates = try Storage.shared.modelContext.fetch(descriptor)

            try Storage.shared.modelContext
                .fetch(descriptor)
                .publisher
                .collect()
                .sink { [weak self] rates in
                    self?.rates = rates
                }.store(in: &cancallables)

        } catch {
            fatalError(error.localizedDescription)
        }
    }

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

    func rate(for coin: Coin, currency: SettingsCurrency = .current) -> Rate? {
        let identifier = Rate.identifier(fiat: currency.rawValue.lowercased(), crypto: coin.priceProviderId)
        return rates.first(where: { $0.id == identifier })
    }

    @MainActor func save(rates: [Rate]) async throws {
        await Storage.shared.insert(rates)
    }
}
