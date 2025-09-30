//
//  RateStorage.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 07.08.2024.
//

import Foundation
import Combine
import SwiftData

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

final class RateProvider {
    static let shared = RateProvider()

    /// Should be updated manually
    // private var rates = Set<Rate>()
    private var cachedRates = NSCache<NSString, Rate>()

    private init() {
        let descriptor = FetchDescriptor<DatabaseRate>()
        do {
            let objects = try Storage.shared.modelContext.fetch(descriptor)
            objects.forEach {
                let identifier = Rate.identifier(fiat: $0.fiat, crypto: $0.crypto)
                cachedRates.setObject(Rate(object: $0), forKey: identifier as NSString)
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func fiatBalance(value: Decimal, cryptoId: CryptoId, currency: SettingsCurrency = .current) -> Decimal {
        guard let rate = rate(cryptoId: cryptoId, currency: currency) else {
            return .zero
        }
        return value * Decimal(rate.value)
    }

    func fiatBalanceString(value: Decimal, cryptoId: CryptoId, currency: SettingsCurrency = .current) -> String {
        let balance = fiatBalance(value: value, cryptoId: cryptoId, currency: currency)
        return balance.formatToFiat(includeCurrencySymbol: true)
    }

    func rate(cryptoId: CryptoId, currency: SettingsCurrency = .current) -> Rate? {
        let identifier = Rate.identifier(fiat: currency.rawValue, crypto: cryptoId.id)
        return self.cachedRates.object(forKey: identifier as NSString)
    }

    @MainActor func save(rates newRates: [Rate]) throws {
        // if a rate is newer , we use the newer one
        newRates.forEach {
            let identifier = Rate.identifier(fiat: $0.fiat, crypto: $0.crypto)
            self.cachedRates.setObject($0, forKey: identifier as NSString)
        }
        
        Storage.shared.insert(newRates.map { $0.mapToObject() })
        try Storage.shared.modelContext.save()
    }
}
