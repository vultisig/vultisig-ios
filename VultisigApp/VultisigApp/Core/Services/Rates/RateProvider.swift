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

    static func cryptoId(for coin: CoinMeta) -> CryptoId {
        switch coin.chain.chainType {
        case .EVM, .Solana, .Sui, .THORChain:
            if coin.isNativeToken || !coin.priceProviderId.isEmpty {
                return .priceProvider(coin.priceProviderId)
            } else {
                return .contract(coin.contractAddress)
            }
        default:
            return .priceProvider(coin.priceProviderId)
        }
    }

    /// Should be updated manually - thread-safe backing storage
    private var _rates = Set<Rate>()
    private var ratesLock = os_unfair_lock()
    private let initQueue = DispatchQueue(label: "com.vultisig.rateprovider.init")

    /// Thread-safe access to rates
    private var rates: Set<Rate> {
        get {
            os_unfair_lock_lock(&ratesLock)
            defer { os_unfair_lock_unlock(&ratesLock) }
            return _rates
        }
        set {
            os_unfair_lock_lock(&ratesLock)
            defer { os_unfair_lock_unlock(&ratesLock) }
            _rates = newValue
        }
    }

    private init() {
        // Defer the database fetch to avoid re-entrant calls during SwiftData operations
        // This prevents the crash caused by calling fetch() while SwiftData is already
        // processing another fetch/register operation
        initQueue.async { [weak self] in
            guard let self = self else { return }

            let descriptor = FetchDescriptor<DatabaseRate>()

            do {
                let objects = try Storage.shared.modelContext.fetch(descriptor)
                let loadedRates = Set(objects.map { Rate(object: $0) })

                // Thread-safe assignment via computed property
                self.rates = loadedRates
            } catch {
                print("Failed to load rates: \(error.localizedDescription)")
            }
        }
    }

    func fiatBalance(value: Decimal, rate: Rate) -> Decimal {
        let result = value * Decimal(rate.value)
        // Don't truncate here - let the formatter handle precision
        return result
    }

    func fiatBalance(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> Decimal {
        fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
    }

    func fiatBalance(value: Decimal, coin: CoinMeta, currency: SettingsCurrency = .current) -> Decimal {
        guard let rate = rate(for: coin, currency: currency) else {
            return .zero
        }
        return fiatBalance(value: value, rate: rate)
    }

    func fiatBalance(for coin: Coin, currency: SettingsCurrency = .current) -> Decimal {
        return fiatBalance(value: coin.balanceDecimal, coin: coin.toCoinMeta(), currency: currency)
    }

    func fiatBalanceString(for coin: Coin, currency: SettingsCurrency = .current) -> String {
        return fiatBalanceString(value: coin.balanceDecimal, coin: coin, currency: currency)
    }

    func fiatBalanceString(value: Decimal, rate: Rate) -> String {
        let balance = fiatBalance(value: value, rate: rate)
        return balance.formatToFiat(includeCurrencySymbol: true)
    }

    func fiatBalanceString(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
        return balance.formatToFiat(includeCurrencySymbol: true)
    }

    /// Format fiat balance for fee display with more decimal places (e.g., $0.0065 instead of $0.00)
    func fiatFeeString(value: Decimal, coin: Coin, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(value: value, coin: coin.toCoinMeta(), currency: currency)
        return balance.formatToFiatForFee(includeCurrencySymbol: true)
    }

    func rate(for coin: Coin, currency: SettingsCurrency = .current) -> Rate? {
        rate(for: coin.toCoinMeta(), currency: currency)
    }

    func rate(for coin: CoinMeta, currency: SettingsCurrency = .current) -> Rate? {
        let cryptoId = RateProvider.cryptoId(for: coin)
        let identifier = Rate.identifier(fiat: currency.rawValue, crypto: cryptoId.id)
        return rates.first(where: { $0.id == identifier })
    }

    @MainActor func save(rates newRates: [Rate]) throws {
        // if a rate is newer , we use the newer one
        let newRateIds = Set(newRates.map { $0.id })
        rates = rates.filter { !newRateIds.contains($0.id) }.union(newRates)

        // Update existing or insert new rates
        for rate in newRates {
            let rateId = rate.id // Capture the value outside the predicate
            let descriptor = FetchDescriptor<DatabaseRate>(
                predicate: #Predicate { $0.id == rateId }
            )

            if let existingRate = try Storage.shared.modelContext.fetch(descriptor).first {
                // Update existing rate
                existingRate.fiat = rate.fiat
                existingRate.crypto = rate.crypto
                existingRate.value = rate.value
            } else {
                // Insert new rate
                Storage.shared.insert(rate.mapToObject())
            }
        }

        try Storage.shared.modelContext.save()
    }
}
