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

    enum CryptoId {
        case priceProvider(String)
        case contract(String)

        var id: String {
            switch self {
            case .priceProvider(let value):
                return value
            case .contract(let value):
                return value
            }
        }
    }

    static let shared = RateProvider()

    static func cryptoId(for coin: Coin) -> CryptoId {
        switch coin.chain.chainType {
        case .EVM:
            if coin.isNativeToken {
                return .priceProvider(coin.priceProviderId)
            } else {
                return .contract(coin.contractAddress)
            }
        default:
            return .priceProvider(coin.priceProviderId)
        }
    }

    /// Should be updated manually
    private var rates = Set<Rate>()
    private var cancallables = Set<AnyCancellable>()

    private init() {
        let descriptor = FetchDescriptor<DatabaseRate>()

        do {
            let objects = try Storage.shared.modelContext.fetch(descriptor)
            self.rates = Set(objects.map { Rate(object: $0) })
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
        let cryptoId = RateProvider.cryptoId(for: coin)
        let identifier = Rate.identifier(fiat: currency.rawValue, crypto: cryptoId.id)
        return rates.first(where: { $0.id == identifier })
    }

    @MainActor func save(rates newRates: [Rate]) async throws {
        rates = rates.union(newRates)
        await Storage.shared.insert(newRates.map { $0.mapToObject() })
    }
}
